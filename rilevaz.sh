#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Optional debug: export DEBUG=1 to enable bash tracing
if [ "${DEBUG:-0}" = "1" ]; then
    set -x
fi

# Base folder to scan
# Default: two levels up from this repo (e.g., from zdev/monthly-commit-report to work)
# You can override via env: e.g., BASE_PATH=. to scan only current folder
BASE_PATH="${BASE_PATH:-../..}"

# Comma-separated list of top-level directories to exclude from scan (relative to BASE_PATH)
# Default excludes 'zdev' so repos inside zdev (including this repo) are ignored
EXCLUDE_DIRS="${EXCLUDE_DIRS:-zdev}"

# Default author fallback; can be overridden via env AUTHOR_NAME or AUTHOR
AUTHOR="${AUTHOR_NAME:-${AUTHOR:-c.accolito}}"
FROM_DATE="$(date +%Y-%m-01)"
TO_DATE="now"
LOG_FILE="" # no report file, prints to stdout

# Accumulator: number of unique commit days per top-level group
declare -A GROUP_DAY_COUNT

# Accumulator: list of days (DD) per group, as a string list
declare -A GROUP_DAY_LIST

# Accumulator: set of unique days per group
declare -A GROUP_DAY_SET

# Temporary directory to aggregate results from parallel jobs
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

is_git_repo() { [ -d "$1/.git" ]; }

get_git_commits() {
    local repo_path="$1"
    # Detect repo-specific author (name/email) and try sequentially
    local repo_email
    local repo_name
    # Allow override via env AUTHOR_EMAIL/AUTHOR_NAME if set
    repo_email=$(git -C "$repo_path" config user.email 2>/dev/null || true)
    [ -n "${AUTHOR_EMAIL:-}" ] && repo_email="${AUTHOR_EMAIL}"
    repo_name=$(git -C "$repo_path" config user.name 2>/dev/null || true)
    [ -n "${AUTHOR_NAME:-}" ] && repo_name="${AUTHOR_NAME}"

    local log_out=""
    # 1) Try email
    if [ -n "$repo_email" ]; then
        log_out=$(git -C "$repo_path" log --since="$FROM_DATE" --until="$TO_DATE" --author="$repo_email" --pretty=format:"%H|%ad|%s" --date=iso 2>/dev/null || true)
    fi
    # 2) If empty, try name
    if [ -z "$log_out" ] && [ -n "$repo_name" ]; then
        log_out=$(git -C "$repo_path" log --since="$FROM_DATE" --until="$TO_DATE" --author="$repo_name" --pretty=format:"%H|%ad|%s" --date=iso 2>/dev/null || true)
    fi
    # 3) If still empty, try fallback AUTHOR
    if [ -z "$log_out" ]; then
        log_out=$(git -C "$repo_path" log --since="$FROM_DATE" --until="$TO_DATE" --author="$AUTHOR" --pretty=format:"%H|%ad|%s" --date=iso 2>/dev/null || true)
    fi

    # Return only non-empty lines with the expected separator
    printf "%s\n" "$log_out" | awk -F"|" 'NF>=3'
}

build_italian_summary() {
    if [ "$#" -eq 0 ]; then echo "No commits in the selected period."; return; fi
    echo "Main activities (summary from commit messages):"
    local count=0
    for line in "$@"; do
        local subject
        subject=$(echo "$line" | awk -F"|" '{print $3}')
        [ -n "$subject" ] && echo "- ${subject}"
        count=$((count+1))
        [ $count -ge 8 ] && break
    done
}

count_commit_days() {
    if [ "$#" -eq 0 ]; then echo 0; return; fi
    for line in "$@"; do
        echo "$line" | awk -F"|" '{print $2}' | awk '{print $1}'
    done | sort -u | wc -l
}

cd "$BASE_PATH" || { echo "Base path not found: $BASE_PATH"; exit 1; }

## Search nested git repos: find all folders containing .git
echo "[INFO] Starting scan in: $BASE_PATH" 1>&2
# Print the period once
echo "Period: from $FROM_DATE to $(date +%Y-%m-%d)"
# Limit depth to avoid slow scans
mapfile -t repo_dirs < <(find . -maxdepth 4 -type d -name ".git" -printf "%h\n" 2>/dev/null)

# Apply directory exclusions (skip any repos under excluded top-level dirs)
if [ -n "$EXCLUDE_DIRS" ] && [ "${#repo_dirs[@]}" -gt 0 ]; then
    IFS=',' read -r -a _EXCLUDES <<< "$EXCLUDE_DIRS"
    _filtered=()
    for _d in "${repo_dirs[@]}"; do
        _rel="${_d#./}"
        _skip=0
        for _ex in "${_EXCLUDES[@]}"; do
            # trim spaces
            _ex_trim="${_ex//[[:space:]]/}"
            [ -z "$_ex_trim" ] && continue
            # Match if path starts with excluded dir name (top-level)
            if [[ "$_rel" == "$_ex_trim"* ]]; then
                _skip=1
                break
            fi
        done
        [ "$_skip" -eq 0 ] && _filtered+=("$_d")
    done
    repo_dirs=("${_filtered[@]}")
fi
echo "[INFO] Repositories found: ${#repo_dirs[@]}" 1>&2
echo

LAST_GROUP=""

# Concurrency settings: set PARALLEL_JOBS to desired number (e.g., 4)
PARALLEL_JOBS=${PARALLEL_JOBS:-4}
active_jobs=0

run_repo() {
    local dir="$1"
    local last_group_ref="$2"
    [ -d "$dir" ] || return 0
    if is_git_repo "$dir"; then
        repo_name=$(basename "$dir")
        mapfile -t commits < <(get_git_commits "$dir")
        # Filter out empty or malformed lines (defense in depth)
        mapfile -t commits < <(printf "%s\n" "${commits[@]}" | awk -F"|" 'NF>=3')
        commit_count=${#commits[@]}
        # If there are no commits, skip printing and continue
        if [ "$commit_count" -eq 0 ]; then
            return 0
        fi
        days_with_commits=$(count_commit_days "${commits[@]}")
        if [ "$days_with_commits" -eq 0 ]; then
            # No valid dates found; treat as no printable commits
            return 0
        fi
        # Human-friendly header: group (top-level folder) + repo in blue
        rel_path=${dir#"./"}
        group_name=${rel_path%%/*}

        # Group header (printed once per group)
        headers_dir="$TMP_DIR/headers"
        mkdir -p "$headers_dir"
        if mkdir "$headers_dir/$group_name" 2>/dev/null; then
            group_upper=${group_name^^}
            printf "\033[33m%s %s\033[0m\n" "$group_upper" "___________________________________________________"
            echo 
        fi

        # Compute list of unique days and print in compact form
        unique_days=$(printf "%s\n" "${commits[@]}" | awk -F"|" '{print $2}' | awk '{print $1}' | sort -u)

        # Extract day numbers (DD) for compact header (no leading zeros)
        days_compact=$(printf "%s\n" "$unique_days" | awk -F"-" '{print $3+0}' | sort -n | paste -sd ' ' -)
        month_num=$(printf "%s\n" "$unique_days" | head -n1 | awk -F"-" '{print $2}')
        
        

        # Header: group normal, repo name in bright cyan
        printf "[%s] \033[96m%s\033[0m\n" "$group_name" "$repo_name"

        # Print commits as [DD] subject
        printf "%s\n" "${commits[@]}" | awk -F"|" '{split($2, a, /[ -]/); day=a[3]+0; printf("[%d] %s\n", day, $3)}'
        
        # One-line italic summary
        if [ -n "$unique_days" ] && [ -n "$days_compact" ]; then
            printf "\033[3mTotal days: %d (this month: %s)\033[0m\n" "$days_with_commits" "$days_compact"
        else
            printf "\033[3mTotal days: %d (none this month)\033[0m\n" "$days_with_commits"
        fi
        echo
        # Aggregate days per group into temp files (avoid subshell issues)
        if [ -n "$group_name" ] && [ -n "$unique_days" ]; then
            printf "%s\n" "$unique_days" | awk -F"-" '{print $3+0}' >> "$TMP_DIR/group_${group_name}.days"
        fi
    else
        echo "[INFO] Skipping (not a git repo): $dir" 1>&2
    fi
}

for dir in "${repo_dirs[@]}" ; do
    run_repo "$dir" "$LAST_GROUP" &
    active_jobs=$((active_jobs+1))
    if [ "$active_jobs" -ge "$PARALLEL_JOBS" ]; then
        wait -n 2>/dev/null || wait
        active_jobs=$((active_jobs-1))
    fi
done

# Wait for any remaining background jobs
wait

# Print summary of days per top-level group (from temp files)
mapfile -t group_files < <(ls -1 "$TMP_DIR"/group_*.days 2>/dev/null || true)
if [ "${#group_files[@]}" -gt 0 ]; then
    echo
    for file in "${group_files[@]}"; do
        grp_name=$(basename "$file")
        grp_name=${grp_name#group_}
        grp_name=${grp_name%.days}
        # Compute sorted unique days
        days_str=$(awk 'NF>0' "$file" | sort -n | uniq | paste -sd ' ' -)
        day_count=$(awk 'NF>0' "$file" | sort -n | uniq | wc -l)
        printf "\033[33m%s days %s\033[0m\n" "$day_count" "$grp_name"
        if [ -n "$days_str" ]; then
            bracketed="["$(printf "%s\n" "$days_str" | tr ' ' '\n' | paste -sd ',' -)"]"
            echo "$bracketed"
        fi
        echo
    done
fi

# Notes:
# - Run this script from the monthly-commit-report folder to scan the parent directory by default.
# - Override BASE_PATH to target a specific directory: BASE_PATH=. bash rilevaz.sh
# - Set AUTHOR_NAME or AUTHOR_EMAIL to filter commits by a specific identity.
# - Use PARALLEL_JOBS to control concurrency when scanning many repositories.
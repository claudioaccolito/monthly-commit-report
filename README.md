# rilevaz.sh

A Bash script to scan Git repositories and summarize your commits from the first day of the current month to today.

Default behavior: place this repository folder (`monthly-commit-report`) inside the `zdev` folder under your main workspace (e.g., `work/zdev`). When you run the script from inside `monthly-commit-report`, it scans the parent of `zdev` (two levels up, i.e. `work`) and, by default, excludes anything under `zdev` from the scan.

## Features

- Default scan path: parent of `zdev` (two levels up) so it scans `work`.
- `zdev` is excluded by default: repos inside `zdev` are ignored.
- Configurable base path: override with `BASE_PATH=.` to scan only the current folder.
- Configurable exclusions: set `EXCLUDE_DIRS` (comma-separated) to skip directories.
- Per-repo output:
  - Cyan group separator and label (e.g., `==== group-a ====`).
  - Blue repo header: `[GROUP] repo-name`.
  - Commit lines with day: `[11] your commit message`.
  - Days summary: `This month: 1 4 10 11` and `Total days: 4`.
- Final per-group summary:
  - Yellow lines: `N days <group>`.
  - Bracketed unique day list: `[1,2,4,10,11]`.
- Parallel processing: configurable concurrency for speed.
- Skips repos without commits in the period.

## Requirements

- Git Bash (Windows) or a Bash-compatible shell.
- Git installed and available in PATH.
- Optional: set env vars `AUTHOR_NAME` or `AUTHOR_EMAIL` to explicitly match your commits without editing the script.

## Folder Structure

Recommended layout: place this repo inside `work/zdev`. The script scans `work` by default and groups repos by the first-level directory name (e.g., `group-a`, `group-b`). Everything under `zdev` is ignored unless you change `EXCLUDE_DIRS`.

```text
work/
  zdev/
    monthly-commit-report/
      rilevaz.sh
    <your-dev-repos>  # excluded by default
  group-a/
    <repo-a>/
      .git/
      ...
    <other-repo>/
      .git/
      ...
  group-b/
    <repo-b>/
      .git/
      ...
  <other-group>/
    <repo>/
      .git/
      ...
```

- Run the script from `monthly-commit-report`; it scans `work` (two levels up) by default and excludes `zdev`.
- Each repository must be a valid Git repo (i.e., contain a `.git` folder).
- The first folder under `work` is treated as the "group" label in output.

## Author Configuration

By default, the script attempts to detect your author identity from each repo's local Git config (`user.email` or `user.name`). If your commits aren’t being counted, explicitly set the author in the script.

Edit `rilevaz.sh` and set the author variables near the top (choose one that matches how commits are recorded in your repos):

```bash
# One of these overrides should match your commit identity
AUTHOR="Fester Addams"         # matches git commit author name
AUTHOR_EMAIL="fester.addams@company.com"  # matches git commit author email
```

### Notes

- Use the exact value that appears in `git log` for your commits.
- If both are set, email usually provides the most reliable match across repos.
- After changing the variable(s), re-run the script from `monthly-commit-report`.

- Use case: to see which shared projects a colleague worked on this month, run the report with their identity, for example:

  ```bash
  AUTHOR_EMAIL="colleague@example.com" ./rilevaz.sh
  # or, if using the alias
  AUTHOR_EMAIL="colleague@example.com" rilevaz
  ```
  
  The scan only includes repositories that exist locally on your machine and are shared with that colleague.

Alternatively, use environment variables (recommended for private/public repos):

```powershell
$env:AUTHOR_NAME="Fester Addams"; $env:AUTHOR_EMAIL="fester.addams@company.com"; bash ./rilevaz.sh
```

```bash
AUTHOR_NAME="Fester Addams" AUTHOR_EMAIL="fester.addams@company.com" ./rilevaz.sh
```

## Usage

Run from the `monthly-commit-report` directory (scans `work` and excludes `zdev` by default):

```powershell
bash ./rilevaz.sh
```

Optionally increase parallelization:

```powershell
$env:PARALLEL_JOBS=6; bash ./rilevaz.sh
```

Or in Git Bash:

```bash
PARALLEL_JOBS=6 ./rilevaz.sh
```

Override base path to scan current folder only:

```powershell
$env:BASE_PATH = "."; bash ./rilevaz.sh
```

```bash
BASE_PATH=. ./rilevaz.sh
```

Exclude different directories (comma-separated). By default `zdev` is excluded; set your own list or clear it to include everything:

```powershell
$env:EXCLUDE_DIRS="group-a,archive"; bash ./rilevaz.sh
```

```bash
EXCLUDE_DIRS="group-a,archive" ./rilevaz.sh
```

Include `zdev` in the scan (remove default exclusion):

```powershell
$env:EXCLUDE_DIRS=""; bash ./rilevaz.sh
```

```bash
EXCLUDE_DIRS="" ./rilevaz.sh
```

## Global Alias (Git Bash)

You can create a shell alias to run the report from anywhere. The script now resolves paths relative to its own location, so no extra variables are needed.

Add this to your `~/.bashrc` and reload the shell (`source ~/.bashrc`):

```bash
alias rilevaz='bash "/c/Users/c.accolito/work/zdev/monthly-commit-report/rilevaz.sh"'
```

Tip: you can also place a small wrapper script in `~/bin` and add it to your `PATH` from `~/.bashrc`.

### Alias Usage

After adding the alias and reloading your shell (`source ~/.bashrc`), you can run the report from any folder:

```bash
rilevaz
```

Temporarily set a specific author name or email (handy if detection fails):

```bash
AUTHOR_NAME="Your Name" rilevaz
# or
AUTHOR_EMAIL="your.name@example.com" rilevaz
```

## How It Works

- Finds nested Git repositories via `find . -maxdepth 4 -type d -name ".git"`, then filters out any paths starting with directories listed in `EXCLUDE_DIRS` (default: `zdev`).
- Detects author from local repo config; filters `git log` by author.
- Prints commits grouped by top-level folder (e.g., `group-a`, `group-b`).
- Aggregates per-group unique days using temporary files to ensure safe parallelism.

## Output

- Period header: `Period: from YYYY-MM-01 to YYYY-MM-DD`.
- For each group (cyan separator + label), repos print:
  - `[GROUP] repo-name`
  - Commit lines: `[day] message`
  - Days summary: `This month: ...`, `Total days: N`
- Final group summary in yellow: `N days <group>` and `[d1,d2,...]`.

## Troubleshooting

- No output for some repos: ensure local `user.name` or `user.email` matches the commit author identity used in that repo.
- `zdev` excluded: by default, repos under `zdev` won’t show up. To include them, set `EXCLUDE_DIRS=""`.
- Run from the correct folder: execute the script from inside `monthly-commit-report`.
- Adjust scan depth or parallel jobs if it’s slow: `-maxdepth 4`, `PARALLEL_JOBS`.

## Additional Notes

- Parallel printing may interleave lines from different repos; the script buffers per-group day aggregation to avoid errors and preserves final summaries.
- If you want strict ordering for repo outputs, adapt the script to buffer each repo’s block into temp files and collate by group/repo at the end.
- Publishing: suitable for private repos. Before making public, sanitize sample outputs and avoid hardcoding personal emails/names; prefer env vars.

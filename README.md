# rilevaz.sh

A Bash script to scan Git repositories and summarize your commits from the first day of the current month to today.

Default behavior: place this repository folder (`monthly-commit-report`) inside your parent folder that contains all your Git projects (e.g., `work`). When you run the script from inside `monthly-commit-report`, it scans the parent folder (`..`) and thus all sibling projects.

## Features

- Default scan path: parent folder (`..`) so it scans sibling projects.
- Configurable base path: override with `BASE_PATH=.` to scan only the current folder.
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

Recommended layout: place this repo inside your parent folder that holds all projects (e.g., `work`). The script will scan the parent and group repos by the first-level directory name (e.g., `group-a`, `group-b`).

```text
work/
  monthly-commit-report/
    rilevaz.sh
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

- Run the script from `monthly-commit-report` so it scans `..` (the parent) by default.
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

Alternatively, use environment variables (recommended for private/public repos):

```powershell
$env:AUTHOR_NAME="Fester Addams"; $env:AUTHOR_EMAIL="fester.addams@company.com"; bash ./rilevaz.sh
```

```bash
AUTHOR_NAME="Fester Addams" AUTHOR_EMAIL="fester.addams@company.com" ./rilevaz.sh
```

## Usage

Run from the `monthly-commit-report` directory (scans parent by default):

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
```

## How It Works

- Finds nested Git repositories via `find . -maxdepth 4 -type d -name ".git"`.
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
- Run from the correct folder: the script assumes it is executed inside `work`.
- Adjust scan depth or parallel jobs if it’s slow: `-maxdepth 4`, `PARALLEL_JOBS`.

## Notes

- Parallel printing may interleave lines from different repos; the script buffers per-group day aggregation to avoid errors and preserves final summaries.
- If you want strict ordering for repo outputs, adapt the script to buffer each repo’s block into temp files and collate by group/repo at the end.
 - Publishing: suitable for private repos. Before making public, sanitize sample outputs and avoid hardcoding personal emails/names; prefer env vars.

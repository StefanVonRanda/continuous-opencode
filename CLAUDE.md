# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Continuous OpenCode is a Bash script wrapper (`continuous_opencode.sh`) that automates the OpenCode CLI in continuous development loops. It runs iterations until task completion, managing branches, PRs, CI checks, and merging automatically.

## Build, Lint, and Test Commands

```bash
# Syntax validation (no execution)
bash -n continuous_opencode.sh
bash -n install.sh

# Lint with shellcheck (if installed)
shellcheck continuous_opencode.sh
shellcheck install.sh

# Manual testing
./continuous_opencode.sh --help
./continuous_opencode.sh -p "test task" -m 1 --dry-run
./continuous_opencode.sh -p "test task" -m 1 --disable-commits
```

## High-Level Architecture

### Main Loop Flow

The script operates as a continuous loop with these stages per iteration:

1. **Branch Creation** (`create_branch`, `run_iteration` start)
   - Creates unique branch: `continuous-opencode/iteration-{N}/{timestamp}-{random}`
   - Branches can be disabled with `--disable-branches` or `--disable-commits`

2. **OpenCode Execution** (`run_opencode`)
   - Uses `opencode serve` server mode if available (faster, maintains context)
   - Falls back to `opencode run` without server
   - Captures output and parses for completion signal
   - Spinner animation shows progress during execution

3. **Reviewer Pass** (`run_reviewer`, optional)
   - Runs if `-r/--review-prompt` is provided
   - Secondary validation after main OpenCode run

4. **Commit Changes** (`commit_changes`)
   - Stages all changes with `git add -A`
   - Commits with iteration number and prompt
   - Tracks `NO_CHANGES_COUNT` for early stopping

5. **PR Creation** (`push_and_create_pr`)
   - Pushes branch to origin
   - Creates PR with share link in body via `gh` CLI
   - Stores PR number in `.continuous-opencode-pr` file

6. **CI Monitoring** (`wait_for_pr_checks`)
   - Polls PR status via `gh pr checks`
   - Waits up to 180 iterations (30 minutes)
   - Displays pending/failed counts per poll

7. **Merge & Cleanup** (`merge_pr`, `cleanup_branch`)
   - Merges PR using configured strategy (default: squash)
   - Returns to main/master branch
   - Deletes feature branch locally

### Stopping Conditions

The loop continues until one of these conditions is met:

- `MAX_RUNS` iterations completed
- `MAX_COST` USD spent (tracked via `opencode stats`)
- `MAX_DURATION` elapsed
- `COMPLETION_THRESHOLD` consecutive completion signals detected
- `NO_CHANGES_THRESHOLD` consecutive iterations with no changes

### Server Mode

Uses `opencode serve` for faster iterations:
- Server starts once on available port (starts at 4096, increments if in use)
- All iterations attach via `--attach` flag
- Avoids cold boot overhead, especially important with MCP servers
- Server PID stored in `OPENCODE_SERVER_PID`, cleaned up via `trap` on exit

### Cost Tracking

- Calls `opencode stats --project $(pwd) --format json` after each run
- Parses `totalCostUsd` from JSON response
- Stores as cents in `TOTAL_COST` variable
- Compared against `MAX_COST` in `should_continue()`

### AGENTS.md Context

OpenCode is instructed to use `AGENTS.md` as external memory between iterations:
- File is auto-created if missing with template
- OpenCode naturally reads this for project context (native OpenCode format)
- Agents should leave notes about progress and next steps

### Git Worktree Support

Parallel execution via worktrees:
- `--worktree <name>` creates isolated working directory
- Worktrees stored in `../continuous-opencode-worktrees/` by default
- `--cleanup-worktree` removes worktree after completion
- `--list-worktrees` shows active worktrees

### Share Links

- OpenCode runs with `--share` flag to generate shareable URL
- Link extracted from output via regex: `https://opncd\.ai/s/[a-zA-Z0-9]+`
- Appended to PR description for review

## State Variables

Global variables track execution state:
- `ITERATION_COUNT`: Current iteration number
- `TOTAL_COST`: Cumulative cost in cents
- `START_TIME`: Unix timestamp of start
- `COMPLETION_SIGNAL_COUNT`: Consecutive completion signals
- `NO_CHANGES_COUNT`: Consecutive iterations without changes
- `HAS_MADE_COMMIT`: Whether any commit was made
- `OPENCODE_SERVER_PID`: Server process for cleanup
- `SHARE_LINK`: Most recent share link

## Function Categories

### Lifecycle Management
- `start_server`, `stop_server`: Server mode
- `setup_worktree`, `cleanup_worktree`: Worktree support
- `check_dependencies`: Validates required tools

### Iteration Functions
- `run_iteration`: Main iteration orchestrator
- `run_opencode`: Executes OpenCode with spinner
- `run_reviewer`: Optional reviewer pass

### Git Operations
- `create_branch`: Generates unique branch name
- `commit_changes`: Stages and commits changes
- `push_and_create_pr`: Creates PR via GitHub CLI
- `wait_for_pr_checks`: Polls CI status
- `merge_pr`: Merges PR
- `cleanup_branch`: Returns to main and deletes branch

### Utility
- `should_continue`: Evaluates stopping conditions
- `parse_duration`: Converts "2h30m" to seconds
- `update_cost_tracking`: Queries opencode stats
- `find_available_port`: Finds open port for server
- `detect_git_remote`: Parses GitHub owner/repo from git remote

## Error Handling

- Uses `set -euo pipefail` for strict bash behavior
- `|| true` pattern for non-critical failures (git operations, gh CLI)
- `|| echo "default"` pattern for jq JSON parsing failures
- `trap stop_server EXIT` ensures cleanup on script exit

## Version Management

- Version stored in `CONTINUOUS_OPENCODE_VERSION` constant
- `install.sh` has separate `VERSION` variable (must be kept in sync)
- Update check fetches version from GitHub raw URL

## When Making Changes

1. Run `bash -n continuous_opencode.sh` to check syntax
2. Test with `--dry-run` to validate logic without side effects
3. Test with `--disable-commits` for non-git changes
4. Update both VERSION constants if changing behavior
5. Update `usage()` function when adding new flags
6. Update VERSION in install.sh when releasing

# Continuous OpenCode

🔂 Run OpenCode in a continuous loop, autonomously creating PRs, waiting for checks, and merging - so multi-step projects complete while you sleep.

## Overview

This is an adaptation of [Continuous Claude](https://github.com/AnandChowdhary/continuous-claude) for the [OpenCode](https://opencode.ai) CLI tool. It provides a continuous development loop that maintains context across iterations and integrates with GitHub's pull request workflow.

## Features

- **Continuous Loop**: Runs OpenCode repeatedly until your task is complete
- **PR Integration**: Automatically creates branches, commits, and pull requests
- **CI Monitoring**: Waits for checks and reviews before merging
- **Context Persistence**: Uses `AGENTS.md` for native OpenCode context management
- **Early Stopping**: Stops when agents signal completion multiple times
- **Parallel Execution**: Use git worktrees to run multiple instances simultaneously
- **Multiple Limits**: Control by iterations, cost, or duration
- **Reviewer Pass**: Optional validation step after each iteration
- **Server Mode**: Uses `opencode serve` for faster iterations (no cold boot)
- **Cost Tracking**: Accurate cost tracking via `opencode stats`
- **Share Links**: Automatically adds OpenCode share links to PR descriptions

## Installation

```bash
# Install via script
curl -fsSL https://raw.githubusercontent.com/StefanVonRanda/architect/main/install.sh | bash

# Or manually
chmod +x continuous_opencode.sh
./continuous_opencode.sh -p "add unit tests" -m 1 --dry-run
```

After installation, use the **`cop`** command:
```bash
cop --prompt "add unit tests" --max-runs 5
```

### Prerequisites

1. **[OpenCode CLI](https://opencode.ai)** - Install and authenticate
2. **[GitHub CLI](https://cli.github.com)** - Authenticate with `gh auth login`
3. **jq** - Install with `brew install jq` (macOS) or `apt-get install jq` (Linux)

## Usage

```bash
# Run 5 iterations
cop --prompt "add unit tests" --max-runs 5

# Run infinitely until stopped
cop -p "increase test coverage" -m 0

# Run until budget exhausted
cop -p "add documentation" --max-cost 10.00

# Run for 2 hours
cop -p "refactor code" --max-duration 2h

# Combine limits (whichever comes first)
cop -p "improve code" -m 10 --max-cost 5.00
```

## Flags

- `-p, --prompt`: Task prompt for OpenCode (required)
- `-m, --max-runs`: Maximum iterations (0 for infinite)
- `--max-cost`: Maximum USD to spend
- `--max-duration`: Maximum duration (e.g., `2h`, `30m`)
- `--owner`: GitHub repository owner (auto-detected)
- `--repo`: GitHub repository name (auto-detected)
- `--merge-strategy`: `squash`, `merge`, or `rebase` (default: `squash`)
- `--git-branch-prefix`: Branch name prefix (default: `continuous-opencode/`)
- `--notes-file`: Path to shared notes file (default: `SHARED_TASK_NOTES.md`)
- `--disable-commits`: Disable git commits and PRs (useful for testing)
- `--disable-branches`: Commit without creating PRs
- `--worktree <name>`: Run in a git worktree for parallel execution
- `--cleanup-worktree`: Remove worktree after completion
- `--list-worktrees`: List active worktrees and exit
- `--dry-run`: Simulate without making changes
- `--completion-signal`: Phrase signaling completion (default: `CONTINUOUS_OPENCODE_PROJECT_COMPLETE`)
- `--completion-threshold`: Consecutive signals required (default: `3`)
- `-r, --review-prompt`: Run reviewer after each iteration

## How It Works

For each iteration:

1. Creates a new branch
2. Starts OpenCode server (for fast iterations)
3. Runs OpenCode with the enhanced prompt
4. Commits any changes
5. Pushes and creates a pull request with share link
6. Monitors CI checks and reviews
7. Merges on success or discards on failure
8. Updates cost tracking via `opencode stats`
9. Repeats until limits are reached

## OpenCode-Specific Features

### Server Mode
Uses `opencode serve` to avoid cold boot overhead on each iteration:
- Server starts once at the beginning
- All iterations attach to the running server
- Much faster iteration times, especially with MCP servers

### AGENTS.md Integration
Leverages OpenCode's native `AGENTS.md` file for context:
- Automatically creates `AGENTS.md` if it doesn't exist
- OpenCode naturally reads this file for project context
- Better than custom notes files as it's the standard OpenCode format

### Cost Tracking
Uses `opencode stats` for accurate cost monitoring:
- Real-time cost tracking per project
- Accurate USD tracking from OpenCode's native statistics
- No manual calculation needed

### Share Links
Adds OpenCode share links to PR descriptions:
- Each run generates a shareable link
- Links are included in PR body for easy review
- Team members can see the full OpenCode conversation

## Shared Notes

The `AGENTS.md` file acts as external memory between iterations. OpenCode is instructed to:

- Make meaningful progress on one thing per iteration
- Leave clear notes for the next iteration
- Track what has been done and what remains

This enables self-improvement and prevents context drift.

## Parallel Execution

Run multiple instances simultaneously using git worktrees:

```bash
# Terminal 1
cop -p "Add unit tests" -m 5 --worktree tests

# Terminal 2 (simultaneously)
cop -p "Add docs" -m 5 --worktree docs

# List worktrees
cop --list-worktrees

# Clean up after completion
cop -p "task" -m 1 --worktree temp --cleanup-worktree
```

## Example Output

```
🔄 (1) Starting iteration...
🌿 Creating branch: continuous-opencode/iteration-1/2026-01-13-abc123
🤖 Running OpenCode...
📝 Output: Added tests for authentication module...
🔍 Running reviewer pass...
💬 Committing changes...
📤 Pushing branch...
🔨 Creating pull request...
💬 PR created: https://github.com/owner/repo/pull/42
🔍 Checking PR status...
   📊 Iteration 1/180: 0 pending, 0 failed
✅ All PR checks passed
🔀 Merging PR #42...
🗑️  Cleaning up branch: continuous-opencode/iteration-1/2026-01-13-abc123
✅ (1) Iteration complete
```

## License

MIT © 2026

## Acknowledgments

Inspired by [Continuous Claude](https://github.com/AnandChowdhary/continuous-claude) by Anand Chowdhary.

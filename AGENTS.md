# AGENTS.md

This file provides guidelines for agentic coding agents working in this repository.

## Project Overview

Continuous OpenCode is a Bash script wrapper that automates OpenCode CLI execution with PR creation, CI monitoring, and auto-merging. It runs in continuous loops until task completion.

## Build, Lint, and Test Commands

### Syntax Validation
```bash
# Check shell syntax without execution
bash -n continuous_opencode.sh
bash -n install.sh
```

### Linting (if shellcheck is installed)
```bash
# Install shellcheck: apt-get install shellcheck (Linux) or brew install shellcheck (macOS)
shellcheck continuous_opencode.sh
shellcheck install.sh
```

### Manual Testing
```bash
# Show help and verify flags parse correctly
./continuous_opencode.sh --help

# Dry run to test logic without making changes
./continuous_opencode.sh -p "test task" -m 1 --dry-run

# Test with disabled commits (no git operations)
./continuous_opencode.sh -p "test task" -m 1 --disable-commits
```

## Code Style Guidelines

### Shebang and Error Handling
- Always start with `#!/bin/bash`
- Follow with `set -euo pipefail` for strict error handling
  - `e`: Exit on error
  - `u`: Treat unset variables as error
  - `o pipefail`: Pipeline fails if any command fails

### Naming Conventions
- **Constants/Global Variables**: UPPERCASE_WITH_UNDERSCORES
  ```bash
  CONTINUOUS_OPENCODE_VERSION="0.2.0"
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  ```
- **Local Variables**: lowercase_with_underscores, declare with `local`
  ```bash
  local branch_name="main"
  local max_iterations=180
  ```
- **Functions**: lowercase_with_underscores
  ```bash
  check_dependencies() { ... }
  run_iteration() { ... }
  ```

### Quoting
- Quote all variable expansions: `"$VAR"` not `$VAR`
- Quote string comparisons: `[[ "$VAR" == "value" ]]`

### Conditional Tests
- Use `[[ ]]` instead of `[ ]` for Bash-specific features (more robust)
- Use `-z` to check empty strings, `-n` to check non-empty
- Use `!` for negation: `[[ ! -f "$file" ]]`

### Command Substitution
- Use `$(...)` instead of backticks
  ```bash
  local output=$(command arg)
  ```

### Exit Codes
- Exit 0 for success
- Exit 1 for errors
- Return meaningful exit codes from functions

### Error Messages
- Use emoji prefixes for visual consistency:
  - ❌ Error messages
  - ✅ Success messages
  - ⚠️ Warnings
  - 🔄 Progress indicators
  - 📝 Informational messages

### Indentation and Formatting
- 4 spaces for indentation (no tabs)
- Add blank lines between functions
- Keep lines under 100 characters when practical

### Functions
- Declare local variables at function start
- Use `return 0` for success, `return 1` for failure (not exit)
- Keep functions focused and under 50 lines when possible
- Minimal inline comments - code should be self-documenting

### Versioning
- Include VERSION constant at script top
- Format: `VERSION="X.Y.Z"`

### Cleanup
- Use `trap` for cleanup on exit:
  ```bash
  trap stop_server EXIT
  ```
- Clean up temporary files and background processes

### Git Operations
- Always check if operations might fail before proceeding
- Use `|| true` to prevent failure on non-critical operations
- Prefer `git checkout main 2>/dev/null || git checkout master 2>/dev/null || true`

### Dependencies
- Use `command -v` to check for command existence
- Provide helpful error messages for missing dependencies

### jq Usage
- Use `|| echo "default"` pattern for JSON parsing:
  ```bash
  local value=$(echo "$json" | jq -r '.field // "default"' 2>/dev/null || echo "default")
  ```

## Project Structure
- `continuous_opencode.sh` - Main script (735 lines)
- `install.sh` - Installation script (46 lines)
- `README.md` - User documentation
- No build system, tests, or CI/CD

## When Making Changes
1. Run syntax check: `bash -n continuous_opencode.sh`
2. Test with `--dry-run` first
3. Test with `--disable-commits` for non-git changes
4. If adding new flags, update help text in `usage()` function
5. Update VERSION if changing behavior
6. Test with manual run before considering complete

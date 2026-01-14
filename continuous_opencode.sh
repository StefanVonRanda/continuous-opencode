#!/bin/bash
set -euo pipefail

CONTINUOUS_OPENCODE_VERSION="0.2.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NOTES_FILE="AGENTS.md"
COMPLETION_SIGNAL="CONTINUOUS_OPENCODE_PROJECT_COMPLETE"
COMPLETION_THRESHOLD=3
NO_CHANGES_THRESHOLD=3
ITERATION_COUNT=0
TOTAL_COST=0
START_TIME=$(date +%s)
MAX_RUNS=0
MAX_COST=""
MAX_DURATION=""
GIT_BRANCH_PREFIX="continuous-opencode/"
MERGE_STRATEGY="squash"
DISABLE_COMMITS=false
DISABLE_BRANCHES=false
WORKTREE_NAME=""
WORKTREE_BASE_DIR="../continuous-opencode-worktrees"
CLEANUP_WORKTREE=false
DRY_RUN=false
REVIEW_PROMPT=""
OWNER=""
REPO=""
PROMPT=""
COMPLETION_SIGNAL_COUNT=0
NO_CHANGES_COUNT=0
HAS_GITHUB_REMOTE=false
OPENCODE_ARGS=()
OPENCODE_SERVER_PID=""
OPENCODE_SERVER_URL=""
SHARE_LINK=""
PREVIOUS_STATS=""

usage() {
    cat <<EOF
Continuous OpenCode v${CONTINUOUS_OPENCODE_VERSION}
Run OpenCode in a continuous loop with PR creation, CI monitoring, and auto-merging

USAGE:
    cop --prompt <task> --max-runs <num>
    cop --prompt <task> --max-cost <usd>
    cop --prompt <task> --max-duration <duration>

FLAGS:
    -p, --prompt <task>              Task prompt for OpenCode (required)
    -m, --max-runs <num>             Maximum number of iterations (0 for infinite)
        --max-cost <usd>             Maximum USD to spend
        --max-duration <duration>    Maximum duration (e.g., 2h, 30m, 1h30m)
        --owner <owner>              GitHub repository owner (auto-detected)
        --repo <repo>                GitHub repository name (auto-detected)
        --merge-strategy <strategy>  Merge strategy: squash|merge|rebase (default: squash)
        --git-branch-prefix <prefix> Prefix for git branches (default: continuous-opencode/)
        --disable-commits            Disable automatic git commits and PR creation
        --disable-branches           Commit on current branch without creating PRs
        --worktree <name>            Run in a git worktree for parallel execution
        --worktree-base-dir <path>   Base directory for worktrees (default: ../continuous-opencode-worktrees)
        --cleanup-worktree           Remove worktree after completion
        --list-worktrees             List all active git worktrees and exit
        --dry-run                    Simulate execution without making changes
        --completion-signal <phrase>  Phrase that signals project completion (default: CONTINUOUS_OPENCODE_PROJECT_COMPLETE)
        --completion-threshold <num>  Number of completion signals required to stop (default: 3)
        --no-changes-threshold <num>  Consecutive iterations without changes to stop (default: 3)
    -r, --review-prompt <prompt>     Run reviewer pass after each iteration
        update                       Check for and install updates

Additional flags are passed directly to opencode.

EXAMPLES:
    continuous-opencode -p "add unit tests" -m 5
    continuous-opencode -p "add docs" --max-cost 10.00
    continuous-opencode -p "refactor" --max-duration 2h
EOF
}

check_dependencies() {
    for cmd in git jq gh bc; do
        if ! command -v "$cmd" &>/dev/null; then
            echo "❌ Error: $cmd is not installed"
            exit 1
        fi
    done

    if ! command -v opencode &>/dev/null; then
        echo "❌ Error: opencode CLI is not installed"
        echo "   Please install from https://opencode.ai"
        exit 1
    fi
}

detect_git_remote() {
    if [[ -z "$OWNER" || -z "$REPO" ]]; then
        local remote_url
        remote_url=$(git remote get-url origin 2>/dev/null || true)
        if [[ -n "$remote_url" ]]; then
            if [[ "$remote_url" =~ github\.com[/:]([^/]+)/([^/\.]+) ]]; then
                OWNER="${OWNER:-${BASH_REMATCH[1]}}"
                REPO="${REPO:-${BASH_REMATCH[2]%%.git}}"
                HAS_GITHUB_REMOTE=true
            fi
        fi
    fi

    if [[ -n "$OWNER" && -n "$REPO" ]]; then
        echo "📦 Repository: ${OWNER}/${REPO}"
    else
        echo "📦 Local repository (no GitHub remote detected)"
    fi
}

parse_duration() {
    local duration="$1"
    local total_seconds=0

    if [[ "$duration" =~ ([0-9]+)h ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 3600))
    fi
    if [[ "$duration" =~ ([0-9]+)m ]]; then
        total_seconds=$((total_seconds + ${BASH_REMATCH[1]} * 60))
    fi

    echo "$total_seconds"
}

should_continue() {
    if [[ "$MAX_RUNS" -gt 0 && "$ITERATION_COUNT" -ge "$MAX_RUNS" ]]; then
        return 1
    fi

    if [[ -n "$MAX_COST" ]]; then
        local max_cost_cents=$(echo "$MAX_COST * 100" | bc | cut -d. -f1)
        if [[ "$TOTAL_COST" -ge "$max_cost_cents" ]]; then
            return 1
        fi
    fi

    if [[ -n "$MAX_DURATION" ]]; then
        local elapsed=$(($(date +%s) - START_TIME))
        if [[ "$elapsed" -ge "$MAX_DURATION" ]]; then
            return 1
        fi
    fi

    if [[ "$NO_CHANGES_COUNT" -ge "$NO_CHANGES_THRESHOLD" ]]; then
        return 1
    fi

    return 0
}

start_server() {
    if [[ "$DISABLE_COMMITS" == true ]]; then
        return 0
    fi

    echo "🚀 Starting OpenCode server..."
    local port=4096
    OPENCODE_SERVER_URL="http://localhost:${port}"

    if [[ "$DRY_RUN" == true ]]; then
        echo "   [DRY RUN] Would start server on ${OPENCODE_SERVER_URL}"
        return 0
    fi

    opencode serve --port "${port}" > /dev/null 2>&1 &
    OPENCODE_SERVER_PID=$!

    sleep 3

    if kill -0 "$OPENCODE_SERVER_PID" 2>/dev/null; then
        echo "   ✅ Server started (PID: ${OPENCODE_SERVER_PID})"
    else
        echo "   ⚠️  Server may not have started, continuing anyway"
        OPENCODE_SERVER_PID=""
        OPENCODE_SERVER_URL=""
    fi
}

stop_server() {
    if [[ -n "$OPENCODE_SERVER_PID" ]]; then
        echo "🛑 Stopping OpenCode server..."
        kill "$OPENCODE_SERVER_PID" 2>/dev/null || true
        wait "$OPENCODE_SERVER_PID" 2>/dev/null || true
        echo "   ✅ Server stopped"
    fi
}

update_cost_tracking() {
    if [[ "$DISABLE_COMMITS" == true || -z "$OPENCODE_SERVER_URL" ]]; then
        return 0
    fi

    local stats
    stats=$(opencode stats --project "$(pwd)" --format json 2>/dev/null || echo '{"totalCostUsd": 0}')

    if [[ "$stats" != "null" && -n "$stats" ]]; then
        local cost=$(echo "$stats" | jq -r '.totalCostUsd // 0' 2>/dev/null || echo "0")
        TOTAL_COST=$(echo "$cost * 100" | bc | cut -d. -f1)
    fi
}

init_agents_md() {
    if [[ ! -f "$NOTES_FILE" ]]; then
        echo "📝 Creating $NOTES_FILE..."
        cat > "$NOTES_FILE" << 'EOF'
# Continuous OpenCode

This file maintains context between iterations of continuous OpenCode.

## Context
This is a continuous development loop where OpenCode runs multiple iterations to complete a task.
Each iteration should:
1. Make meaningful progress on one thing
2. Leave clear notes here for the next iteration
3. Track progress and next steps

## Progress

## Next Steps
EOF
    fi
}

run_opencode() {
    local prompt="$1"
    local branch_name="$2"

    echo "🤖 Running OpenCode..."

    if [[ "$DRY_RUN" == true ]]; then
        echo "   [DRY RUN] Would run: opencode $prompt"
        return 0
    fi

    local cmd
    if [[ -n "$OPENCODE_SERVER_URL" ]]; then
        cmd="opencode run --attach ${OPENCODE_SERVER_URL} ${OPENCODE_ARGS[@]:-} --share \"$prompt\""
    else
        cmd="opencode run ${OPENCODE_ARGS[@]:-} -- \"$prompt\""
    fi

    echo "   Running: opencode..."

    local spinner=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_idx=0
    local output_file=$(mktemp)
    
    local exit_code
    (eval "$cmd" >"$output_file" 2>&1) &
    local pid=$!
    
    while kill -0 $pid 2>/dev/null; do
        printf "\r   ${spinner[$spin_idx]} Running OpenCode..."
        spin_idx=$(( (spin_idx + 1) % 10 ))
        sleep 0.1
    done
    printf "\r   ✅ OpenCode finished\n"
    
    wait $pid || exit_code=$?
    
    local output
    output=$(cat "$output_file")
    rm -f "$output_file"

    SHARE_LINK=$(echo "$output" | grep -oE 'https://opncd\.ai/s/[a-zA-Z0-9]+' || true)

    if [[ -n "$output" ]]; then
        echo "📝 Output: $output"

        if echo "$output" | grep -q "$COMPLETION_SIGNAL"; then
            COMPLETION_SIGNAL_COUNT=$((COMPLETION_SIGNAL_COUNT + 1))
            echo "   ✨ Completion signal detected ($COMPLETION_SIGNAL_COUNT/$COMPLETION_THRESHOLD)"
        fi
    fi

    update_cost_tracking

    return ${exit_code:-0}
}

run_reviewer() {
    if [[ -z "$REVIEW_PROMPT" ]]; then
        return 0
    fi

    echo "🔍 Running reviewer pass..."

    if [[ "$DRY_RUN" == true ]]; then
        echo "   [DRY RUN] Would run reviewer: $REVIEW_PROMPT"
        return 0
    fi

    local cmd
    if [[ -n "$OPENCODE_SERVER_URL" ]]; then
        cmd="opencode run --attach ${OPENCODE_SERVER_URL} ${OPENCODE_ARGS[@]:-} -- \"$REVIEW_PROMPT\""
    else
        cmd="opencode run ${OPENCODE_ARGS[@]:-} -- \"$REVIEW_PROMPT\""
    fi

    echo "   Running: opencode $REVIEW_PROMPT"

    local output
    output=$(eval "$cmd" 2>&1) || true

    if [[ -n "$output" ]]; then
        echo "📝 Reviewer output: $output"
    fi

    update_cost_tracking
}

commit_changes() {
    local branch_name="$1"

    if [[ "$DISABLE_COMMITS" == true ]]; then
        echo "⏭️  Skipping commits (--disable-commits)"
        return 0
    fi

    echo "💬 Committing changes..."

    if ! git diff --quiet; then
        NO_CHANGES_COUNT=0
        if [[ "$DRY_RUN" == true ]]; then
            echo "   [DRY RUN] Would commit changes"
            return 0
        fi

        git add -A
        git commit -m "OpenCode iteration $((ITERATION_COUNT + 1))" -m "Prompt: $PROMPT"
        echo "   ✅ Changes committed"
    else
        NO_CHANGES_COUNT=$((NO_CHANGES_COUNT + 1))
        echo "   ℹ️  No changes to commit ($NO_CHANGES_COUNT/$NO_CHANGES_THRESHOLD consecutive)"
    fi
}

create_branch() {
    local timestamp=$(date +%Y-%m-%d-%H%M%S)
    local random=$(head -c 8 /dev/urandom | xxd -p | head -c 8)
    echo "${GIT_BRANCH_PREFIX}iteration-$((ITERATION_COUNT + 1))/${timestamp}-${random}"
}

push_and_create_pr() {
    local branch_name="$1"

    if [[ "$DISABLE_COMMITS" == true || "$DISABLE_BRANCHES" == true ]]; then
        echo "⏭️  Skipping PR creation"
        return 0
    fi

    echo "📤 Pushing branch..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "   [DRY RUN] Would push branch: $branch_name"
        return 0
    fi

    git push -u origin "$branch_name" 2>&1 || true

    echo "🔨 Creating pull request..."
    local pr_title="OpenCode iteration $((ITERATION_COUNT + 1))"
    local pr_body="Automated PR created by Continuous OpenCode

**Prompt:** $PROMPT"

    if [[ -n "$SHARE_LINK" ]]; then
        pr_body+="${pr_body}

**Share Link:** $SHARE_LINK"
    fi

    local pr_url
    pr_url=$(gh pr create --title "$pr_title" --body "$pr_body" --base main --head "$branch_name" 2>&1 || true)

    if [[ -n "$pr_url" && ! "$pr_url" =~ ^(Error|failed|no) ]]; then
        echo "💬 PR created: $pr_url"
        local pr_number=$(echo "$pr_url" | grep -oE '[0-9]+$')
        echo "$pr_number" > .continuous-opencode-pr
        return 0
    else
        echo "⚠️  Failed to create PR"
        return 1
    fi
}

wait_for_pr_checks() {
    if [[ "$DISABLE_COMMITS" == true || "$DISABLE_BRANCHES" == true ]]; then
        return 0
    fi

    if [[ ! -f .continuous-opencode-pr ]]; then
        return 0
    fi

    local pr_number
    pr_number=$(cat .continuous-opencode-pr)

    echo "🔍 Checking PR status..."
    local max_iterations=180
    local iteration=0

    while [[ $iteration -lt $max_iterations ]]; do
        iteration=$((iteration + 1))

        local status_data
        status_data=$(gh pr checks "$pr_number" --json status,name,conclusion --jq '.[] | "\(.status) \(.name) \(.conclusion // "")"' 2>&1 || true)

        if [[ -n "$status_data" ]]; then
            local pending_count=$(echo "$status_data" | grep -c "QUEUED\|IN_PROGRESS" || true)
            local failed_count=$(echo "$status_data" | grep -c "FAILURE" || true)

            echo "   📊 Iteration $iteration/$max_iterations: $pending_count pending, $failed_count failed"

            if [[ $pending_count -eq 0 ]]; then
                if [[ $failed_count -gt 0 ]]; then
                    echo "❌ PR checks failed"
                    return 1
                else
                    echo "✅ All PR checks passed"
                    return 0
                fi
            fi
        fi

        sleep 10
    done

    echo "⏰ Timeout waiting for PR checks"
    return 1
}

merge_pr() {
    if [[ "$DISABLE_COMMITS" == true || "$DISABLE_BRANCHES" == true ]]; then
        return 0
    fi

    if [[ ! -f .continuous-opencode-pr ]]; then
        return 0
    fi

    local pr_number
    pr_number=$(cat .continuous-opencode-pr)

    echo "🔀 Merging PR #$pr_number..."
    if [[ "$DRY_RUN" == true ]]; then
        echo "   [DRY RUN] Would merge PR #$pr_number"
        return 0
    fi

    gh pr merge "$pr_number" --merge --delete-branch --squash 2>&1 || true

    rm -f .continuous-opencode-pr
}

cleanup_branch() {
    local branch_name="$1"

    if [[ "$DISABLE_COMMITS" == true || "$DISABLE_BRANCHES" == true ]]; then
        return 0
    fi

    echo "🗑️  Cleaning up branch: $branch_name"
    git checkout main 2>/dev/null || git checkout master 2>/dev/null || true
    git pull 2>/dev/null || true
    git branch -D "$branch_name" 2>/dev/null || true
}

run_iteration() {
    ITERATION_COUNT=$((ITERATION_COUNT + 1))
    echo "🔄 ($ITERATION_COUNT) Starting iteration..."

    local skip_branching=false
    if [[ "$DISABLE_BRANCHES" == true || "$HAS_GITHUB_REMOTE" == false ]]; then
        skip_branching=true
    fi

    if [[ "$skip_branching" == false ]]; then
        BRANCH_NAME=$(create_branch)
        echo "🌿 Creating branch: $BRANCH_NAME"

        if [[ "$DRY_RUN" == false ]]; then
            git checkout -b "$BRANCH_NAME"
        fi
    fi

    local enhanced_prompt="This is part of a continuous development loop with OpenCode.
 You don't need to complete the entire goal in one iteration - just make meaningful progress on one thing.
 Leave clear notes in $NOTES_FILE for the next iteration.

 When the entire task is COMPLETE and nothing more needs to be done, output this exact phrase:
 $COMPLETION_SIGNAL

 $PROMPT"

    run_opencode "$enhanced_prompt" "${BRANCH_NAME:-}"

    if [[ $? -ne 0 && ! "$DRY_RUN" ]]; then
        echo "⚠️  OpenCode encountered an error"
    fi

    run_reviewer
    commit_changes "${BRANCH_NAME:-}"

    if [[ "$skip_branching" == false ]]; then
        if push_and_create_pr "$BRANCH_NAME"; then
            if wait_for_pr_checks; then
                merge_pr
                git pull 2>/dev/null || true
            fi
        fi
        cleanup_branch "$BRANCH_NAME"
    fi

    echo "✅ ($ITERATION_COUNT) Iteration complete"
}

setup_worktree() {
    if [[ -z "$WORKTREE_NAME" ]]; then
        return 0
    fi

    local worktree_dir="${WORKTREE_BASE_DIR}/${WORKTREE_NAME}"
    mkdir -p "$WORKTREE_BASE_DIR"

    if [[ ! -d "$worktree_dir" ]]; then
        echo "🌲 Creating worktree: $worktree_dir"
        git worktree add "$worktree_dir" -b "worktree-${WORKTREE_NAME}"
    fi

    cd "$worktree_dir"
    git pull
    echo "📁 Working in: $worktree_dir"
}

cleanup_worktree() {
    if [[ -z "$WORKTREE_NAME" || "$CLEANUP_WORKTREE" == false ]]; then
        return 0
    fi

    local worktree_dir="${WORKTREE_BASE_DIR}/${WORKTREE_NAME}"

    if [[ -d "$worktree_dir" ]]; then
        echo "🗑️  Removing worktree: $worktree_dir"
        git worktree remove "$worktree_dir"
        git branch -D "worktree-${WORKTREE_NAME}" 2>/dev/null || true
    fi
}

list_worktrees() {
    git worktree list
    exit 0
}

check_for_updates() {
    echo "🔄 Checking for updates..."
    local latest_version
    latest_version=$(curl -fsSL https://raw.githubusercontent.com/StefanVonRanda/continuous-opencode/main/continuous_opencode.sh | grep "CONTINUOUS_OPENCODE_VERSION=" | cut -d'"' -f2)

    if [[ -n "$latest_version" && "$latest_version" != "$CONTINUOUS_OPENCODE_VERSION" ]]; then
        echo "📦 New version available: $latest_version (current: $CONTINUOUS_OPENCODE_VERSION})"
        echo "   Run 'curl -fsSL https://raw.githubusercontent.com/StefanVonRanda/continuous-opencode/main/install.sh | bash' to update"
    else
        echo "✅ You're on the latest version"
    fi
}

trap stop_server EXIT

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--prompt)
            PROMPT="$2"
            shift 2
            ;;
        -m|--max-runs)
            MAX_RUNS="$2"
            shift 2
            ;;
        --max-cost)
            MAX_COST="$2"
            shift 2
            ;;
        --max-duration)
            MAX_DURATION="$2"
            MAX_DURATION=$(parse_duration "$MAX_DURATION")
            shift 2
            ;;
        --owner)
            OWNER="$2"
            shift 2
            ;;
        --repo)
            REPO="$2"
            shift 2
            ;;
        --merge-strategy)
            MERGE_STRATEGY="$2"
            shift 2
            ;;
        --git-branch-prefix)
            GIT_BRANCH_PREFIX="$2"
            shift 2
            ;;
        --disable-commits)
            DISABLE_COMMITS=true
            shift
            ;;
        --disable-branches)
            DISABLE_BRANCHES=true
            shift
            ;;
        --worktree)
            WORKTREE_NAME="$2"
            shift 2
            ;;
        --worktree-base-dir)
            WORKTREE_BASE_DIR="$2"
            shift 2
            ;;
        --cleanup-worktree)
            CLEANUP_WORKTREE=true
            shift
            ;;
        --list-worktrees)
            list_worktrees
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --completion-signal)
            COMPLETION_SIGNAL="$2"
            shift 2
            ;;
        --completion-threshold)
            COMPLETION_THRESHOLD="$2"
            shift 2
            ;;
        --no-changes-threshold)
            NO_CHANGES_THRESHOLD="$2"
            shift 2
            ;;
        -r|--review-prompt)
            REVIEW_PROMPT="$2"
            shift 2
            ;;
        update)
            check_for_updates
            exit 0
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            OPENCODE_ARGS+=("$1")
            shift
            ;;
    esac
done

if [[ "${1:-}" == "update" ]]; then
    check_for_updates
    exit 0
fi

if [[ -z "$PROMPT" ]]; then
    echo "❌ Error: --prompt is required"
    usage
    exit 1
fi

if [[ -z "$MAX_RUNS" && -z "$MAX_COST" && -z "$MAX_DURATION" ]]; then
    echo "❌ Error: Must specify one of: --max-runs, --max-cost, or --max-duration"
    usage
    exit 1
fi

check_dependencies
detect_git_remote
setup_worktree
init_agents_md
start_server

echo "🚀 Starting Continuous OpenCode..."
echo "   Prompt: $PROMPT"

if [[ "$MAX_RUNS" -gt 0 ]]; then
    echo "   Max iterations: $MAX_RUNS"
fi

if [[ -n "$MAX_COST" ]]; then
    echo "   Max cost: \$${MAX_COST}"
fi

if [[ -n "$MAX_DURATION" ]]; then
    local duration_display=$((MAX_DURATION / 60))
    echo "   Max duration: ${duration_display}m"
fi

if [[ "$COMPLETION_THRESHOLD" -gt 0 ]]; then
    echo "   Completion threshold: $COMPLETION_THRESHOLD consecutive signals"
fi

if [[ -n "$OPENCODE_SERVER_URL" ]]; then
    echo "   Server: $OPENCODE_SERVER_URL"
fi

echo ""

while should_continue; do
    run_iteration
    echo ""

    if [[ "$COMPLETION_SIGNAL_COUNT" -ge "$COMPLETION_THRESHOLD" ]]; then
        echo "🎉 Project completion threshold reached!"
        break
    fi

    if [[ "$NO_CHANGES_COUNT" -ge "$NO_CHANGES_THRESHOLD" ]]; then
        echo "🛑 No changes threshold reached ($NO_CHANGES_THRESHOLD consecutive iterations)"
        break
    fi

    sleep 1
done

cleanup_worktree

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))
ELAPSED_MINUTES=$((ELAPSED / 60))

echo "🎉 Done with $ITERATION_COUNT iterations in ${ELAPSED_MINUTES} minutes"
echo "💰 Total cost: \$$(echo "scale=3; $TOTAL_COST / 100" | bc)"

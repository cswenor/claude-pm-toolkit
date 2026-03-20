#!/usr/bin/env bash
set -euo pipefail

# pm-post-merge-hook.sh — Claude Code PostToolUse hook for post-merge cleanup
#
# Triggered on every Bash PostToolUse. Reads stdin for the hook event JSON,
# checks if the command was a merge (gh pr merge / git merge), and if so:
#   1. Extracts issue numbers from the merge commit
#   2. Moves issues to Done in local PM database
#   3. Cleans up worktrees (from main repo context, or defers if in worktree)

# Read hook event from stdin
HOOK_INPUT=$(cat)

# Check if this was a merge command — exit fast if not
COMMAND=$(echo "$HOOK_INPUT" | jq -r '.tool_input.command // ""' 2>/dev/null || echo "")
if [[ -z "$COMMAND" ]]; then
  exit 0
fi

# Only act on merge commands
case "$COMMAND" in
  *"gh pr merge"*|*"git merge"*|*"git pull"*) ;;
  *) exit 0 ;;
esac

# Check exit code — only proceed on success
# shellcheck disable=SC2034  # EXIT_CODE reserved for future exit-code gating
EXIT_CODE=$(echo "$HOOK_INPUT" | jq -r '.tool_response.exit_code // .tool_response.stdout' 2>/dev/null || echo "")

# Find repo root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo ".")"

# Check if pm CLI is available
PM_CLI="$REPO_ROOT/tools/mcp/pm-intelligence/build/cli.js"
if [[ ! -f "$PM_CLI" ]]; then
  exit 0
fi

# Extract issue numbers from recent merge commit message
MERGE_MSG=$(git log -1 --format="%s%n%b" 2>/dev/null || echo "")
ISSUE_NUMS=$(echo "$MERGE_MSG" | grep -oiE '(fixes|closes|resolves)\s+#[0-9]+' | grep -oE '[0-9]+' | sort -u || true)

if [[ -z "$ISSUE_NUMS" ]]; then
  exit 0
fi

# Check if we're in a worktree or main repo
MAIN_WORKTREE=$(git worktree list --porcelain 2>/dev/null | head -1 | sed 's/^worktree //')
CURRENT_DIR=$(pwd -P)
IN_WORKTREE=false
if [[ "$CURRENT_DIR" != "$MAIN_WORKTREE" ]]; then
  IN_WORKTREE=true
fi

for ISSUE_NUM in $ISSUE_NUMS; do
  # Move to Done in local DB
  node "$PM_CLI" move "$ISSUE_NUM" Done 2>/dev/null || true

  if $IN_WORKTREE; then
    # Can't clean up from inside a worktree — print deferred instructions
    echo >&2 "[pm] Issue #$ISSUE_NUM moved to Done. Worktree cleanup deferred."
    echo >&2 "[pm] Run from main repo: ./tools/scripts/worktree-cleanup.sh $ISSUE_NUM"
  else
    # In main repo — safe to clean up worktrees
    CLEANUP_SCRIPT="$REPO_ROOT/tools/scripts/worktree-cleanup.sh"
    if [[ -x "$CLEANUP_SCRIPT" ]]; then
      CHECK_OUTPUT=$("$CLEANUP_SCRIPT" "$ISSUE_NUM" --check 2>/dev/null || true)
      if echo "$CHECK_OUTPUT" | grep -q "can_cleanup"; then
        "$CLEANUP_SCRIPT" "$ISSUE_NUM" 2>/dev/null && \
          echo >&2 "[pm] Cleaned up worktree for #$ISSUE_NUM" || \
          echo >&2 "[pm] Worktree cleanup failed for #$ISSUE_NUM (non-fatal)"
      fi
    fi
  fi
done

exit 0

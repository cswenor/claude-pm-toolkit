#!/usr/bin/env bash
set -euo pipefail

# project-move.sh - Move an issue to a workflow state
# Usage: project-move.sh <issue-number> <state>
# States: Backlog | Ready | Active | Review | Rework | Done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pm.config.sh"

# Cleanup trap for temp files
TEMP_FILES=()
cleanup_temp_files() {
  for tf in "${TEMP_FILES[@]}"; do
    [[ -f "$tf" ]] && rm -f "$tf"
  done
}
trap cleanup_temp_files EXIT

show_help() {
  cat <<'HELPEOF'
project-move.sh - Move an issue to a workflow state

USAGE
  project-move.sh <issue-number> <state>

STATES
  Backlog   Issue is documented, not yet prioritized
  Ready     Prioritized and spec-ready
  Active    Work in progress (coding permitted)
  Review    PR opened, awaiting review
  Rework    Changes requested, needs fixes
  Done      PR merged, issue closed

EXAMPLES
  project-move.sh 123 Active        # Start work
  project-move.sh 123 Review        # PR opened, ready for review
  project-move.sh 123 Rework        # Changes requested, needs fixes
  project-move.sh 123 Done          # PR merged

NOTES
  The "Review" transition runs a pre-review gate:
    1. Fetches and rebases on origin/main
    2. Runs the test suite
    3. Force-pushes the rebased branch
  All three must pass before the state change occurs.

  Requires: gh CLI with 'project' scope, jq
HELPEOF
}

ISSUE_NUM=""
STATE=""

for arg in "$@"; do
  case "$arg" in
    --help|-h)
      show_help
      exit 0
      ;;
    -*)
      echo "Error: Unknown flag '$arg'"
      echo "Usage: project-move.sh <issue-number> <state>"
      echo "Run project-move.sh --help for details"
      exit 1
      ;;
    *)
      if [ -z "$ISSUE_NUM" ]; then
        ISSUE_NUM="$arg"
      elif [ -z "$STATE" ]; then
        STATE="$arg"
      else
        echo "Error: Unexpected argument '$arg'"
        echo "Usage: project-move.sh <issue-number> <state>"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$ISSUE_NUM" ] || [ -z "$STATE" ]; then
  echo "Usage: project-move.sh <issue-number> <state>"
  echo "States: Backlog | Ready | Active | Review | Rework | Done"
  echo ""
  echo "Run project-move.sh --help for full documentation"
  exit 1
fi

# Validate config (will fail if Active ID not set)
pm_validate_config

# Map state name to option ID
case "$STATE" in
  Backlog) OPTION_ID="$PM_WORKFLOW_BACKLOG" ;;
  Ready)   OPTION_ID="$PM_WORKFLOW_READY" ;;
  Active)  OPTION_ID="$PM_WORKFLOW_ACTIVE" ;;
  Review)  OPTION_ID="$PM_WORKFLOW_REVIEW" ;;
  Rework)  OPTION_ID="$PM_WORKFLOW_REWORK" ;;
  Done)    OPTION_ID="$PM_WORKFLOW_DONE" ;;
  *) echo "Error: Invalid state '$STATE'. Use: Backlog | Ready | Active | Review | Rework | Done" && exit 1 ;;
esac

# Get item ID
ITEM_ID=$(pm_get_item_id "$ISSUE_NUM" 2>/dev/null || echo "")

if [ -z "$ITEM_ID" ]; then
  echo "Error: Issue #$ISSUE_NUM not found in project #$PM_PROJECT_NUMBER" >&2
  echo "" >&2
  echo "Possible causes:" >&2
  echo "  - Issue hasn't been added to the project yet" >&2
  echo "  - Issue number is wrong" >&2
  echo "  - gh CLI token missing 'project' scope" >&2
  echo "" >&2
  echo "Fix: ./tools/scripts/project-add.sh $ISSUE_NUM <priority>" >&2
  exit 1
fi

# Pre-review test gate: runs on ANY transition to Review
if [ "$STATE" = "Review" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  echo "Running pre-review test gate..."

  # Step 0: Branch safety guard
  CURRENT_BRANCH=$(git branch --show-current)
  if [ -z "$CURRENT_BRANCH" ]; then
    echo ""
    echo "ERROR: Detached HEAD state. Switch to a feature branch before moving to Review."
    exit 1
  fi
  # Detect default branch dynamically (falls back to main/master check)
  DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "")
  if [ -z "$DEFAULT_BRANCH" ]; then
    # Fallback: check common names
    for candidate in main master; do
      if git rev-parse --verify "refs/heads/$candidate" &>/dev/null; then
        DEFAULT_BRANCH="$candidate"
        break
      fi
    done
  fi
  if [ -z "$DEFAULT_BRANCH" ]; then
    echo ""
    echo "ERROR: Could not detect default branch (tried symbolic-ref, main, master)."
    echo "Ensure your remote has a default branch configured."
    exit 1
  fi
  if [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ]; then
    echo ""
    echo "ERROR: Cannot rebase and force-push the '$CURRENT_BRANCH' branch (default branch)."
    echo "Switch to a feature branch first."
    exit 1
  fi

  # Step 1: Pre-flight checks
  if [ -d "$(git rev-parse --git-dir)/rebase-merge" ] || [ -d "$(git rev-parse --git-dir)/rebase-apply" ]; then
    echo ""
    echo "ERROR: A rebase is already in progress."
    echo "Finish or abort the existing rebase before moving to Review."
    exit 1
  fi

  if [ -n "$(git status --porcelain)" ]; then
    echo ""
    echo "ERROR: Working tree is not clean. Commit or stash changes before moving to Review."
    exit 1
  fi

  # Step 2: Fetch latest default branch
  echo "==> git fetch origin $DEFAULT_BRANCH"
  if ! git fetch origin "$DEFAULT_BRANCH"; then
    echo ""
    echo "ERROR: Failed to fetch origin/$DEFAULT_BRANCH. Check your network connection."
    exit 1
  fi

  # Step 3: Rebase on default branch
  echo "==> git rebase origin/$DEFAULT_BRANCH"
  if ! git rebase "origin/$DEFAULT_BRANCH"; then
    echo ""
    echo "ERROR: Rebase on origin/$DEFAULT_BRANCH failed."

    CONFLICTS=$(git diff --name-only --diff-filter=U 2>/dev/null) || true
    if [ -n "$CONFLICTS" ]; then
      echo ""
      echo "Conflicting files:"
      echo "$CONFLICTS"
    fi

    # Only abort if rebase is actually in progress
    GIT_DIR=$(git rev-parse --git-dir)
    if [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ]; then
      echo ""
      echo "Aborting rebase to restore your branch..."
      git rebase --abort
    fi

    echo ""
    echo "To fix manually:"
    echo "  1. git rebase origin/main"
    echo "  2. Resolve conflicts"
    echo "  3. git rebase --continue"
    echo "  4. Re-run: ./tools/scripts/project-move.sh $ISSUE_NUM Review"
    exit 1
  fi

  # Step 4: Run tests against rebased code
  echo "==> {{TEST_COMMAND}}"
  if ! eval "{{TEST_COMMAND}}"; then
    echo ""
    echo "ERROR: tests failed. Fix before moving to Review."
    exit 1
  fi

  # Step 5: Force-push rebased branch (only after tests pass)
  echo "==> git push --force-with-lease origin $CURRENT_BRANCH"
  if ! git push --force-with-lease origin "$CURRENT_BRANCH"; then
    echo ""
    echo "ERROR: Force-push failed. Another push may have happened since your last fetch."
    echo "Run 'git fetch origin' and try again."
    exit 1
  fi

  echo "Pre-review test gate passed. Branch rebased and pushed."
fi

# Move to state
gh project item-edit --project-id "$PM_PROJECT_ID" --id "$ITEM_ID" \
  --field-id "$PM_FIELD_WORKFLOW" --single-select-option-id "$OPTION_ID"

echo "Issue #$ISSUE_NUM -> $STATE"

# Post-Done cleanup
if [ "$STATE" = "Done" ]; then
  REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

  # Docker cleanup: only if project has a Makefile with docker-check target
  if [ -f "$REPO_ROOT/Makefile" ] && grep -q 'docker-check' "$REPO_ROOT/Makefile" 2>/dev/null; then
    COMPOSE_PROJECT="{{prefix}}-$ISSUE_NUM"
    echo "Checking Docker resources for project '$COMPOSE_PROJECT'..."

    # Gate: is Docker available?
    if ! make -C "$REPO_ROOT" --no-print-directory docker-check 2>/dev/null; then
      echo "Note: Docker is not available. Skipping container cleanup for '$COMPOSE_PROJECT'."
    else
      # Detection: do containers exist? (prints: found|empty|error)
      CHECK_STDERR=$(mktemp)
      TEMP_FILES+=("$CHECK_STDERR")
      CHECK_STATUS=$(COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT" make -C "$REPO_ROOT" --no-print-directory compose-check 2>"$CHECK_STDERR") || true

      case "$CHECK_STATUS" in
        found)
          echo "Found Docker containers for project '$COMPOSE_PROJECT', cleaning up..."
          if CLEANUP_OUTPUT=$(COMPOSE_PROJECT_NAME="$COMPOSE_PROJECT" make -C "$REPO_ROOT" --no-print-directory down-clean 2>&1); then
            echo "$CLEANUP_OUTPUT"
            echo "Docker cleanup complete for '$COMPOSE_PROJECT'."
          else
            echo "Warning: Docker cleanup failed for '$COMPOSE_PROJECT' (non-fatal)."
            echo "$CLEANUP_OUTPUT"
          fi
          ;;
        empty)
          echo "No Docker containers found for project '$COMPOSE_PROJECT'."
          ;;
        *)
          echo "Warning: Could not check containers for '$COMPOSE_PROJECT' (non-fatal)."
          cat "$CHECK_STDERR" 2>/dev/null
          ;;
      esac
    fi
  fi

  # Inform about worktree (do NOT auto-remove -- per non-goals)
  if [ -x "$REPO_ROOT/tools/scripts/worktree-cleanup.sh" ]; then
    WT_CHECK=$("$REPO_ROOT/tools/scripts/worktree-cleanup.sh" "$ISSUE_NUM" --check 2>/dev/null || true)
    case "$WT_CHECK" in
      can_cleanup:*)
        WT_PATH="${WT_CHECK#can_cleanup:}"
        echo "Tip: Worktree still exists at $WT_PATH"
        echo "  To clean up: ./tools/scripts/worktree-cleanup.sh $ISSUE_NUM"
        ;;
    esac
  fi
fi

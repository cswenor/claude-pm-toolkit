#!/usr/bin/env bash
set -euo pipefail

# context-digest.sh - Low-token context digest for PM workflows
# Provides a single deterministic snapshot of issue + local environment state.
#
# Usage: context-digest.sh <issue-number> [--compact] [--json]
#
# Outputs issue metadata (title, state, workflow, priority, labels) plus
# local git state (branch, dirty-tree, ahead/behind) and review-gate
# prerequisite summary.
#
# When to use:
#   - Quick context recovery at the start of a session
#   - Pre-PR readiness check (review gate summary)
#   - Low-token alternative to running pm status + git status separately
#
# When NOT to use (use the specific tool instead):
#   - Moving issues between states → pm move
#   - Syncing from GitHub          → pm sync
#   - Detailed project status      → pm status

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve project root: walk up from SCRIPT_DIR until we find .claude-pm-toolkit.json
_find_root() {
  local dir="$SCRIPT_DIR"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude-pm-toolkit.json" ]; then
      echo "$dir"
      return
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback: two levels up from tools/scripts/
  echo "$(cd "$SCRIPT_DIR/../.." && pwd)"
}
PROJECT_ROOT="$(_find_root)"

# Resolve main repo root (works from worktrees and main repo alike)
if command -v git &>/dev/null; then
  COMMON_DIR="$(git rev-parse --git-common-dir 2>/dev/null || echo "")"
  if [[ -n "$COMMON_DIR" && "$COMMON_DIR" != ".git" ]]; then
    MAIN_ROOT="$(cd "$COMMON_DIR/.." && pwd)"
  else
    MAIN_ROOT="$PROJECT_ROOT"
  fi
else
  MAIN_ROOT="$PROJECT_ROOT"
fi

# PM CLI path
PM_CLI="$MAIN_ROOT/tools/mcp/pm-intelligence/build/cli.js"

# ─── Help ─────────────────────────────────────────────────────────────────────
show_help() {
  cat <<'HELPEOF'
context-digest.sh — Low-token context digest for PM workflows

USAGE
  context-digest.sh <issue-number> [--compact] [--json]

OPTIONS
  --json       Output structured JSON (default)
  --compact    One-line summary format
  --help, -h   Show this help

OUTPUT (JSON mode, default)
  {
    "issue_number": 42,
    "issue_title": "...",
    "issue_state": "open",
    "workflow": "Active",
    "priority": "high",
    "labels": [...],
    "assignees": [...],
    "branch": "feat/42-something",
    "dirty": false,
    "ahead": 3,
    "behind": 0,
    "worktree": { "active": true, "path": "/path/to/wt-42" },
    "review_gate": {
      "clean_tree": true,
      "on_feature_branch": true,
      "detached_head": false,
      "no_rebase_in_progress": true,
      "codex_available": true,
      "summary": "ready"
    }
  }

WHEN TO USE
  - Quick context recovery at session start
  - Pre-PR readiness check
  - Low-token alternative to pm status + git status

WHEN NOT TO USE
  - Moving issues between states → pm move <num> <state>
  - Syncing from GitHub          → pm sync
  - Detailed project status      → pm status
HELPEOF
}

# ─── Argument parsing ────────────────────────────────────────────────────────
ISSUE_NUM=""
FORMAT="json"

for arg in "$@"; do
  case "$arg" in
    --help|-h) show_help; exit 0 ;;
    --compact) FORMAT="compact" ;;
    --json)    FORMAT="json" ;;
    --default) FORMAT="default" ;;
    -*)
      echo "Error: Unknown option '$arg'" >&2
      echo "Usage: context-digest.sh <issue-number> [--compact] [--json]" >&2
      exit 1
      ;;
    *)
      if [ -z "$ISSUE_NUM" ]; then
        ISSUE_NUM="$arg"
      else
        echo "Error: Unexpected argument '$arg'" >&2
        echo "Usage: context-digest.sh <issue-number> [--compact] [--json]" >&2
        exit 1
      fi
      ;;
  esac
done

if [ -z "$ISSUE_NUM" ]; then
  echo "Error: Issue number is required" >&2
  echo "Usage: context-digest.sh <issue-number> [--compact] [--json]" >&2
  exit 1
fi

# Validate numeric
if ! echo "$ISSUE_NUM" | grep -qE '^[0-9]+$'; then
  echo "Error: Issue number must be numeric, got '$ISSUE_NUM'" >&2
  exit 1
fi

# ─── Dependency checks ───────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  echo "Error: git not installed" >&2
  exit 1
fi

if ! git rev-parse --git-dir &>/dev/null; then
  echo "Error: Not in a git repository" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq not installed. Run: brew install jq (macOS) or apt install jq (Linux)" >&2
  exit 1
fi

if ! command -v node &>/dev/null; then
  echo "Error: node not installed" >&2
  exit 1
fi

if [ ! -f "$PM_CLI" ]; then
  echo "Error: PM CLI not built at $PM_CLI" >&2
  echo "  Run: make build" >&2
  exit 1
fi

# ─── Issue metadata from local PM database ──────────────────────────────────
# Use pm status <num> and parse the structured output.
# The CLI outputs to terminal with ANSI codes, so we capture and parse.
PM_OUTPUT=""
PM_ERR=""
if ! PM_OUTPUT=$(node "$PM_CLI" status "$ISSUE_NUM" 2>&1); then
  PM_ERR="$PM_OUTPUT"
fi

# If pm status failed, try syncing first then retry
if [ -n "$PM_ERR" ]; then
  node "$PM_CLI" sync 2>/dev/null || true
  if ! PM_OUTPUT=$(node "$PM_CLI" status "$ISSUE_NUM" 2>&1); then
    echo "Error: Could not retrieve issue #$ISSUE_NUM from PM database" >&2
    echo "  $PM_OUTPUT" >&2
    exit 1
  fi
fi

# Parse issue metadata from pm status output (strip ANSI codes, drop blank lines)
CLEAN_OUTPUT=$(echo "$PM_OUTPUT" | sed 's/\x1b\[[0-9;]*m//g' | sed '/^$/d')

# Line 1: "#22: <title>"
# Line 2: "  <Workflow> | <pri_icon> <priority> | <state>"
ISSUE_TITLE=$(echo "$CLEAN_OUTPUT" | sed -n '1p' | sed "s/^#${ISSUE_NUM}: //")
ISSUE_STATE=$(echo "$CLEAN_OUTPUT" | sed -n '2p' | grep -oP '(open|closed)\s*$' | tr -d ' ' || echo "unknown")
WORKFLOW=$(echo "$CLEAN_OUTPUT" | sed -n '2p' | sed 's/^\s*//' | awk '{print $1}')
PRIORITY=$(echo "$CLEAN_OUTPUT" | sed -n '2p' | grep -oP '(critical|high|normal)' | head -1 || echo "normal")

# Extract labels
LABELS_RAW=$(echo "$CLEAN_OUTPUT" | grep '^\s*Labels:' | sed 's/^\s*Labels:\s*//' || echo "")
if [ -n "$LABELS_RAW" ]; then
  LABELS_JSON=$(echo "$LABELS_RAW" | tr ',' '\n' | sed 's/^\s*//;s/\s*$//' | jq -R -s -c 'split("\n") | map(select(length > 0))')
else
  LABELS_JSON="[]"
fi

# Extract assignees
ASSIGNEES_RAW=$(echo "$CLEAN_OUTPUT" | grep '^\s*Assignees:' | sed 's/^\s*Assignees:\s*//' || echo "")
if [ -n "$ASSIGNEES_RAW" ]; then
  ASSIGNEES_JSON=$(echo "$ASSIGNEES_RAW" | tr ',' '\n' | sed 's/^\s*//;s/\s*$//' | jq -R -s -c 'split("\n") | map(select(length > 0))')
else
  ASSIGNEES_JSON="[]"
fi

# ─── Local git state ─────────────────────────────────────────────────────────
BRANCH=$(git branch --show-current 2>/dev/null || echo "")
DIRTY_OUTPUT=$(git status --porcelain 2>/dev/null || echo "")

# Ahead/behind tracking
AHEAD=0
BEHIND=0
if [ -n "$BRANCH" ]; then
  UPSTREAM=$(git rev-parse --abbrev-ref "@{upstream}" 2>/dev/null || echo "")
  if [ -n "$UPSTREAM" ]; then
    AHEAD_BEHIND=$(git rev-list --left-right --count "$BRANCH...$UPSTREAM" 2>/dev/null || echo "0 0")
    AHEAD=$(echo "$AHEAD_BEHIND" | awk '{print $1}')
    BEHIND=$(echo "$AHEAD_BEHIND" | awk '{print $2}')
  fi
fi

# ─── Worktree info ───────────────────────────────────────────────────────────
WORKTREE_ACTIVE=false
WORKTREE_PATH=""

# Read prefix from config
PREFIX_LOWER=""
if [ -f "$PROJECT_ROOT/.claude-pm-toolkit.json" ]; then
  PREFIX_LOWER=$(jq -r '.prefix_lower // ""' "$PROJECT_ROOT/.claude-pm-toolkit.json" 2>/dev/null || echo "")
fi
[ -z "$PREFIX_LOWER" ] && PREFIX_LOWER="wt"

# Check git worktree list for this issue
WT_PATH=$(git worktree list --porcelain | awk -v issue="$ISSUE_NUM" -v pfx="$PREFIX_LOWER" '
  /^worktree / {
    path = substr($0, 10)
    if (path ~ "/" pfx "-" issue "$" || path == pfx "-" issue) {
      print path
      exit
    }
  }
')

if [ -n "$WT_PATH" ] && [ -d "$WT_PATH" ]; then
  WORKTREE_ACTIVE=true
  WORKTREE_PATH="$WT_PATH"
fi

# ─── Review gate prerequisites ───────────────────────────────────────────────
BLOCKERS=()

# Clean tree
if [ -z "$DIRTY_OUTPUT" ]; then
  GATE_CLEAN_TREE=true
else
  GATE_CLEAN_TREE=false
  BLOCKERS+=("dirty-tree")
fi

# Feature branch (not main/master, not empty)
if [ -z "$BRANCH" ]; then
  GATE_FEATURE_BRANCH=false
else
  if [ "$BRANCH" = "main" ] || [ "$BRANCH" = "master" ]; then
    GATE_FEATURE_BRANCH=false
    BLOCKERS+=("on-main")
  else
    GATE_FEATURE_BRANCH=true
  fi
fi

# Detached HEAD
if [ -z "$BRANCH" ]; then
  GATE_DETACHED_HEAD=true
  BLOCKERS+=("detached-head")
else
  GATE_DETACHED_HEAD=false
fi

# No rebase in progress
GIT_DIR=$(git rev-parse --git-dir 2>/dev/null)
if [ -d "$GIT_DIR/rebase-merge" ] || [ -d "$GIT_DIR/rebase-apply" ]; then
  GATE_NO_REBASE=false
  BLOCKERS+=("rebase-in-progress")
else
  GATE_NO_REBASE=true
fi

# Codex available (validate runtime health, not just PATH presence)
if codex --version &>/dev/null; then
  GATE_CODEX=true
else
  GATE_CODEX=false
fi

# Gate summary
if [ ${#BLOCKERS[@]} -eq 0 ]; then
  GATE_SUMMARY="ready"
else
  GATE_SUMMARY="blocked:$(IFS=,; echo "${BLOCKERS[*]}")"
fi

# ─── Output formatting ───────────────────────────────────────────────────────

bool_to_yesno() {
  if [ "$1" = "true" ]; then echo "yes"; else echo "no"; fi
}

case "$FORMAT" in
  json)
    # Build dirty boolean
    if [ "$GATE_CLEAN_TREE" = "true" ]; then
      DIRTY_BOOL="false"
    else
      DIRTY_BOOL="true"
    fi

    jq -n \
      --argjson issue_number "$ISSUE_NUM" \
      --arg issue_title "$ISSUE_TITLE" \
      --arg issue_state "$ISSUE_STATE" \
      --arg workflow "$WORKFLOW" \
      --arg priority "$PRIORITY" \
      --argjson labels "$LABELS_JSON" \
      --argjson assignees "$ASSIGNEES_JSON" \
      --arg branch "${BRANCH:-}" \
      --argjson dirty "$DIRTY_BOOL" \
      --argjson ahead "$AHEAD" \
      --argjson behind "$BEHIND" \
      --argjson worktree_active "$WORKTREE_ACTIVE" \
      --arg worktree_path "$WORKTREE_PATH" \
      --argjson clean_tree "$GATE_CLEAN_TREE" \
      --argjson on_feature_branch "$GATE_FEATURE_BRANCH" \
      --argjson detached_head "$GATE_DETACHED_HEAD" \
      --argjson no_rebase_in_progress "$GATE_NO_REBASE" \
      --argjson codex_available "$GATE_CODEX" \
      --arg summary "$GATE_SUMMARY" \
      '{
        issue_number: $issue_number,
        issue_title: $issue_title,
        issue_state: $issue_state,
        workflow: $workflow,
        priority: $priority,
        labels: $labels,
        assignees: $assignees,
        branch: $branch,
        dirty: $dirty,
        ahead: $ahead,
        behind: $behind,
        worktree: {
          active: $worktree_active,
          path: $worktree_path
        },
        review_gate: {
          clean_tree: $clean_tree,
          on_feature_branch: $on_feature_branch,
          detached_head: $detached_head,
          no_rebase_in_progress: $no_rebase_in_progress,
          codex_available: $codex_available,
          summary: $summary
        }
      }'
    ;;

  compact)
    # Dirty indicator
    if [ "$GATE_CLEAN_TREE" = "true" ]; then
      DIRTY_COMPACT="no"
    else
      DIRTY_COMPACT="yes"
    fi

    # Ahead/behind indicator
    AB_INFO=""
    if [ "$AHEAD" -gt 0 ] || [ "$BEHIND" -gt 0 ]; then
      AB_INFO=" +${AHEAD}/-${BEHIND}"
    fi

    echo "#$ISSUE_NUM $ISSUE_TITLE | $ISSUE_STATE/$WORKFLOW [$PRIORITY] branch:${BRANCH:-detached}${AB_INFO} dirty:$DIRTY_COMPACT gate:$GATE_SUMMARY"
    ;;

  default)
    # Human-readable format
    if [ "$GATE_CLEAN_TREE" = "true" ]; then
      DIRTY_DISPLAY="no"
    else
      DIRTY_DISPLAY="yes"
    fi

    echo "Issue #$ISSUE_NUM: $ISSUE_TITLE"
    echo "  State:     $ISSUE_STATE"
    echo "  Workflow:  $WORKFLOW"
    echo "  Priority:  $PRIORITY"
    echo "  Branch:    ${BRANCH:-"(detached HEAD)"}"
    echo "  Dirty:     $DIRTY_DISPLAY"
    echo "  Ahead:     $AHEAD"
    echo "  Behind:    $BEHIND"
    if [ "$WORKTREE_ACTIVE" = "true" ]; then
      echo "  Worktree:  $WORKTREE_PATH"
    else
      echo "  Worktree:  (none)"
    fi
    echo "  Review Gate:"
    echo "    Clean tree:            $(bool_to_yesno "$GATE_CLEAN_TREE")"
    echo "    Feature branch:        $(bool_to_yesno "$GATE_FEATURE_BRANCH")"
    echo "    Detached HEAD:         $(bool_to_yesno "$GATE_DETACHED_HEAD")"
    echo "    No rebase in progress: $(bool_to_yesno "$GATE_NO_REBASE")"
    echo "    Codex available:       $(bool_to_yesno "$GATE_CODEX")"
    echo "    Summary:               $GATE_SUMMARY"
    ;;
esac

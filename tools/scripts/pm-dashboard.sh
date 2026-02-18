#!/usr/bin/env bash
set -euo pipefail

# pm-dashboard.sh - Health dashboard for claude-pm-toolkit
#
# Shows: toolkit version, validation summary, active work, worktree status,
# portfolio state (if tmux), and project board summary.
#
# Usage: pm-dashboard.sh [--json]

show_help() {
  cat <<'HELPEOF'
pm-dashboard.sh - Health dashboard for claude-pm-toolkit

USAGE
  pm-dashboard.sh
  pm-dashboard.sh --json

OPTIONS
  --json    Output as JSON instead of formatted text

SECTIONS
  1. Toolkit Info       - Version, install date, project identity
  2. Health Checks      - Config validation, gh auth, required tools
  3. Active Worktrees   - Git worktree status for parallel development
  4. Portfolio State    - tmux session status (if portfolio manager active)
  5. Project Board      - Workflow distribution and active/review items

EXAMPLES
  pm-dashboard.sh                    # Show formatted dashboard
  pm-dashboard.sh --json | jq .      # JSON output for scripting
HELPEOF
}

for arg in "$@"; do
  case "$arg" in
    --help|-h) show_help; exit 0 ;;
  esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pm.config.sh"

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

JSON_MODE=false
[[ "${1:-}" == "--json" ]] && JSON_MODE=true

section() { printf "\n${BOLD}%s${RESET}\n" "$*"; }
ok()      { printf "  ${GREEN}●${RESET} %s\n" "$*"; }
warn()    { printf "  ${YELLOW}●${RESET} %s\n" "$*"; }
err()     { printf "  ${RED}●${RESET} %s\n" "$*"; }
dim()     { printf "  ${DIM}%s${RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# 1. Toolkit Info
# ---------------------------------------------------------------------------
section "Toolkit"

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]]; then
  err "Not in a git repository"
  exit 1
fi

METADATA="$REPO_ROOT/.claude-pm-toolkit.json"
if [[ -f "$METADATA" ]]; then
  TOOLKIT_VER=$(jq -r '.toolkit_version // "unknown"' "$METADATA")
  INSTALLED_AT=$(jq -r '.installed_at // "unknown"' "$METADATA")
  UPDATED_AT=$(jq -r '.updated_at // empty' "$METADATA")
  DISPLAY_NAME=$(jq -r '.display_name // "unknown"' "$METADATA")
  ok "Project: $DISPLAY_NAME"
  ok "Owner: $PM_OWNER | Project #$PM_PROJECT_NUMBER"
  if [[ -n "$UPDATED_AT" ]] && [[ "$UPDATED_AT" != "$INSTALLED_AT" ]]; then
    dim "Installed: $INSTALLED_AT | Updated: $UPDATED_AT (toolkit: $TOOLKIT_VER)"
  else
    dim "Installed: $INSTALLED_AT (toolkit: $TOOLKIT_VER)"
  fi
else
  warn "No .claude-pm-toolkit.json found — toolkit may not be installed"
fi

# ---------------------------------------------------------------------------
# 2. Quick validation
# ---------------------------------------------------------------------------
section "Health"

ISSUES_FOUND=0

# Check key files
for f in "tools/scripts/pm.config.sh" ".claude/settings.json" ".claude/skills/issue/SKILL.md"; do
  if [[ ! -f "$REPO_ROOT/$f" ]]; then
    err "Missing: $f"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
  fi
done

# Check for unreplaced placeholders in config
if [[ -f "$REPO_ROOT/tools/scripts/pm.config.sh" ]]; then
  UNRESOLVED=$(grep -cE '^PM_[A-Z_]+="[^"]*\{\{' "$REPO_ROOT/tools/scripts/pm.config.sh" 2>/dev/null || true)
  if [[ "${UNRESOLVED:-0}" -gt 0 ]]; then
    err "$UNRESOLVED unreplaced placeholder(s) in pm.config.sh"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
  fi
fi

# Check gh auth
if ! gh auth status &>/dev/null; then
  err "gh CLI not authenticated"
  ISSUES_FOUND=$((ISSUES_FOUND+1))
else
  # Check project access
  if gh project view "$PM_PROJECT_NUMBER" --owner "$PM_OWNER" &>/dev/null 2>&1; then
    ok "GitHub project accessible"
  elif gh project view "$PM_PROJECT_NUMBER" --owner @me &>/dev/null 2>&1; then
    ok "GitHub project accessible (via @me)"
  else
    warn "Cannot access project #$PM_PROJECT_NUMBER"
    ISSUES_FOUND=$((ISSUES_FOUND+1))
  fi
fi

if [[ $ISSUES_FOUND -eq 0 ]]; then
  ok "All checks passed"
else
  warn "$ISSUES_FOUND issue(s) found — run validate.sh for details"
fi

# ---------------------------------------------------------------------------
# 3. Worktree Status
# ---------------------------------------------------------------------------
section "Worktrees"

WORKTREE_COUNT=0
while IFS= read -r line; do
  if [[ "$line" == worktree\ * ]]; then
    path="${line#worktree }"
    WORKTREE_COUNT=$((WORKTREE_COUNT+1))

    # Read the next lines to get branch info
    read -r head_line || true
    read -r branch_line || true
    read -r blank_line || true  # blank separator

    branch=""
    if [[ "$branch_line" == branch\ * ]]; then
      branch="${branch_line#branch refs/heads/}"
    elif [[ "$head_line" == "HEAD "* ]]; then
      branch="(detached)"
    fi

    basename=$(basename "$path")

    # Check if it looks like a toolkit worktree
    if [[ "$basename" =~ ^[a-z]+-[0-9]+$ ]]; then
      issue_num="${basename##*-}"
      ok "$basename → $branch (#$issue_num)"
    elif [[ "$WORKTREE_COUNT" -eq 1 ]]; then
      dim "$basename (main repo)"
    else
      dim "$basename → $branch"
    fi
  fi
done < <(git worktree list --porcelain 2>/dev/null)

if [[ $WORKTREE_COUNT -le 1 ]]; then
  dim "No worktrees (working from main repo)"
fi

# ---------------------------------------------------------------------------
# 4. Portfolio Status (tmux)
# ---------------------------------------------------------------------------
PREFIX_LOWER=$(jq -r '.prefix_lower // ""' "$METADATA" 2>/dev/null || echo "")
PORTFOLIO_DIR="$HOME/.${PREFIX_LOWER:-pm}/portfolio"

if [[ -d "$PORTFOLIO_DIR" ]] && [[ -n "$(ls -A "$PORTFOLIO_DIR" 2>/dev/null)" ]]; then
  section "Portfolio"

  for issue_dir in "$PORTFOLIO_DIR"/*/; do
    [[ ! -d "$issue_dir" ]] && continue
    issue_num=$(basename "$issue_dir")
    status="unknown"
    last_event=""

    [[ -f "$issue_dir/status" ]] && status=$(cat "$issue_dir/status")
    [[ -f "$issue_dir/last-event" ]] && last_event=$(cat "$issue_dir/last-event")

    case "$status" in
      needs-input|needs-permission) warn "#$issue_num: $status (since $last_event)" ;;
      running)                      ok "#$issue_num: running" ;;
      idle)                         dim "#$issue_num: idle (since $last_event)" ;;
      complete)                     dim "#$issue_num: complete" ;;
      *)                            dim "#$issue_num: $status" ;;
    esac
  done
fi

# ---------------------------------------------------------------------------
# 5. Project Board Summary
# ---------------------------------------------------------------------------
section "Project Board"

REPO_NAME=$(pm_get_repo 2>/dev/null || echo "")
if [[ -z "$REPO_NAME" ]]; then
  warn "Cannot determine repo name"
else
  # Query project board for issue counts by workflow state
  BOARD_DATA=$(gh api graphql -f query='
    query($owner: String!, $num: Int!) {
      user(login: $owner) {
        projectV2(number: $num) {
          items(first: 100) {
            nodes {
              fieldValueByName(name: "Workflow") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue { number title state }
              }
            }
          }
        }
      }
    }
  ' -f owner="$PM_OWNER" -F num="$PM_PROJECT_NUMBER" 2>/dev/null) || \
  BOARD_DATA=$(gh api graphql -f query='
    query($owner: String!, $num: Int!) {
      organization(login: $owner) {
        projectV2(number: $num) {
          items(first: 100) {
            nodes {
              fieldValueByName(name: "Workflow") {
                ... on ProjectV2ItemFieldSingleSelectValue { name }
              }
              content {
                ... on Issue { number title state }
              }
            }
          }
        }
      }
    }
  ' -f owner="$PM_OWNER" -F num="$PM_PROJECT_NUMBER" 2>/dev/null) || true

  if [[ -n "$BOARD_DATA" ]]; then
    # Count issues by workflow state
    # Try user first, then org
    ITEMS=$(echo "$BOARD_DATA" | jq -r '
      (.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
      | map(select(.content != null))
      | group_by(.fieldValueByName.name // "Unset")
      | map({state: .[0].fieldValueByName.name // "Unset", count: length})
      | sort_by(-.count)
      | .[]
      | "\(.state)\t\(.count)"
    ' 2>/dev/null || echo "")

    if [[ -n "$ITEMS" ]]; then
      while IFS=$'\t' read -r state count; do
        case "$state" in
          Active)  printf "  ${GREEN}●${RESET} %-12s %s\n" "$state" "$count" ;;
          Review)  printf "  ${CYAN}●${RESET} %-12s %s\n" "$state" "$count" ;;
          Rework)  printf "  ${YELLOW}●${RESET} %-12s %s\n" "$state" "$count" ;;
          Done)    printf "  ${DIM}● %-12s %s${RESET}\n" "$state" "$count" ;;
          *)       printf "  ● %-12s %s\n" "$state" "$count" ;;
        esac
      done <<< "$ITEMS"

      # Show active issues with titles
      ACTIVE_ISSUES=$(echo "$BOARD_DATA" | jq -r '
        (.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
        | map(select(.fieldValueByName.name == "Active" and .content != null))
        | .[]
        | "#\(.content.number): \(.content.title)"
      ' 2>/dev/null || echo "")

      if [[ -n "$ACTIVE_ISSUES" ]]; then
        printf "\n"
        dim "Active work:"
        while IFS= read -r line; do
          printf "    ${GREEN}→${RESET} %s\n" "$line"
        done <<< "$ACTIVE_ISSUES"
      fi

      # Show review items
      REVIEW_ISSUES=$(echo "$BOARD_DATA" | jq -r '
        (.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
        | map(select((.fieldValueByName.name == "Review" or .fieldValueByName.name == "Rework") and .content != null))
        | .[]
        | "#\(.content.number): \(.content.title) [\(.fieldValueByName.name)]"
      ' 2>/dev/null || echo "")

      if [[ -n "$REVIEW_ISSUES" ]]; then
        dim "Needs attention:"
        while IFS= read -r line; do
          printf "    ${YELLOW}→${RESET} %s\n" "$line"
        done <<< "$REVIEW_ISSUES"
      fi
    else
      dim "No items on project board"
    fi
  else
    warn "Could not query project board"
  fi
fi

# ---------------------------------------------------------------------------
# 6. Health Score (0-100)
# ---------------------------------------------------------------------------
section "Health Score"

HEALTH=100
HEALTH_NOTES=""

# Tooling health (-10 per missing critical file)
for f in "tools/scripts/pm.config.sh" ".claude/settings.json" ".claude/skills/issue/SKILL.md"; do
  if [[ ! -f "$REPO_ROOT/$f" ]]; then
    HEALTH=$((HEALTH - 10))
    HEALTH_NOTES="${HEALTH_NOTES}\n  -10  Missing: $f"
  fi
done

# WIP compliance: more than 1 Active issue = penalty
if [[ -n "${BOARD_DATA:-}" ]]; then
  ACTIVE_COUNT=$(echo "$BOARD_DATA" | jq -r '
    [(.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
    | .[] | select(.fieldValueByName.name == "Active" and .content != null)] | length
  ' 2>/dev/null || echo "0")
  if [[ "$ACTIVE_COUNT" -gt 1 ]]; then
    PENALTY=$((ACTIVE_COUNT * 10))
    HEALTH=$((HEALTH - PENALTY))
    HEALTH_NOTES="${HEALTH_NOTES}\n  -${PENALTY}  WIP violation: $ACTIVE_COUNT items Active (limit: 1)"
  fi

  # Rework pileup: each Rework item = -5
  REWORK_COUNT=$(echo "$BOARD_DATA" | jq -r '
    [(.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
    | .[] | select(.fieldValueByName.name == "Rework" and .content != null)] | length
  ' 2>/dev/null || echo "0")
  if [[ "$REWORK_COUNT" -gt 0 ]]; then
    PENALTY=$((REWORK_COUNT * 5))
    HEALTH=$((HEALTH - PENALTY))
    HEALTH_NOTES="${HEALTH_NOTES}\n  -${PENALTY}  Rework pileup: $REWORK_COUNT item(s) need attention"
  fi

  # Review bottleneck: more than 2 items in Review = -10
  REVIEW_COUNT=$(echo "$BOARD_DATA" | jq -r '
    [(.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
    | .[] | select(.fieldValueByName.name == "Review" and .content != null)] | length
  ' 2>/dev/null || echo "0")
  if [[ "$REVIEW_COUNT" -gt 2 ]]; then
    HEALTH=$((HEALTH - 10))
    HEALTH_NOTES="${HEALTH_NOTES}\n  -10  Review bottleneck: $REVIEW_COUNT items waiting"
  fi

  # Backlog bloat: more than 20 items in Backlog = -5
  BACKLOG_COUNT=$(echo "$BOARD_DATA" | jq -r '
    [(.data.user.projectV2.items.nodes // .data.organization.projectV2.items.nodes // [])
    | .[] | select(.fieldValueByName.name == "Backlog" and .content != null)] | length
  ' 2>/dev/null || echo "0")
  if [[ "$BACKLOG_COUNT" -gt 20 ]]; then
    HEALTH=$((HEALTH - 5))
    HEALTH_NOTES="${HEALTH_NOTES}\n  -5   Backlog bloat: $BACKLOG_COUNT items (consider triaging)"
  fi
fi

# Unreplaced placeholders = -15
if [[ -f "$REPO_ROOT/tools/scripts/pm.config.sh" ]]; then
  UNRESOLVED=$(grep -cE '^PM_[A-Z_]+="[^"]*\{\{' "$REPO_ROOT/tools/scripts/pm.config.sh" 2>/dev/null || true)
  if [[ "${UNRESOLVED:-0}" -gt 0 ]]; then
    HEALTH=$((HEALTH - 15))
    HEALTH_NOTES="${HEALTH_NOTES}\n  -15  Config has unreplaced placeholders"
  fi
fi

# Clamp to 0
[[ $HEALTH -lt 0 ]] && HEALTH=0

# Display
if [[ $HEALTH -ge 80 ]]; then
  printf "  ${GREEN}${BOLD}%d/100${RESET} — Healthy\n" "$HEALTH"
elif [[ $HEALTH -ge 50 ]]; then
  printf "  ${YELLOW}${BOLD}%d/100${RESET} — Needs attention\n" "$HEALTH"
else
  printf "  ${RED}${BOLD}%d/100${RESET} — At risk\n" "$HEALTH"
fi

if [[ -n "$HEALTH_NOTES" ]]; then
  printf "${DIM}%b${RESET}\n" "$HEALTH_NOTES"
fi

printf "\n"

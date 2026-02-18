#!/usr/bin/env bash
set -euo pipefail

# validate.sh - Post-install validation for claude-pm-toolkit
#
# Checks that all toolkit files are present, all placeholders are resolved,
# scripts are executable, and project board integration works.
#
# Usage:
#   ./validate.sh [/path/to/repo]     # Defaults to current directory
#   ./validate.sh --fix [/path/to/repo]  # Auto-fix what's possible

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'
DIM='\033[2m'

log_pass()    { printf "${GREEN}  PASS${RESET}  %s\n" "$*"; }
log_fail()    { printf "${RED}  FAIL${RESET}  %s\n" "$*"; }
log_warn()    { printf "${YELLOW}  WARN${RESET}  %s\n" "$*"; }
log_info()    { printf "${CYAN}  INFO${RESET}  %s\n" "$*"; }
log_section() { printf "\n${BOLD}%s${RESET}\n" "$*"; }

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
FIX_MODE=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --fix) FIX_MODE=true ;;
    --help|-h)
      cat <<'HELPEOF'
validate.sh - Post-install validation for claude-pm-toolkit

USAGE
  validate.sh [/path/to/repo]       Validate installation (defaults to cwd)
  validate.sh --fix [/path/to/repo]  Auto-fix issues where possible

CHECKS PERFORMED
  1. Required/optional files exist
  2. Script permissions (executable)
  3. Placeholder resolution (no remaining {{...}} tokens)
  4. pm.config.sh values (non-empty, no TODOs, no unreplaced placeholders)
  5. CLAUDE.md sentinel block integrity
  6. settings.json validity and hook configuration
  7. .gitignore rules (.claude, .codex-work/)
  8. Metadata file (.claude-pm-toolkit.json) validity
  9. GitHub connectivity (optional, non-blocking)

AUTO-FIX (--fix)
  - Script permissions: chmod +x on non-executable .sh files
  - .gitignore: convert blanket .claude → selective entries
  - .gitignore: add .codex-work/ if missing

EXIT CODES
  0 - All checks passed
  1 - One or more checks failed
HELPEOF
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

TARGET="${TARGET:-.}"
TARGET="$(cd "$TARGET" && pwd)"

PASS=0
FAIL=0
WARN=0
FIXED=0

pass() { PASS=$((PASS+1)); log_pass "$@"; }
fail() { FAIL=$((FAIL+1)); log_fail "$@"; }
warn() { WARN=$((WARN+1)); log_warn "$@"; }

# ---------------------------------------------------------------------------
# 1. Required files
# ---------------------------------------------------------------------------
log_section "1. Required Files"

REQUIRED_FILES=(
  "tools/scripts/pm.config.sh"
  "tools/scripts/project-add.sh"
  "tools/scripts/project-move.sh"
  "tools/scripts/project-status.sh"
  "tools/scripts/project-archive-done.sh"
  "tools/scripts/worktree-setup.sh"
  "tools/scripts/worktree-detect.sh"
  "tools/scripts/worktree-cleanup.sh"
  "tools/scripts/worktree-ports.conf"
  ".claude/settings.json"
  ".claude/skills/issue/SKILL.md"
  ".claude/skills/pm-review/SKILL.md"
  ".claude/skills/weekly/SKILL.md"
  "docs/PM_PLAYBOOK.md"
  "docs/PM_PROJECT_CONFIG.md"
  ".claude-pm-toolkit.json"
)

for f in "${REQUIRED_FILES[@]}"; do
  if [[ -f "$TARGET/$f" ]]; then
    pass "$f"
  else
    fail "$f — MISSING"
  fi
done

# Sub-playbooks and appendices (required for decomposed /issue skill)
SKILL_SUBFILES=(
  ".claude/skills/issue/VERIFICATION.md"
  ".claude/skills/issue/sub-playbooks/duplicate-scan.md"
  ".claude/skills/issue/sub-playbooks/update-existing.md"
  ".claude/skills/issue/sub-playbooks/merge-consolidate.md"
  ".claude/skills/issue/sub-playbooks/discovered-work.md"
  ".claude/skills/issue/sub-playbooks/collaborative-planning.md"
  ".claude/skills/issue/sub-playbooks/implementation-review.md"
  ".claude/skills/issue/sub-playbooks/post-implementation.md"
  ".claude/skills/issue/appendices/templates.md"
  ".claude/skills/issue/appendices/briefing-format.md"
  ".claude/skills/issue/appendices/worktrees.md"
  ".claude/skills/issue/appendices/priority.md"
  ".claude/skills/issue/appendices/codex-reference.md"
  ".claude/skills/issue/appendices/design-rationale.md"
)

for f in "${SKILL_SUBFILES[@]}"; do
  if [[ -f "$TARGET/$f" ]]; then
    pass "$f"
  else
    fail "$f — MISSING (required for /issue skill)"
  fi
done

# Optional files (warn if missing)
OPTIONAL_FILES=(
  "tools/scripts/worktree-urls.conf"
  "tools/scripts/find-plan.sh"
  "tools/scripts/tmux-session.sh"
  "tools/scripts/portfolio-notify.sh"
  "tools/scripts/codex-mcp-overrides.sh"
  "tools/config/command-guard.conf"
  "tools/config/secret-patterns.json"
  "tools/config/secret-paths.conf"
  "reports/weekly/.gitkeep"
  "reports/weekly/analysis/.gitkeep"
  ".github/workflows/pm-post-merge.yml"
  ".github/workflows/pm-pr-check.yml"
)

for f in "${OPTIONAL_FILES[@]}"; do
  if [[ -f "$TARGET/$f" ]]; then
    pass "$f"
  else
    warn "$f — missing (optional)"
  fi
done

# ---------------------------------------------------------------------------
# 2. Script permissions
# ---------------------------------------------------------------------------
log_section "2. Script Permissions"

while IFS= read -r shfile; do
  rel="${shfile#$TARGET/}"
  if [[ -x "$shfile" ]]; then
    pass "$rel is executable"
  else
    if $FIX_MODE; then
      chmod +x "$shfile"
      FIXED=$((FIXED+1))
      pass "$rel — FIXED (chmod +x)"
    else
      fail "$rel is NOT executable (run with --fix to repair)"
    fi
  fi
done < <(find "$TARGET/tools" -name "*.sh" -type f 2>/dev/null | sort)

# ---------------------------------------------------------------------------
# 3. Placeholder check
# ---------------------------------------------------------------------------
log_section "3. Placeholder Resolution"

PLACEHOLDER_COUNT=0
PLACEHOLDER_FILES=""

while IFS= read -r line; do
  file=$(echo "$line" | cut -d: -f1)
  match=$(echo "$line" | cut -d: -f2-)
  rel="${file#$TARGET/}"

  # Skip template-like references in docs (e.g. "format: {{prefix}}-$ISSUE_NUM")
  if [[ "$rel" == *"PM_PLAYBOOK.md"* ]] || [[ "$rel" == *"SKILL.md"* ]]; then
    # Only count if it looks like an unreplaced config placeholder, not a documentation example
    if echo "$match" | grep -qE '\{\{(OWNER|REPO|PROJECT_ID|PROJECT_NUMBER|DISPLAY_NAME|PREFIX|prefix|FIELD_|OPT_|TEST_COMMAND|SETUP_COMMAND|DEV_COMMAND)\}\}'; then
      PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT+1))
      PLACEHOLDER_FILES="$PLACEHOLDER_FILES\n  $rel: $match"
    fi
    continue
  fi

  # In shell scripts, skip echo/printf/comment lines — these reference placeholders
  # as literal text (e.g. error messages about unreplaced placeholders), not actual placeholders
  if [[ "$rel" == *.sh ]]; then
    content="${match#*:}"  # Strip line number prefix
    if echo "$content" | grep -qE '^\s*(echo |printf |#)'; then
      continue
    fi
  fi

  PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT+1))
  PLACEHOLDER_FILES="$PLACEHOLDER_FILES\n  $rel: $match"
done < <(grep -rn '{{[A-Z_a-z]*}}' "$TARGET/tools" "$TARGET/.claude" "$TARGET/docs" \
    --include="*.sh" --include="*.md" --include="*.json" --include="*.conf" \
    2>/dev/null || true)

if [[ $PLACEHOLDER_COUNT -eq 0 ]]; then
  pass "No unresolved placeholders found"
else
  fail "$PLACEHOLDER_COUNT unresolved placeholder(s) found:"
  printf "${DIM}%b${RESET}\n" "$PLACEHOLDER_FILES"
fi

# ---------------------------------------------------------------------------
# 4. pm.config.sh validation
# ---------------------------------------------------------------------------
log_section "4. Configuration (pm.config.sh)"

CONFIG_FILE="$TARGET/tools/scripts/pm.config.sh"
if [[ -f "$CONFIG_FILE" ]]; then
  # Source it in a subshell to check values
  PM_OWNER=""
  PM_PROJECT_ID=""
  PM_PROJECT_NUMBER=""
  PM_FIELD_WORKFLOW=""
  PM_WORKFLOW_ACTIVE=""

  # Safe parse — extract values without eval (printf -v doesn't execute content)
  while IFS='=' read -r key value; do
    # Strip surrounding quotes from value
    value="${value#\"}"
    value="${value%\"}"
    value="${value#\'}"
    value="${value%\'}"
    case "$key" in
      PM_*) printf -v "$key" '%s' "$value" 2>/dev/null || true ;;
    esac
  done < <(grep -E '^PM_[A-Z_]+=' "$CONFIG_FILE" | head -50)

  if [[ -n "$PM_OWNER" ]]; then
    pass "PM_OWNER=$PM_OWNER"
  else
    fail "PM_OWNER is empty"
  fi

  if [[ -n "$PM_PROJECT_ID" ]] && [[ "$PM_PROJECT_ID" != *"TODO"* ]]; then
    pass "PM_PROJECT_ID is set"
  else
    fail "PM_PROJECT_ID is empty or contains TODO"
  fi

  if [[ -n "$PM_PROJECT_NUMBER" ]]; then
    pass "PM_PROJECT_NUMBER=$PM_PROJECT_NUMBER"
  else
    fail "PM_PROJECT_NUMBER is empty"
  fi

  if [[ -n "$PM_FIELD_WORKFLOW" ]] && [[ "$PM_FIELD_WORKFLOW" != *"TODO"* ]]; then
    pass "PM_FIELD_WORKFLOW is set"
  else
    fail "PM_FIELD_WORKFLOW is empty or TODO"
  fi

  if [[ -n "$PM_WORKFLOW_ACTIVE" ]] && [[ "$PM_WORKFLOW_ACTIVE" != *"TODO"* ]]; then
    pass "PM_WORKFLOW_ACTIVE is set"
  else
    fail "PM_WORKFLOW_ACTIVE is empty or TODO — project-move.sh will fail"
  fi

  # Check for unreplaced placeholders in any field (catches broken installs)
  UNRESOLVED_COUNT=$(grep -cE '^PM_[A-Z_]+="[^"]*\{\{' "$CONFIG_FILE" 2>/dev/null || true)
  UNRESOLVED_COUNT="${UNRESOLVED_COUNT:-0}"
  if [[ "$UNRESOLVED_COUNT" -eq 0 ]]; then
    pass "No unreplaced {{...}} placeholders in config values"
  else
    fail "$UNRESOLVED_COUNT config value(s) contain unreplaced {{...}} placeholders"
  fi
else
  fail "pm.config.sh not found"
fi

# ---------------------------------------------------------------------------
# 5. CLAUDE.md sentinel check
# ---------------------------------------------------------------------------
log_section "5. CLAUDE.md Integration"

CLAUDE_MD="$TARGET/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  pass "CLAUDE.md exists"

  HAS_START=$(grep -cF "claude-pm-toolkit:start" "$CLAUDE_MD" || echo 0)
  HAS_END=$(grep -cF "claude-pm-toolkit:end" "$CLAUDE_MD" || echo 0)

  if [[ "$HAS_START" -gt 0 ]] && [[ "$HAS_END" -gt 0 ]]; then
    # Count lines between sentinels (should have content)
    SENTINEL_LINES=$(awk '/claude-pm-toolkit:start/{found=1;next} /claude-pm-toolkit:end/{found=0} found{c++} END{print c+0}' "$CLAUDE_MD")
    if [[ "$SENTINEL_LINES" -gt 0 ]]; then
      pass "PM toolkit sentinel block present ($SENTINEL_LINES lines of content)"
    else
      fail "PM toolkit sentinel block is empty (start/end markers present but no content)"
    fi
  elif [[ "$HAS_START" -gt 0 ]]; then
    fail "Sentinel start marker found but no end marker — CLAUDE.md may be corrupted"
  else
    warn "No claude-pm-toolkit sentinel markers — toolkit sections may not be integrated"
  fi
else
  fail "CLAUDE.md not found"
fi

# ---------------------------------------------------------------------------
# 6. settings.json hooks check
# ---------------------------------------------------------------------------
log_section "6. Claude Settings (hooks)"

SETTINGS_FILE="$TARGET/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  pass ".claude/settings.json exists"

  # Validate JSON structure before inspecting hooks
  if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
    fail ".claude/settings.json is not valid JSON — may be corrupted"
  else
    pass ".claude/settings.json is valid JSON"
  fi

  if jq -e '.hooks' "$SETTINGS_FILE" >/dev/null 2>&1; then
    HOOK_COUNT=$(jq '[.hooks | to_entries[].value | length] | add // 0' "$SETTINGS_FILE")
    if [[ "$HOOK_COUNT" -gt 0 ]]; then
      pass "$HOOK_COUNT hook entries configured"
    else
      warn "hooks section exists but has no entries"
    fi
  else
    warn "No hooks configured in settings.json"
  fi
else
  fail ".claude/settings.json not found"
fi

# ---------------------------------------------------------------------------
# 7. .gitignore check
# ---------------------------------------------------------------------------
log_section "7. Gitignore"

GITIGNORE="$TARGET/.gitignore"
if [[ -f "$GITIGNORE" ]]; then
  if grep -qx '\.claude' "$GITIGNORE"; then
    if $FIX_MODE; then
      awk '
        /^\.claude$/ {
          print ".claude/settings.local.json"
          print ".claude/plans/"
          next
        }
        { print }
      ' "$GITIGNORE" > "${GITIGNORE}.tmp" && mv "${GITIGNORE}.tmp" "$GITIGNORE"
      FIXED=$((FIXED+1))
      pass ".gitignore — FIXED (blanket .claude → selective)"
    else
      fail ".claude is fully gitignored — .claude/settings.json and skills won't be tracked (use --fix)"
    fi
  else
    pass ".claude not blanket-gitignored"
  fi

  if grep -qF '.codex-work/' "$GITIGNORE"; then
    pass ".codex-work/ is gitignored"
  else
    warn ".codex-work/ not gitignored (needed for collaborative planning)"
    if $FIX_MODE; then
      echo '.codex-work/' >> "$GITIGNORE"
      FIXED=$((FIXED+1))
      pass ".codex-work/ — FIXED (added to .gitignore)"
    fi
  fi
else
  warn "No .gitignore found"
fi

# ---------------------------------------------------------------------------
# 8. Metadata file validation
# ---------------------------------------------------------------------------
log_section "8. Metadata File"

METADATA_FILE="$TARGET/.claude-pm-toolkit.json"
if [[ -f "$METADATA_FILE" ]]; then
  if jq empty "$METADATA_FILE" 2>/dev/null; then
    pass ".claude-pm-toolkit.json is valid JSON"
    # Check required fields
    TK_VERSION=$(jq -r '.toolkit_version // empty' "$METADATA_FILE")
    if [[ -n "$TK_VERSION" ]]; then
      pass "toolkit_version: $TK_VERSION"
    else
      warn "toolkit_version not set in metadata"
    fi
    TK_OWNER=$(jq -r '.owner // empty' "$METADATA_FILE")
    if [[ -n "$TK_OWNER" ]]; then
      pass "owner: $TK_OWNER"
    else
      warn "owner not set in metadata"
    fi
  else
    fail ".claude-pm-toolkit.json is not valid JSON — may be corrupted"
  fi
else
  warn ".claude-pm-toolkit.json not found — toolkit may not be fully installed"
fi

# ---------------------------------------------------------------------------
# 9. GitHub connectivity (optional, non-blocking)
# ---------------------------------------------------------------------------
log_section "9. GitHub Connectivity (optional)"

if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  if [[ -f "$CONFIG_FILE" ]]; then
    while IFS='=' read -r key value; do
      value="${value#\"}"
      value="${value%\"}"
      case "$key" in
        PM_OWNER|PM_PROJECT_NUMBER) printf -v "$key" '%s' "$value" 2>/dev/null || true ;;
      esac
    done < <(grep -E '^PM_(OWNER|PROJECT_NUMBER)=' "$CONFIG_FILE" | head -5)
    if [[ -n "${PM_OWNER:-}" ]] && [[ -n "${PM_PROJECT_NUMBER:-}" ]]; then
      if gh project view "$PM_PROJECT_NUMBER" --owner "$PM_OWNER" &>/dev/null; then
        pass "Project #$PM_PROJECT_NUMBER accessible for $PM_OWNER"
      else
        # Try @me fallback
        if gh project view "$PM_PROJECT_NUMBER" --owner @me &>/dev/null; then
          pass "Project #$PM_PROJECT_NUMBER accessible (via @me)"
        else
          warn "Cannot access project #$PM_PROJECT_NUMBER for $PM_OWNER (check permissions)"
        fi
      fi
    fi
  fi
else
  warn "gh CLI not available or not authenticated — skipping connectivity check"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Summary"

printf "  ${GREEN}%d passed${RESET}" "$PASS"
if [[ $FAIL -gt 0 ]]; then
  printf "  ${RED}%d failed${RESET}" "$FAIL"
fi
if [[ $WARN -gt 0 ]]; then
  printf "  ${YELLOW}%d warnings${RESET}" "$WARN"
fi
if [[ $FIXED -gt 0 ]]; then
  printf "  ${CYAN}%d fixed${RESET}" "$FIXED"
fi
printf "\n\n"

if [[ $FAIL -gt 0 ]]; then
  printf "${RED}Validation failed.${RESET} Fix the issues above"
  if ! $FIX_MODE; then
    printf " or re-run with ${BOLD}--fix${RESET}"
  fi
  printf ".\n"
  if ! $FIX_MODE; then
    printf "\n${DIM}Tip: ./validate.sh --fix %s  (auto-fixes permissions and .gitignore)${RESET}\n" "$TARGET"
    printf "${DIM}     install.sh --update %s   (re-discovers project field IDs)${RESET}\n" "$TARGET"
  fi
  exit 1
elif [[ $WARN -gt 0 ]]; then
  printf "${YELLOW}Validation passed with warnings.${RESET} Review warnings above.\n"
  exit 0
else
  printf "${GREEN}All checks passed.${RESET} Toolkit is properly installed.\n"
  exit 0
fi

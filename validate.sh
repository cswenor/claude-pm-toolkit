#!/usr/bin/env bash
set -euo pipefail

# validate.sh - Post-install validation for claude-pm-toolkit
#
# v0.15.0: Local-first SQLite architecture. Validates pm CLI, MCP server build,
# .claude-pm-toolkit.json config, CLAUDE.md sentinels, hooks, and gitignore.
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
  4. Configuration (.claude-pm-toolkit.json validity)
  5. MCP server build (build/index.js, build/cli.js exist)
  6. CLAUDE.md sentinel block integrity
  7. settings.json validity and hook configuration
  8. .gitignore rules (.claude, .codex-work/, .pm/)
  9. GitHub connectivity (optional, non-blocking)

AUTO-FIX (--fix)
  - Script permissions: chmod +x on non-executable .sh files
  - .gitignore: convert blanket .claude → selective entries
  - .gitignore: add .codex-work/ and .pm/ if missing

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
  "tools/scripts/worktree-setup.sh"
  "tools/scripts/worktree-detect.sh"
  "tools/scripts/worktree-cleanup.sh"
  ".claude/settings.json"
  ".claude/skills/issue/SKILL.md"
  ".claude/skills/pm-review/SKILL.md"
  ".claude/skills/weekly/SKILL.md"
  ".claude/skills/start/SKILL.md"
  "docs/PM_PLAYBOOK.md"
  "docs/PM_PROJECT_CONFIG.md"
  ".claude-pm-toolkit.json"
  "tools/mcp/pm-intelligence/package.json"
  "tools/mcp/pm-intelligence/src/index.ts"
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
  "tools/scripts/worktree-ports.conf"
  "tools/scripts/worktree-urls.conf"
  "tools/scripts/find-plan.sh"
  "tools/scripts/tmux-session.sh"
  "tools/scripts/portfolio-notify.sh"
  "tools/scripts/codex-mcp-overrides.sh"
  "tools/scripts/claude-command-guard.sh"
  "tools/scripts/claude-secret-guard.sh"
  "tools/scripts/claude-secret-bash-guard.sh"
  "tools/scripts/claude-secret-detect.sh"
  "tools/scripts/claude-secret-check-path.sh"
  "tools/scripts/pm-commit-guard.sh"
  "tools/scripts/pm-stop-guard.sh"
  "tools/scripts/pm-event-log.sh"
  "tools/scripts/pm-session-context.sh"
  "tools/scripts/makefile-targets.mk"
  "tools/config/command-guard.conf"
  "tools/config/secret-patterns.json"
  "tools/config/secret-paths.conf"
  "reports/weekly/.gitkeep"
  "reports/weekly/analysis/.gitkeep"
  ".github/workflows/pm-post-merge.yml"
  ".github/workflows/pm-pr-check.yml"
  ".mcp.json"
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
    # Only count if it looks like an unreplaced config placeholder
    if echo "$match" | grep -qE '\{\{(OWNER|REPO|DISPLAY_NAME|PREFIX|prefix|TEST_COMMAND|SETUP_COMMAND|DEV_COMMAND)\}\}'; then
      PLACEHOLDER_COUNT=$((PLACEHOLDER_COUNT+1))
      PLACEHOLDER_FILES="$PLACEHOLDER_FILES\n  $rel: $match"
    fi
    continue
  fi

  # In shell scripts, skip echo/printf/comment lines
  if [[ "$rel" == *.sh ]]; then
    content="${match#*:}"
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
# 4. Configuration (.claude-pm-toolkit.json)
# ---------------------------------------------------------------------------
log_section "4. Configuration (.claude-pm-toolkit.json)"

METADATA_FILE="$TARGET/.claude-pm-toolkit.json"
if [[ -f "$METADATA_FILE" ]]; then
  if jq empty "$METADATA_FILE" 2>/dev/null; then
    pass ".claude-pm-toolkit.json is valid JSON"

    TK_VERSION=$(jq -r '.toolkit_version // empty' "$METADATA_FILE")
    if [[ -n "$TK_VERSION" ]]; then
      pass "toolkit_version: $TK_VERSION"
    else
      warn "toolkit_version not set"
    fi

    TK_OWNER=$(jq -r '.owner // empty' "$METADATA_FILE")
    if [[ -n "$TK_OWNER" ]]; then
      pass "owner: $TK_OWNER"
    else
      fail "owner not set — pm sync will not work"
    fi

    TK_REPO=$(jq -r '.repo // empty' "$METADATA_FILE")
    if [[ -n "$TK_REPO" ]]; then
      pass "repo: $TK_REPO"
    else
      fail "repo not set — pm sync will not work"
    fi

    TK_PREFIX=$(jq -r '.prefix_lower // empty' "$METADATA_FILE")
    if [[ -n "$TK_PREFIX" ]]; then
      pass "prefix: $TK_PREFIX"
    else
      warn "prefix_lower not set"
    fi
  else
    fail ".claude-pm-toolkit.json is not valid JSON — may be corrupted"
  fi
else
  fail ".claude-pm-toolkit.json not found — toolkit not properly installed"
fi

# ---------------------------------------------------------------------------
# 5. MCP Server Build
# ---------------------------------------------------------------------------
log_section "5. MCP Server Build"

MCP_DIR="$TARGET/tools/mcp/pm-intelligence"

if [[ -d "$MCP_DIR" ]]; then
  pass "MCP server source directory exists"

  if [[ -f "$MCP_DIR/build/index.js" ]]; then
    pass "build/index.js exists (MCP server entry)"
  else
    fail "build/index.js missing — run: cd $MCP_DIR && npm install && npm run build"
  fi

  if [[ -f "$MCP_DIR/build/cli.js" ]]; then
    pass "build/cli.js exists (pm CLI entry)"
  else
    fail "build/cli.js missing — run: cd $MCP_DIR && npm install && npm run build"
  fi

  if [[ -d "$MCP_DIR/node_modules" ]]; then
    pass "node_modules installed"
    if [[ -d "$MCP_DIR/node_modules/better-sqlite3" ]]; then
      pass "better-sqlite3 dependency present"
    else
      fail "better-sqlite3 missing — run: cd $MCP_DIR && npm install"
    fi
  else
    fail "node_modules missing — run: cd $MCP_DIR && npm install"
  fi

  # Check .mcp.json references the server
  MCP_JSON="$TARGET/.mcp.json"
  if [[ -f "$MCP_JSON" ]]; then
    if jq -e '.mcpServers["pm-intelligence"]' "$MCP_JSON" >/dev/null 2>&1; then
      pass "pm-intelligence registered in .mcp.json"
    else
      warn "pm-intelligence not found in .mcp.json — MCP tools won't load"
    fi
  else
    warn ".mcp.json not found — MCP tools won't load"
  fi
else
  fail "MCP server directory not found: tools/mcp/pm-intelligence"
fi

# ---------------------------------------------------------------------------
# 6. CLAUDE.md sentinel check
# ---------------------------------------------------------------------------
log_section "6. CLAUDE.md Integration"

CLAUDE_MD="$TARGET/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]]; then
  pass "CLAUDE.md exists"

  HAS_START=$(grep -cF "claude-pm-toolkit:start" "$CLAUDE_MD" || echo 0)
  HAS_END=$(grep -cF "claude-pm-toolkit:end" "$CLAUDE_MD" || echo 0)

  if [[ "$HAS_START" -gt 0 ]] && [[ "$HAS_END" -gt 0 ]]; then
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
# 7. settings.json hooks check
# ---------------------------------------------------------------------------
log_section "7. Claude Settings (hooks)"

SETTINGS_FILE="$TARGET/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]]; then
  pass ".claude/settings.json exists"

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
# 8. .gitignore check
# ---------------------------------------------------------------------------
log_section "8. Gitignore"

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

  if grep -qF '.pm/' "$GITIGNORE"; then
    pass ".pm/ is gitignored"
  else
    warn ".pm/ not gitignored (SQLite database should not be committed)"
    if $FIX_MODE; then
      echo '.pm/' >> "$GITIGNORE"
      FIXED=$((FIXED+1))
      pass ".pm/ — FIXED (added to .gitignore)"
    fi
  fi
else
  warn "No .gitignore found"
fi

# ---------------------------------------------------------------------------
# 9. GitHub connectivity (optional, non-blocking)
# ---------------------------------------------------------------------------
log_section "9. GitHub Connectivity (optional)"

if command -v gh &>/dev/null && gh auth status &>/dev/null; then
  pass "gh CLI authenticated"

  # Read owner/repo from metadata file
  if [[ -f "$METADATA_FILE" ]] && jq empty "$METADATA_FILE" 2>/dev/null; then
    GH_OWNER=$(jq -r '.owner // empty' "$METADATA_FILE")
    GH_REPO=$(jq -r '.repo // empty' "$METADATA_FILE")

    if [[ -n "$GH_OWNER" ]] && [[ -n "$GH_REPO" ]]; then
      if gh repo view "$GH_OWNER/$GH_REPO" --json name >/dev/null 2>&1; then
        pass "Repository $GH_OWNER/$GH_REPO is accessible"
      else
        warn "Cannot access repository $GH_OWNER/$GH_REPO (check permissions)"
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
    printf "\n${DIM}Tip: ./validate.sh --fix %s  (auto-fixes permissions, .gitignore)${RESET}\n" "$TARGET"
    printf "${DIM}     ./install.sh --update %s  (refresh toolkit files)${RESET}\n" "$TARGET"
  fi
  exit 1
elif [[ $WARN -gt 0 ]]; then
  printf "${YELLOW}Validation passed with warnings.${RESET} Review warnings above.\n"
  exit 0
else
  printf "${GREEN}All checks passed.${RESET} Toolkit is properly installed.\n"
  exit 0
fi

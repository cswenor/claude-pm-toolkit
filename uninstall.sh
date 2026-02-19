#!/usr/bin/env bash
set -euo pipefail

# uninstall.sh - Remove claude-pm-toolkit from an existing repository
#
# v0.15.0: Updated for local-first SQLite architecture.
# Removes pm CLI, MCP server build artifacts, .pm/ database, and all toolkit files.
#
# Usage:
#   ./uninstall.sh /path/to/your/repo             # Show what would be removed
#   ./uninstall.sh --confirm /path/to/your/repo    # Actually remove files

# ---------------------------------------------------------------------------
# Colors
# ---------------------------------------------------------------------------
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

log_info()    { printf "${CYAN}[info]${RESET}  %s\n" "$*"; }
log_ok()      { printf "${GREEN}[ok]${RESET}    %s\n" "$*"; }
log_warn()    { printf "${YELLOW}[warn]${RESET}  %s\n" "$*"; }
log_error()   { printf "${RED}[error]${RESET} %s\n" "$*" >&2; }
log_section() { printf "\n${BOLD}%s${RESET}\n%s\n" "$*" "$(printf '%0.s-' {1..60})"; }

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
CONFIRM=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --confirm) CONFIRM=true ;;
    --help|-h)
      cat <<EOF
uninstall.sh - Remove claude-pm-toolkit from a repository

USAGE
  ./uninstall.sh /path/to/repo             # Dry run (show what would be removed)
  ./uninstall.sh --confirm /path/to/repo   # Actually remove files

WHAT IT REMOVES
  - tools/scripts/ (worktree-*.sh, claude-*-guard.sh, claude-secret-*.sh, pm-*.sh)
  - tools/config/ (command-guard.conf, secret-patterns.json, secret-paths.conf)
  - tools/mcp/pm-intelligence/build/ (compiled MCP server)
  - tools/mcp/pm-intelligence/node_modules/ (dependencies)
  - .claude/skills/issue/, .claude/skills/pm-review/, .claude/skills/weekly/, .claude/skills/start/
  - docs/PM_PLAYBOOK.md, docs/PM_PROJECT_CONFIG.md
  - reports/weekly/ (directory structure only, not reports you generated)
  - .claude-pm-toolkit.json (metadata)
  - .pm/ (local SQLite database and state)
  - pm-intelligence entry from .mcp.json

WHAT IT PRESERVES
  - CLAUDE.md (sentinel block removed, rest untouched)
  - .claude/settings.json (toolkit hooks removed, rest untouched)
  - .mcp.json (only pm-intelligence entry removed, rest untouched)
  - MCP server source files (tools/mcp/pm-intelligence/src/)
  - Any files not installed by the toolkit

EOF
      exit 0
      ;;
    *) TARGET="$arg" ;;
  esac
done

# Temp file cleanup trap
TEMP_FILES=()
cleanup_temp_files() {
  for tf in "${TEMP_FILES[@]}"; do
    [[ -f "$tf" ]] && rm -f "$tf"
  done
}
trap cleanup_temp_files EXIT

if [[ -z "$TARGET" ]]; then
  log_error "Usage: ./uninstall.sh [--confirm] /path/to/repo"
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  log_error "Target directory does not exist: $TARGET"
  exit 1
fi

TARGET="$(cd "$TARGET" && pwd)"

# Check for metadata file
METADATA="$TARGET/.claude-pm-toolkit.json"
if [[ ! -f "$METADATA" ]]; then
  log_warn "No .claude-pm-toolkit.json found — toolkit may not be installed here"
  log_warn "Continuing anyway (will remove known toolkit files if found)"
fi

# ---------------------------------------------------------------------------
# Files and directories to remove
# ---------------------------------------------------------------------------

# Toolkit-installed scripts and config files
TOOLKIT_FILES=(
  # Scripts
  "tools/scripts/worktree-setup.sh"
  "tools/scripts/worktree-detect.sh"
  "tools/scripts/worktree-cleanup.sh"
  "tools/scripts/worktree-ports.conf"
  "tools/scripts/worktree-urls.conf"
  "tools/scripts/tmux-session.sh"
  "tools/scripts/portfolio-notify.sh"
  "tools/scripts/find-plan.sh"
  "tools/scripts/claude-command-guard.sh"
  "tools/scripts/claude-secret-guard.sh"
  "tools/scripts/claude-secret-bash-guard.sh"
  "tools/scripts/claude-secret-detect.sh"
  "tools/scripts/claude-secret-check-path.sh"
  "tools/scripts/codex-mcp-overrides.sh"
  "tools/scripts/pm-commit-guard.sh"
  "tools/scripts/pm-stop-guard.sh"
  "tools/scripts/pm-event-log.sh"
  "tools/scripts/pm-session-context.sh"
  "tools/scripts/pm-dashboard.sh"
  "tools/scripts/makefile-targets.mk"
  # Config
  "tools/config/command-guard.conf"
  "tools/config/secret-patterns.json"
  "tools/config/secret-paths.conf"
  # Docs
  "docs/PM_PLAYBOOK.md"
  "docs/PM_PROJECT_CONFIG.md"
  "AGENTS.md"
  # Metadata
  ".claude-pm-toolkit.json"
)

# Toolkit-installed directories (removed recursively or if empty)
TOOLKIT_DIRS_RECURSIVE=(
  ".claude/skills/issue"
  ".claude/skills/pm-review"
  ".claude/skills/weekly"
  ".claude/skills/start"
  ".pm"
  "tools/mcp/pm-intelligence/build"
  "tools/mcp/pm-intelligence/node_modules"
)

# Directories to remove only if empty (bottom-up)
TOOLKIT_DIRS_IF_EMPTY=(
  ".claude/skills"
  "tools/mcp/pm-intelligence"
  "tools/mcp"
  "tools/config"
  "tools/scripts"
  "tools"
  "reports/weekly/analysis"
  "reports/weekly"
  "reports"
)

# ---------------------------------------------------------------------------
# Sentinel block in CLAUDE.md
# ---------------------------------------------------------------------------
SENTINEL_START="<!-- claude-pm-toolkit:start -->"
SENTINEL_END="<!-- claude-pm-toolkit:end -->"

# ---------------------------------------------------------------------------
# Hooks in settings.json
# ---------------------------------------------------------------------------
TOOLKIT_HOOK_SCRIPTS=(
  "./tools/scripts/claude-command-guard.sh"
  "./tools/scripts/claude-secret-bash-guard.sh"
  "./tools/scripts/claude-secret-guard.sh"
  "./tools/scripts/claude-secret-detect.sh"
  "./tools/scripts/portfolio-notify.sh"
  "./tools/scripts/pm-commit-guard.sh"
  "./tools/scripts/pm-event-log.sh"
  "./tools/scripts/pm-stop-guard.sh"
)

# ---------------------------------------------------------------------------
# Dry run or execute
# ---------------------------------------------------------------------------

if ! $CONFIRM; then
  log_section "DRY RUN — showing what would be removed"
  log_info "Run with --confirm to actually remove files"
  printf "\n"
fi

removed_count=0

# Remove individual files
log_section "Toolkit files"
for rel in "${TOOLKIT_FILES[@]}"; do
  full="$TARGET/$rel"
  if [[ -f "$full" ]]; then
    if $CONFIRM; then
      rm "$full"
      log_ok "Removed: $rel"
    else
      log_info "Would remove: $rel"
    fi
    removed_count=$((removed_count + 1))
  fi
done

# Remove directories recursively (skills, .pm, build artifacts)
log_section "Toolkit directories (recursive)"
for dir_rel in "${TOOLKIT_DIRS_RECURSIVE[@]}"; do
  full="$TARGET/$dir_rel"
  if [[ -d "$full" ]]; then
    if $CONFIRM; then
      rm -rf "$full"
      log_ok "Removed: $dir_rel/"
    else
      log_info "Would remove: $dir_rel/"
    fi
    removed_count=$((removed_count + 1))
  fi
done

# Remove .gitkeep files in report dirs
for gitkeep in "reports/weekly/.gitkeep" "reports/weekly/analysis/.gitkeep"; do
  full="$TARGET/$gitkeep"
  if [[ -f "$full" ]]; then
    if $CONFIRM; then
      rm "$full"
      log_ok "Removed: $gitkeep"
    else
      log_info "Would remove: $gitkeep"
    fi
    removed_count=$((removed_count + 1))
  fi
done

# Clean up empty directories (bottom-up order)
log_section "Empty directories"
for dir_rel in "${TOOLKIT_DIRS_IF_EMPTY[@]}"; do
  full="$TARGET/$dir_rel"
  if [[ -d "$full" ]] && [[ -z "$(ls -A "$full" 2>/dev/null)" ]]; then
    if $CONFIRM; then
      rmdir "$full"
      log_ok "Removed empty dir: $dir_rel/"
    else
      log_info "Would remove empty dir: $dir_rel/"
    fi
  fi
done

# Clean sentinel block from CLAUDE.md
log_section "CLAUDE.md sentinel block"
CLAUDE_MD="$TARGET/CLAUDE.md"
if [[ -f "$CLAUDE_MD" ]] && grep -qF "$SENTINEL_START" "$CLAUDE_MD"; then
  if $CONFIRM; then
    tmp_md=$(mktemp)
    TEMP_FILES+=("$tmp_md")
    awk -v start="$SENTINEL_START" -v end="$SENTINEL_END" \
        'BEGIN { skip=0 }
         $0 == start { skip=1; next }
         $0 == end   { skip=0; next }
         !skip       { print }
        ' "$CLAUDE_MD" > "$tmp_md"
    mv "$tmp_md" "$CLAUDE_MD"
    log_ok "Removed sentinel block from CLAUDE.md"
  else
    log_info "Would remove sentinel block from CLAUDE.md"
  fi
  removed_count=$((removed_count + 1))
else
  log_info "No sentinel block found in CLAUDE.md"
fi

# Clean Makefile sentinel block
log_section "Makefile targets"
TARGET_MAKEFILE="$TARGET/Makefile"
MK_SENTINEL_START="# claude-pm-toolkit:start"
MK_SENTINEL_END="# claude-pm-toolkit:end"
if [[ -f "$TARGET_MAKEFILE" ]] && grep -qF "$MK_SENTINEL_START" "$TARGET_MAKEFILE"; then
  if $CONFIRM; then
    tmp_mk=$(mktemp)
    TEMP_FILES+=("$tmp_mk")
    awk -v start="$MK_SENTINEL_START" -v end="$MK_SENTINEL_END" \
        'BEGIN { skip=0 }
         $0 == start { skip=1; next }
         $0 == end   { skip=0; next }
         !skip       { print }
        ' "$TARGET_MAKEFILE" > "$tmp_mk"
    mv "$tmp_mk" "$TARGET_MAKEFILE"
    log_ok "Removed toolkit targets from Makefile"
  else
    log_info "Would remove toolkit targets from Makefile"
  fi
  removed_count=$((removed_count + 1))
else
  log_info "No toolkit targets found in Makefile"
fi

# Remove pm-intelligence from .mcp.json
log_section "MCP configuration (.mcp.json)"
MCP_JSON="$TARGET/.mcp.json"
if [[ -f "$MCP_JSON" ]] && jq -e '.mcpServers["pm-intelligence"]' "$MCP_JSON" >/dev/null 2>&1; then
  if $CONFIRM; then
    tmp_mcp=$(mktemp)
    TEMP_FILES+=("$tmp_mcp")
    if jq 'del(.mcpServers["pm-intelligence"]) | if (.mcpServers | length) == 0 then del(.mcpServers) else . end' "$MCP_JSON" > "$tmp_mcp" 2>/dev/null; then
      mv "$tmp_mcp" "$MCP_JSON"
      # If the resulting .mcp.json is effectively empty, remove it
      if jq -e 'length == 0 or (keys == ["mcpServers"] and (.mcpServers | length) == 0)' "$MCP_JSON" >/dev/null 2>&1; then
        rm "$MCP_JSON"
        log_ok "Removed .mcp.json (was empty after removing pm-intelligence)"
      else
        log_ok "Removed pm-intelligence from .mcp.json"
      fi
    else
      rm -f "$tmp_mcp"
      log_warn "Could not remove pm-intelligence from .mcp.json — edit manually"
    fi
  else
    log_info "Would remove pm-intelligence entry from .mcp.json"
  fi
  removed_count=$((removed_count + 1))
else
  log_info "No pm-intelligence entry found in .mcp.json"
fi

# Clean hooks from settings.json
log_section "Settings.json hooks"
SETTINGS="$TARGET/.claude/settings.json"
if [[ -f "$SETTINGS" ]]; then
  hooks_found=false
  for script in "${TOOLKIT_HOOK_SCRIPTS[@]}"; do
    if grep -qF "$script" "$SETTINGS"; then
      hooks_found=true
      break
    fi
  done

  if $hooks_found; then
    if $CONFIRM; then
      # Remove hook entries that reference toolkit scripts
      JQ_SCRIPTS=""
      for script in "${TOOLKIT_HOOK_SCRIPTS[@]}"; do
        JQ_SCRIPTS="${JQ_SCRIPTS:+$JQ_SCRIPTS, }\"$script\""
      done

      if jq '
        . as $root |
        ['"$JQ_SCRIPTS"'] as $scripts |
        [$root.hooks // {} | keys[]] as $events |
        reduce $events[] as $event ($root;
          .hooks[$event] = [
            .hooks[$event][] |
            if .hooks then
              .hooks = [.hooks[] | select(
                .command as $cmd |
                ($scripts | any(. as $s | $cmd | startswith($s))) | not
              )] |
              if (.hooks | length) > 0 then . else empty end
            else
              .
            end
          ] |
          if (.hooks[$event] | length) == 0 then del(.hooks[$event]) else . end
        ) |
        if (.hooks // {} | length) == 0 then del(.hooks) else . end
      ' "$SETTINGS" > "${SETTINGS}.tmp" 2>/dev/null; then
        mv "${SETTINGS}.tmp" "$SETTINGS"
        log_ok "Removed toolkit hooks from settings.json"
      else
        rm -f "${SETTINGS}.tmp"
        log_warn "Could not remove hooks from settings.json automatically"
        log_warn "Manually remove entries referencing these scripts:"
        for script in "${TOOLKIT_HOOK_SCRIPTS[@]}"; do
          printf "  - %s\n" "$script"
        done
      fi
    else
      log_info "Would remove toolkit hooks from settings.json"
    fi
    removed_count=$((removed_count + 1))
  else
    log_info "No toolkit hooks found in settings.json"
  fi
else
  log_info "No settings.json found"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf "\n"
if $CONFIRM; then
  log_section "Uninstall complete"
  log_ok "Removed $removed_count items"
  log_info "Your CLAUDE.md and settings.json have been cleaned (non-toolkit content preserved)"
  log_info "You may want to run: git diff  to review changes before committing"
else
  log_section "Dry run complete"
  log_info "Would remove $removed_count items"
  log_info "Run with --confirm to actually remove files:"
  printf "  ./uninstall.sh --confirm %s\n" "$TARGET"
fi

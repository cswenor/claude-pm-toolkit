#!/usr/bin/env bash
set -euo pipefail

# install.sh - Install or update claude-pm-toolkit in an existing repository
#
# v0.15.0: Local-first architecture. No more GitHub Projects field IDs.
# Config is just owner/repo, everything else lives in local SQLite.
#
# Modes:
#   Fresh install:  Prompts for config, copies files, builds MCP server
#   Update:         Reads saved config, overwrites toolkit files, preserves customizations
#
# Usage:
#   ./install.sh /path/to/existing/repo           # Fresh install
#   ./install.sh --update /path/to/existing/repo   # Update from latest toolkit
#   ./install.sh --help

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
log_skip()    { printf "${YELLOW}[skip]${RESET}  %s\n" "$*"; }
log_section() { printf "\n${BOLD}%s${RESET}\n%s\n" "$*" "$(printf '%0.s-' {1..60})"; }

# Cleanup trap for temp files
TEMP_FILES=()
cleanup_temp_files() {
  for tf in "${TEMP_FILES[@]+"${TEMP_FILES[@]}"}"; do
    [[ -f "$tf" ]] && rm -f "$tf"
  done
}
trap cleanup_temp_files EXIT

# ---------------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------------
show_help() {
  cat <<EOF
install.sh - Install or update claude-pm-toolkit in an existing repository

USAGE
  ./install.sh /path/to/target/repo              # Fresh install
  ./install.sh --update /path/to/target/repo      # Update existing installation

MODES
  Fresh install (default):
    - Prompts for project configuration (owner, repo, prefix)
    - Copies template files with replacements applied
    - Builds MCP server (pm-intelligence)
    - Creates .claude-pm-toolkit.json metadata file
    - Runs initial GitHub sync into local SQLite

  Update (--update):
    - Reads config from existing .claude-pm-toolkit.json
    - Overwrites toolkit-managed files (scripts, skills, docs)
    - Preserves user customizations (ports.conf, urls.conf, PM_PROJECT_CONFIG.md)
    - Refreshes CLAUDE.md sentinel block and settings.json hooks
    - Rebuilds MCP server

PREREQUISITES
  - gh CLI (authenticated)
  - jq
  - node >= 18
  - Target directory must be a git repository

ARGUMENTS
  /path/to/target/repo   Path to the existing repository
EOF
  exit 0
}

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
UPDATE_MODE=false
TARGET=""

for arg in "$@"; do
  case "$arg" in
    --help|-h) show_help ;;
    --update)  UPDATE_MODE=true ;;
    *)         TARGET="$arg" ;;
  esac
done

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
log_section "Checking prerequisites"

MISSING_DEPS=()
if ! command -v gh &>/dev/null; then
  MISSING_DEPS+=("gh (https://cli.github.com)")
fi
if ! command -v jq &>/dev/null; then
  MISSING_DEPS+=("jq (brew install jq  /  apt install jq)")
fi
if ! command -v node &>/dev/null; then
  MISSING_DEPS+=("node >= 18 (https://nodejs.org)")
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  log_error "Missing required tools:"
  for dep in "${MISSING_DEPS[@]}"; do
    printf "  - %s\n" "$dep" >&2
  done
  exit 1
fi
log_ok "gh, jq, and node found"

# Check node version
NODE_MAJOR=$(node -e 'console.log(process.versions.node.split(".")[0])')
if [[ "$NODE_MAJOR" -lt 18 ]]; then
  log_error "Node.js >= 18 required (found v$(node --version))"
  exit 1
fi
log_ok "Node.js v$(node --version)"

if ! gh auth status &>/dev/null; then
  log_error "gh CLI is not authenticated. Run: gh auth login"
  exit 1
fi
log_ok "gh authenticated"

# ---------------------------------------------------------------------------
# Validate target argument
# ---------------------------------------------------------------------------
if [[ -z "$TARGET" ]]; then
  log_error "Usage: ./install.sh [--update] /path/to/existing/repo"
  exit 1
fi

if [[ ! -d "$TARGET" ]]; then
  log_error "Target directory does not exist: $TARGET"
  exit 1
fi

# Resolve to absolute path (after existence check)
TARGET="$(cd "$TARGET" && pwd)"

if ! git -C "$TARGET" rev-parse --git-dir &>/dev/null; then
  log_error "Target is not a git repository: $TARGET"
  exit 1
fi
log_ok "Target is a git repo: $TARGET"

TOOLKIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
METADATA_FILE="$TARGET/.claude-pm-toolkit.json"

# ---------------------------------------------------------------------------
# User config files (NEVER overwritten in update mode)
# ---------------------------------------------------------------------------
USER_CONFIG_FILES=(
  "tools/scripts/worktree-ports.conf"
  "tools/scripts/worktree-urls.conf"
  "tools/config/command-guard.conf"
  "tools/config/secret-paths.conf"
  "tools/config/secret-patterns.json"
  "docs/PM_PROJECT_CONFIG.md"
)

is_user_config() {
  local rel="$1"
  for ucf in "${USER_CONFIG_FILES[@]}"; do
    if [[ "$rel" == "$ucf" ]]; then
      return 0
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Helper: prompt with default
# ---------------------------------------------------------------------------
prompt_with_default() {
  local prompt="$1"
  local default="$2"
  local result

  if [[ -n "$default" ]]; then
    read -r -p "$(printf "${CYAN}%s${RESET} [${BOLD}%s${RESET}]: " "$prompt" "$default")" result
    result="${result:-$default}"
  else
    read -r -p "$(printf "${CYAN}%s${RESET}: " "$prompt")" result
    while [[ -z "$result" ]]; do
      log_warn "This field is required."
      read -r -p "$(printf "${CYAN}%s${RESET}: " "$prompt")" result
    done
  fi
  echo "$result"
}

# ---------------------------------------------------------------------------
# Detect owner/repo from target git remote
# ---------------------------------------------------------------------------
detect_git_remote_owner() {
  local url
  url=$(git -C "$TARGET" remote get-url origin 2>/dev/null) || true
  if [[ -z "$url" ]]; then echo ""; return; fi
  echo "$url" | sed -E 's#(git@github\.com:|https://github\.com/)##' | sed 's/\.git$//' | cut -d'/' -f1
}

detect_git_remote_repo() {
  local url
  url=$(git -C "$TARGET" remote get-url origin 2>/dev/null) || true
  if [[ -z "$url" ]]; then echo ""; return; fi
  echo "$url" | sed -E 's#(git@github\.com:|https://github\.com/)##' | sed 's/\.git$//' | cut -d'/' -f2
}

# ---------------------------------------------------------------------------
# UPDATE MODE: Read config from existing metadata
# ---------------------------------------------------------------------------
if $UPDATE_MODE; then
  log_section "Update mode — reading existing configuration"

  if [[ ! -f "$METADATA_FILE" ]]; then
    log_error "No .claude-pm-toolkit.json found in target."
    log_error "Run a fresh install first: ./install.sh $TARGET"
    exit 1
  fi

  # Read all values from metadata
  OWNER=$(jq -r '.owner' "$METADATA_FILE")
  REPO=$(jq -r '.repo' "$METADATA_FILE")
  PREFIX_LOWER=$(jq -r '.prefix_lower' "$METADATA_FILE")
  PREFIX_UPPER=$(jq -r '.prefix_upper' "$METADATA_FILE")
  DISPLAY_NAME=$(jq -r '.display_name' "$METADATA_FILE")
  TEST_COMMAND=$(jq -r '.test_command' "$METADATA_FILE")
  SETUP_COMMAND=$(jq -r '.setup_command' "$METADATA_FILE")
  DEV_COMMAND=$(jq -r '.dev_command' "$METADATA_FILE")

  log_ok "Loaded config: $OWNER/$REPO"
  log_info "Prefix: $PREFIX_LOWER / $PREFIX_UPPER"
  log_info "Display: $DISPLAY_NAME"
fi

# ---------------------------------------------------------------------------
# FRESH INSTALL: Gather inputs interactively
# ---------------------------------------------------------------------------
if ! $UPDATE_MODE; then
  log_section "Project configuration"

  DETECTED_OWNER=$(detect_git_remote_owner)
  DETECTED_REPO=$(detect_git_remote_repo)

  OWNER=$(prompt_with_default "GitHub owner (org or user)" "$DETECTED_OWNER")
  REPO=$(prompt_with_default "GitHub repo name" "$DETECTED_REPO")

  PREFIX_LOWER=$(prompt_with_default "Short prefix, lowercase (e.g. hov, myapp)" "")
  # Validate prefix: must be 2-10 lowercase alphanumeric chars
  if [[ ! "$PREFIX_LOWER" =~ ^[a-z][a-z0-9]{1,9}$ ]]; then
    log_error "Prefix must be 2-10 lowercase alphanumeric characters starting with a letter"
    exit 1
  fi
  PREFIX_UPPER=$(echo "$PREFIX_LOWER" | tr '[:lower:]' '[:upper:]')
  DISPLAY_NAME=$(prompt_with_default "Display name (e.g. My Project)" "$OWNER")
  TEST_COMMAND=$(prompt_with_default "Test command (run before PR/review)" "make test")
  SETUP_COMMAND=$(prompt_with_default "Setup command (bootstrap environment)" "make setup")
  DEV_COMMAND=$(prompt_with_default "Dev command (start dev server)" "make dev")

  printf "\n"
  log_info "Owner:          $OWNER"
  log_info "Repo:           $REPO"
  log_info "Prefix:         $PREFIX_LOWER / $PREFIX_UPPER"
  log_info "Display name:   $DISPLAY_NAME"
  log_info "Test command:   $TEST_COMMAND"
  log_info "Setup command:  $SETUP_COMMAND"
  log_info "Dev command:    $DEV_COMMAND"
  printf "\n"
  read -r -p "$(printf "${YELLOW}Continue?${RESET} [Y/n] ")" CONFIRM
  CONFIRM="${CONFIRM:-Y}"
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log_warn "Aborted."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# Replacement map (stride-3: placeholder, value, fallback)
# ---------------------------------------------------------------------------
declare -a REPLACE_PAIRS
REPLACE_PAIRS=(
  "{{OWNER}}"               "$OWNER"               ""
  "{{REPO}}"                "$REPO"                ""
  "{{DISPLAY_NAME}}"        "$DISPLAY_NAME"        ""
  "{{PREFIX}}"              "$PREFIX_UPPER"        ""
  "{{prefix}}"              "$PREFIX_LOWER"        ""
  "{{TEST_COMMAND}}"        "$TEST_COMMAND"        ""
  "{{SETUP_COMMAND}}"       "$SETUP_COMMAND"       ""
  "{{DEV_COMMAND}}"         "$DEV_COMMAND"         ""
)

# ---------------------------------------------------------------------------
# Apply replacements using awk with fixed-string matching
# ---------------------------------------------------------------------------
apply_replacements_to_content() {
  local src="$1"
  local dst="$2"
  cp "$src" "$dst"

  local i=0
  while [[ $i -lt ${#REPLACE_PAIRS[@]} ]]; do
    local placeholder="${REPLACE_PAIRS[$i]}"
    local value="${REPLACE_PAIRS[$((i+1))]}"
    local fallback="${REPLACE_PAIRS[$((i+2))]}"
    i=$((i+3))

    # Use value if set, else fallback, else leave placeholder
    local effective="$value"
    if [[ -z "$effective" && -n "$fallback" ]]; then
      effective="$fallback"
    fi

    if [[ -n "$effective" ]]; then
      awk -v ph="$placeholder" -v val="$effective" '
        {
          while (idx = index($0, ph)) {
            $0 = substr($0, 1, idx-1) val substr($0, idx+length(ph))
          }
          print
        }
      ' "$dst" > "${dst}.tmp" && mv "${dst}.tmp" "$dst"
    fi
  done
}

# ---------------------------------------------------------------------------
# Special handler: merge .claude/settings.json hooks
# ---------------------------------------------------------------------------
merge_settings_json() {
  local src_file="$1"
  local dst_file="$2"

  log_info "Merging hooks from template into existing .claude/settings.json ..."

  local tmp_src
  tmp_src=$(mktemp)
  TEMP_FILES+=("$tmp_src")
  apply_replacements_to_content "$src_file" "$tmp_src"

  local merged
  merged=$(jq -s '
    def merge_hook_matchers(existing_list; incoming_list):
      existing_list + (incoming_list | map(
        . as $inc |
        if (existing_list | any(.matcher == $inc.matcher)) then
          empty
        else
          $inc
        end
      ));

    .[0] as $dst | .[1] as $src |
    $dst |
    .hooks.PreToolUse   = (merge_hook_matchers(($dst.hooks.PreToolUse   // []);  ($src.hooks.PreToolUse   // []))) |
    .hooks.PostToolUse  = (merge_hook_matchers(($dst.hooks.PostToolUse  // []);  ($src.hooks.PostToolUse  // []))) |
    .hooks.Notification = (merge_hook_matchers(($dst.hooks.Notification // []);  ($src.hooks.Notification // []))) |
    .hooks.Stop         = (merge_hook_matchers(($dst.hooks.Stop         // []);  ($src.hooks.Stop         // [])))
  ' "$dst_file" "$tmp_src")

  echo "$merged" > "$dst_file"
  log_ok "Merged .claude/settings.json"
}

# ---------------------------------------------------------------------------
# Special handler: append/create CLAUDE.md sections
# ---------------------------------------------------------------------------
SENTINEL_START="<!-- claude-pm-toolkit:start -->"
SENTINEL_END="<!-- claude-pm-toolkit:end -->"
SECTIONS_FILE="$TOOLKIT_DIR/claude-md-sections.md"

merge_claude_md() {
  local target_claude_md="$TARGET/CLAUDE.md"

  if [[ ! -f "$SECTIONS_FILE" ]]; then
    log_warn "claude-md-sections.md not found in toolkit — skipping CLAUDE.md merge"
    return
  fi

  local tmp_sections
  tmp_sections=$(mktemp)
  TEMP_FILES+=("$tmp_sections")
  apply_replacements_to_content "$SECTIONS_FILE" "$tmp_sections"

  if [[ ! -f "$target_claude_md" ]]; then
    log_info "Creating CLAUDE.md in target repo from claude-md-sections.md ..."
    {
      echo "# CLAUDE.md"
      echo ""
      echo "This file provides guidance to Claude Code when working with this project."
      echo ""
      echo "---"
      echo ""
      echo "$SENTINEL_START"
      cat "$tmp_sections"
      echo ""
      echo "$SENTINEL_END"
    } > "$target_claude_md"
    log_ok "Created CLAUDE.md"
    return
  fi

  # Check if sentinels already present (idempotent: replace block)
  if grep -qF "$SENTINEL_START" "$target_claude_md"; then
    log_info "Updating existing claude-pm-toolkit section in CLAUDE.md ..."
    local tmp_md
    tmp_md=$(mktemp)
    TEMP_FILES+=("$tmp_md")
    awk -v start="$SENTINEL_START" -v end="$SENTINEL_END" \
        -v replacement_file="$tmp_sections" \
        'BEGIN { printing=1 }
         $0 == start { printing=0; print; while ((getline line < replacement_file) > 0) print line; close(replacement_file); next }
         $0 == end   { printing=1 }
         printing    { print }
        ' "$target_claude_md" > "$tmp_md"
    mv "$tmp_md" "$target_claude_md"
    log_ok "Updated claude-pm-toolkit section in CLAUDE.md"
    return
  fi

  # Append new sentinel block at end of existing CLAUDE.md
  log_info "Appending claude-pm-toolkit section to existing CLAUDE.md ..."
  {
    echo ""
    echo "---"
    echo ""
    echo "$SENTINEL_START"
    cat "$tmp_sections"
    echo ""
    echo "$SENTINEL_END"
  } >> "$target_claude_md"
  log_ok "Appended to CLAUDE.md"
}

# ---------------------------------------------------------------------------
# Copy files to target
# ---------------------------------------------------------------------------
log_section "Copying files to target"

COUNT_COPIED=0
COUNT_SKIPPED=0
COUNT_MERGED=0
COUNT_UPDATED=0
COUNT_CREATED_DIRS=0

# Files to skip from the toolkit root (not part of the install payload)
SKIP_FILES=("setup.sh" "install.sh" "validate.sh" "uninstall.sh" "claude-md-sections.md" ".gitignore" "README.md" "LICENSE")
SKIP_FILES+=("CLAUDE.md" "CONTRIBUTING.md" "CHANGELOG.md" "VERSION" "Makefile")
SKIP_FILES+=("CLAUDE_SESSION_CONTEXT.md")

while IFS= read -r src_file; do
  # Get path relative to toolkit
  rel="${src_file#$TOOLKIT_DIR/}"

  # Skip setup/install scripts and other toolkit-meta files
  local_basename="$(basename "$src_file")"
  skip=false
  for skip_name in "${SKIP_FILES[@]}"; do
    if [[ "$local_basename" == "$skip_name" ]]; then
      skip=true
      break
    fi
  done
  $skip && continue

  # Skip .git internals and .github (toolkit CI, not installable)
  if [[ "$rel" == .git/* || "$rel" == ".git" || "$rel" == .github/* ]]; then
    continue
  fi

  dst_file="$TARGET/$rel"
  dst_dir="$(dirname "$dst_file")"

  # Special case: .claude/settings.json — always merge
  if [[ "$rel" == ".claude/settings.json" ]]; then
    mkdir -p "$dst_dir"
    if [[ -f "$dst_file" ]]; then
      merge_settings_json "$src_file" "$dst_file"
      COUNT_MERGED=$((COUNT_MERGED+1))
    else
      tmp_dst=$(mktemp)
      TEMP_FILES+=("$tmp_dst")
      apply_replacements_to_content "$src_file" "$tmp_dst"
      cp "$tmp_dst" "$dst_file"
      log_ok "Created: $rel"
      COUNT_COPIED=$((COUNT_COPIED+1))
    fi
    continue
  fi

  # In update mode: overwrite toolkit-managed files, skip user configs
  if $UPDATE_MODE; then
    if is_user_config "$rel"; then
      if [[ -f "$dst_file" ]]; then
        log_skip "Preserved (user config): $rel"
        COUNT_SKIPPED=$((COUNT_SKIPPED+1))
        continue
      fi
      # User config doesn't exist yet — copy the default
    fi

    # Overwrite with latest version
    if [[ ! -d "$dst_dir" ]]; then
      mkdir -p "$dst_dir"
      COUNT_CREATED_DIRS=$((COUNT_CREATED_DIRS+1))
    fi
    is_new=false
    [[ ! -f "$dst_file" ]] && is_new=true
    tmp_dst=$(mktemp)
    TEMP_FILES+=("$tmp_dst")
    apply_replacements_to_content "$src_file" "$tmp_dst"
    cp "$tmp_dst" "$dst_file"
    if $is_new; then
      log_ok "Created: $rel"
      COUNT_COPIED=$((COUNT_COPIED+1))
    else
      log_ok "Updated: $rel"
      COUNT_UPDATED=$((COUNT_UPDATED+1))
    fi
    continue
  fi

  # Fresh install: skip if exists
  if [[ -f "$dst_file" ]]; then
    log_skip "Exists (skipping): $rel"
    COUNT_SKIPPED=$((COUNT_SKIPPED+1))
    continue
  fi

  # Create destination directory if needed
  if [[ ! -d "$dst_dir" ]]; then
    mkdir -p "$dst_dir"
    COUNT_CREATED_DIRS=$((COUNT_CREATED_DIRS+1))
  fi

  # Apply replacements and copy
  tmp_dst=$(mktemp)
  TEMP_FILES+=("$tmp_dst")
  apply_replacements_to_content "$src_file" "$tmp_dst"
  cp "$tmp_dst" "$dst_file"
  log_ok "Copied: $rel"
  COUNT_COPIED=$((COUNT_COPIED+1))

done < <(find "$TOOLKIT_DIR" \
  -not -path "*/.git/*" \
  -not -path "*/.git" \
  -not -path "*/node_modules/*" \
  -not -path "*/build/*" \
  -type f | sort)

# ---------------------------------------------------------------------------
# Special handling: CLAUDE.md
# ---------------------------------------------------------------------------
log_section "Handling CLAUDE.md"
merge_claude_md

# ---------------------------------------------------------------------------
# Fix .gitignore
# ---------------------------------------------------------------------------
GITIGNORE_FILE="$TARGET/.gitignore"

# Create .gitignore if it doesn't exist
if [[ ! -f "$GITIGNORE_FILE" ]]; then
  log_section "Creating .gitignore"
  cat > "$GITIGNORE_FILE" <<'GITIGNORE'
# Claude Code
.claude/settings.local.json
.claude/plans/
.codex-work/

# PM Intelligence
.pm/
GITIGNORE
  log_ok "Created .gitignore with Claude Code entries"
fi

if [[ -f "$GITIGNORE_FILE" ]] && grep -qx '\.claude' "$GITIGNORE_FILE"; then
  log_section "Updating .gitignore"
  log_info ".claude directory is fully gitignored — switching to selective ignoring"
  awk '
    /^\.claude$/ {
      print ".claude/settings.local.json"
      print ".claude/plans/"
      next
    }
    { print }
  ' "$GITIGNORE_FILE" > "${GITIGNORE_FILE}.tmp" && mv "${GITIGNORE_FILE}.tmp" "$GITIGNORE_FILE"
  log_ok "Updated .gitignore: .claude/settings.json and .claude/skills/ now trackable"
fi

# Ensure essential ignore entries exist
if [[ -f "$GITIGNORE_FILE" ]]; then
  for entry in '.claude/settings.local.json' '.claude/plans/' '.codex-work/' '.pm/'; do
    if ! grep -qF "$entry" "$GITIGNORE_FILE"; then
      echo "$entry" >> "$GITIGNORE_FILE"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Clean up any remaining old placeholders
# ---------------------------------------------------------------------------
while IFS= read -r file_with_opt; do
  awk '{
    while (match($0, /\{\{OPT_[A-Z_]+\}\}/)) {
      $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH)
    }
    while (match($0, /\{\{FIELD_[A-Z_]+\}\}/)) {
      $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH)
    }
    while (match($0, /\{\{PROJECT_ID\}\}/)) {
      $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH)
    }
    while (match($0, /\{\{PROJECT_NUMBER\}\}/)) {
      $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH)
    }
    print
  }' "$file_with_opt" > "${file_with_opt}.tmp" && mv "${file_with_opt}.tmp" "$file_with_opt"
done < <(grep -rl '{{OPT_\|{{FIELD_\|{{PROJECT_' "$TARGET/tools" "$TARGET/.claude" \
    --include='*.sh' --include='*.json' --include='*.md' 2>/dev/null || true)

# ---------------------------------------------------------------------------
# Make shell scripts executable in target
# ---------------------------------------------------------------------------
log_section "Making shell scripts executable in target"

while IFS= read -r shfile; do
  chmod +x "$shfile"
  log_ok "chmod +x: ${shfile#$TARGET/}"
done < <(find "$TARGET" \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  \( -name "*.sh" \) \
  -type f | sort)

# ---------------------------------------------------------------------------
# Save metadata
# ---------------------------------------------------------------------------
log_section "Saving configuration metadata"

TOOLKIT_VERSION=$(cd "$TOOLKIT_DIR" && git log --oneline -1 --format='%h' 2>/dev/null || echo "unknown")
ORIGINAL_INSTALLED_AT=""
PREVIOUS_VERSION=""

# Preserve original install timestamp on updates
if $UPDATE_MODE && [[ -f "$METADATA_FILE" ]]; then
  ORIGINAL_INSTALLED_AT=$(jq -r '.installed_at // empty' "$METADATA_FILE")
  PREVIOUS_VERSION=$(jq -r '.toolkit_version // empty' "$METADATA_FILE")
fi
ORIGINAL_INSTALLED_AT="${ORIGINAL_INSTALLED_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)

jq -n \
  --arg toolkit_version "$TOOLKIT_VERSION" \
  --arg installed_at "$ORIGINAL_INSTALLED_AT" \
  --arg updated_at "$NOW" \
  --arg owner "$OWNER" \
  --arg repo "$REPO" \
  --arg prefix_lower "$PREFIX_LOWER" \
  --arg prefix_upper "$PREFIX_UPPER" \
  --arg display_name "$DISPLAY_NAME" \
  --arg test_command "$TEST_COMMAND" \
  --arg setup_command "$SETUP_COMMAND" \
  --arg dev_command "$DEV_COMMAND" \
  '{
    toolkit_version: $toolkit_version,
    installed_at: $installed_at,
    updated_at: $updated_at,
    owner: $owner,
    repo: $repo,
    prefix_lower: $prefix_lower,
    prefix_upper: $prefix_upper,
    display_name: $display_name,
    test_command: $test_command,
    setup_command: $setup_command,
    dev_command: $dev_command,
    autonomous_mode: false
  }' > "$METADATA_FILE"

log_ok "Saved .claude-pm-toolkit.json"

# ---------------------------------------------------------------------------
# Makefile integration (optional)
# ---------------------------------------------------------------------------
MAKEFILE_SENTINEL_START="# claude-pm-toolkit:start"
MAKEFILE_SENTINEL_END="# claude-pm-toolkit:end"
TARGET_MAKEFILE="$TARGET/Makefile"
MAKEFILE_TARGETS="$TOOLKIT_DIR/tools/scripts/makefile-targets.mk"

if [[ -f "$TARGET_MAKEFILE" ]] && [[ -f "$MAKEFILE_TARGETS" ]]; then
  if grep -qF "$MAKEFILE_SENTINEL_START" "$TARGET_MAKEFILE"; then
    tmp_mk=$(mktemp)
    TEMP_FILES+=("$tmp_mk")
    awk -v start="$MAKEFILE_SENTINEL_START" -v end="$MAKEFILE_SENTINEL_END" \
        'BEGIN { skip=0 }
         $0 == start { skip=1; next }
         $0 == end   { skip=0; next }
         !skip       { print }
        ' "$TARGET_MAKEFILE" > "$tmp_mk"
    {
      echo ""
      echo "$MAKEFILE_SENTINEL_START"
      cat "$MAKEFILE_TARGETS"
      echo "$MAKEFILE_SENTINEL_END"
    } >> "$tmp_mk"
    mv "$tmp_mk" "$TARGET_MAKEFILE"
    log_ok "Updated Makefile targets"
  elif ! $UPDATE_MODE; then
    {
      echo ""
      echo "$MAKEFILE_SENTINEL_START"
      cat "$MAKEFILE_TARGETS"
      echo "$MAKEFILE_SENTINEL_END"
    } >> "$TARGET_MAKEFILE"
    log_ok "Added Makefile targets"
  fi
fi

# ---------------------------------------------------------------------------
# MCP Server (pm-intelligence)
# ---------------------------------------------------------------------------
MCP_DST="$TARGET/tools/mcp/pm-intelligence"

if [[ -d "$MCP_DST/src" ]] && [[ -f "$MCP_DST/package.json" ]]; then
  log_section "Building MCP Server (pm-intelligence)"

  log_info "Installing dependencies..."
  (cd "$MCP_DST" && npm install --loglevel=warn 2>&1) || {
    log_warn "npm install failed — MCP server won't be available"
    log_warn "Run manually: cd $MCP_DST && npm install && npm run build"
  }

  log_info "Compiling TypeScript..."
  if (cd "$MCP_DST" && npm run build 2>&1); then
    log_ok "MCP server built successfully"
  else
    log_warn "TypeScript compilation failed — MCP server won't be available"
    log_warn "Run manually: cd $MCP_DST && npm run build"
  fi

  # Merge pm-intelligence into .mcp.json
  MCP_JSON="$TARGET/.mcp.json"
  MCP_ENTRY='{"mcpServers":{"pm-intelligence":{"command":"node","args":["./tools/mcp/pm-intelligence/build/index.js"]}}}'

  if [[ -f "$MCP_JSON" ]]; then
    tmp_mcp=$(mktemp)
    TEMP_FILES+=("$tmp_mcp")
    if jq -s '.[0] * .[1]' "$MCP_JSON" <(echo "$MCP_ENTRY") > "$tmp_mcp" 2>/dev/null; then
      cp "$tmp_mcp" "$MCP_JSON"
      log_ok "Merged pm-intelligence into existing .mcp.json"
    else
      log_warn "Failed to merge .mcp.json — add pm-intelligence entry manually"
    fi
  else
    echo "$MCP_ENTRY" | jq '.' > "$MCP_JSON"
    log_ok "Created .mcp.json with pm-intelligence server"
  fi
fi

# ---------------------------------------------------------------------------
# Initial sync (fresh install only)
# ---------------------------------------------------------------------------
if ! $UPDATE_MODE; then
  PM_CLI="$MCP_DST/build/cli.js"
  if [[ -f "$PM_CLI" ]]; then
    log_section "Initial GitHub sync"
    log_info "Syncing issues and PRs into local SQLite database..."
    if (cd "$TARGET" && node "$PM_CLI" init 2>&1); then
      log_ok "Initial sync complete — local database ready at .pm/state.db"
    else
      log_warn "Initial sync failed. Run manually: cd $TARGET && pm init"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Install complete"

printf "${GREEN}%-20s${RESET} %s\n" "Target:"         "$TARGET"
printf "${GREEN}%-20s${RESET} %s\n" "Owner:"          "$OWNER"
printf "${GREEN}%-20s${RESET} %s\n" "Repo:"           "$REPO"
printf "${GREEN}%-20s${RESET} %s\n" "Prefix (lower):" "$PREFIX_LOWER"
printf "${GREEN}%-20s${RESET} %s\n" "Prefix (upper):" "$PREFIX_UPPER"
printf "${GREEN}%-20s${RESET} %s\n" "Display name:"   "$DISPLAY_NAME"
printf "${GREEN}%-20s${RESET} %s\n" "Test command:"   "$TEST_COMMAND"
printf "${GREEN}%-20s${RESET} %s\n" "Setup command:"  "$SETUP_COMMAND"
printf "${GREEN}%-20s${RESET} %s\n" "Dev command:"    "$DEV_COMMAND"
printf "\n"
printf "${GREEN}%-20s${RESET} %d\n" "Files copied:"   "$COUNT_COPIED"
if $UPDATE_MODE; then
  printf "${GREEN}%-20s${RESET} %d\n" "Files updated:" "$COUNT_UPDATED"
fi
printf "${GREEN}%-20s${RESET} %d\n" "Files merged:"   "$COUNT_MERGED"
printf "${YELLOW}%-20s${RESET} %d\n" "Files skipped:" "$COUNT_SKIPPED"

if $UPDATE_MODE; then
  printf "\n${GREEN}Update complete.${RESET} Toolkit files refreshed in:\n  $TARGET\n"
  if [[ -n "${PREVIOUS_VERSION:-}" ]] && [[ "$PREVIOUS_VERSION" != "$TOOLKIT_VERSION" ]]; then
    printf "\n${CYAN}%-20s${RESET} %s → %s\n" "Toolkit version:" "$PREVIOUS_VERSION" "$TOOLKIT_VERSION"
  fi
  printf "\n${BOLD}Preserved user config files:${RESET}\n"
  for ucf in "${USER_CONFIG_FILES[@]}"; do
    if [[ -f "$TARGET/$ucf" ]]; then
      printf "  ${GREEN}✓${RESET} %s\n" "$ucf"
    else
      printf "  ${YELLOW}–${RESET} %s (not present)\n" "$ucf"
    fi
  done
  printf "\nRun ./validate.sh $TARGET to verify the installation.\n\n"
else
  printf "\n${GREEN}Done.${RESET} The PM toolkit has been installed into:\n  $TARGET\n"
  printf "\n${BOLD}Architecture:${RESET} local-first SQLite\n"
  printf "  - Workflow state managed locally (.pm/state.db)\n"
  printf "  - Issues synced from GitHub on demand (pm sync)\n"
  printf "  - No GitHub Projects v2 dependency\n"
  printf "\n${BOLD}Next steps:${RESET}\n"
  printf "  1. Review and customize: docs/PM_PROJECT_CONFIG.md\n"
  printf "  2. Validate: ./validate.sh $TARGET\n"
  printf "  3. Commit the new files\n"
  printf "  4. Run ${BOLD}pm board${RESET} to see your kanban board\n\n"
fi

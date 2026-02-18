#!/usr/bin/env bash
set -euo pipefail

# install.sh - Install or update claude-pm-toolkit in an existing repository
#
# Modes:
#   Fresh install:  Prompts for config, discovers field IDs, copies files
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
    - Prompts for project configuration
    - Discovers GitHub Projects v2 field IDs via GraphQL
    - Copies template files with replacements applied
    - Creates .claude-pm-toolkit.json metadata file

  Update (--update):
    - Reads config from existing .claude-pm-toolkit.json
    - Overwrites toolkit-managed files (scripts, skills, docs)
    - Preserves user customizations (ports.conf, urls.conf, PM_PROJECT_CONFIG.md)
    - Refreshes CLAUDE.md sentinel block and settings.json hooks

  Copy rules (fresh install):
    - New files:              copied with replacements applied
    - Existing files:         skipped (not clobbered)
    - .claude/settings.json:  merged (hooks from template added)
    - CLAUDE.md:              content appended between sentinel comments

  Copy rules (update):
    - Toolkit-managed files:  overwritten with latest version
    - User config files:      preserved (never overwritten)
    - .claude/settings.json:  merged (new hooks added)
    - CLAUDE.md:              sentinel block replaced

PREREQUISITES
  - gh CLI (authenticated, with 'project' scope)
  - jq
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

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
  log_error "Missing required tools:"
  for dep in "${MISSING_DEPS[@]}"; do
    printf "  - %s\n" "$dep" >&2
  done
  exit 1
fi
log_ok "gh and jq found"

if ! gh auth status &>/dev/null; then
  log_error "gh CLI is not authenticated. Run: gh auth login"
  exit 1
fi
log_ok "gh authenticated"

if ! gh auth status 2>&1 | grep -q "'project'"; then
  log_warn "gh token may be missing 'project' scope."
  log_warn "If project board writes fail later, run:"
  log_warn "  gh auth refresh -s project --hostname github.com"
fi

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
  PROJECT_NUMBER=$(jq -r '.project_number' "$METADATA_FILE")
  PROJECT_ID=$(jq -r '.project_id' "$METADATA_FILE")
  PREFIX_LOWER=$(jq -r '.prefix_lower' "$METADATA_FILE")
  PREFIX_UPPER=$(jq -r '.prefix_upper' "$METADATA_FILE")
  DISPLAY_NAME=$(jq -r '.display_name' "$METADATA_FILE")
  TEST_COMMAND=$(jq -r '.test_command' "$METADATA_FILE")
  SETUP_COMMAND=$(jq -r '.setup_command' "$METADATA_FILE")
  DEV_COMMAND=$(jq -r '.dev_command' "$METADATA_FILE")

  log_ok "Loaded config: $OWNER/$REPO (project #$PROJECT_NUMBER)"
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
  PROJECT_NUMBER=$(prompt_with_default "GitHub Project number (Projects v2, or 'new' to create)" "")

  # If user entered "new", create a project board with all required fields
  if [[ "$PROJECT_NUMBER" == "new" ]]; then
    log_section "Creating GitHub Projects v2 board"
    PROJECT_TITLE=$(prompt_with_default "Project board title" "$REPO")
    log_info "Creating project '$PROJECT_TITLE'..."
    CREATE_RESULT=$(gh project create --owner "$OWNER" --title "$PROJECT_TITLE" --format json 2>&1) || {
      # Fallback for personal accounts (--owner @me)
      CREATE_RESULT=$(gh project create --owner @me --title "$PROJECT_TITLE" --format json 2>&1) || {
        log_error "Failed to create project: $CREATE_RESULT"
        exit 1
      }
    }
    PROJECT_NUMBER=$(echo "$CREATE_RESULT" | jq -r '.number')
    log_ok "Created project #$PROJECT_NUMBER"

    log_info "Adding Workflow field..."
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Workflow" --data-type "SINGLE_SELECT" \
      --single-select-options "Backlog,Ready,Active,Review,Rework,Done" 2>/dev/null || \
    gh project field-create "$PROJECT_NUMBER" --owner @me --name "Workflow" --data-type "SINGLE_SELECT" \
      --single-select-options "Backlog,Ready,Active,Review,Rework,Done" 2>/dev/null
    log_ok "  Workflow: Backlog, Ready, Active, Review, Rework, Done"

    log_info "Adding Priority field..."
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Priority" --data-type "SINGLE_SELECT" \
      --single-select-options "Critical,High,Normal" 2>/dev/null || \
    gh project field-create "$PROJECT_NUMBER" --owner @me --name "Priority" --data-type "SINGLE_SELECT" \
      --single-select-options "Critical,High,Normal" 2>/dev/null
    log_ok "  Priority: Critical, High, Normal"

    log_info "Adding Area field..."
    AREA_OPTS=$(prompt_with_default "Area options (comma-separated)" "Frontend,Backend,Infra,Docs")
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Area" --data-type "SINGLE_SELECT" \
      --single-select-options "$AREA_OPTS" 2>/dev/null || \
    gh project field-create "$PROJECT_NUMBER" --owner @me --name "Area" --data-type "SINGLE_SELECT" \
      --single-select-options "$AREA_OPTS" 2>/dev/null
    log_ok "  Area: $AREA_OPTS"

    log_info "Adding Issue Type field..."
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Issue Type" --data-type "SINGLE_SELECT" \
      --single-select-options "Bug,Feature,Spike,Epic,Chore" 2>/dev/null || \
    gh project field-create "$PROJECT_NUMBER" --owner @me --name "Issue Type" --data-type "SINGLE_SELECT" \
      --single-select-options "Bug,Feature,Spike,Epic,Chore" 2>/dev/null
    log_ok "  Issue Type: Bug, Feature, Spike, Epic, Chore"

    log_info "Adding Risk field..."
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Risk" --data-type "SINGLE_SELECT" \
      --single-select-options "Low,Medium,High" 2>/dev/null || \
    gh project field-create "$PROJECT_NUMBER" --owner @me --name "Risk" --data-type "SINGLE_SELECT" \
      --single-select-options "Low,Medium,High" 2>/dev/null
    log_ok "  Risk: Low, Medium, High"

    log_info "Adding Estimate field..."
    gh project field-create "$PROJECT_NUMBER" --owner "$OWNER" --name "Estimate" --data-type "SINGLE_SELECT" \
      --single-select-options "Small,Medium,Large" 2>/dev/null || \
    gh project field-create "$PROJECT_NUMBER" --owner @me --name "Estimate" --data-type "SINGLE_SELECT" \
      --single-select-options "Small,Medium,Large" 2>/dev/null
    log_ok "  Estimate: Small, Medium, Large"

    log_ok "Project board created with all fields!"
    printf "\n"
  fi

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
  log_info "Project number: $PROJECT_NUMBER"
  log_info "Prefix:         $PREFIX_LOWER / $PREFIX_UPPER"
  log_info "Display name:   $DISPLAY_NAME"
  log_info "Test command:   $TEST_COMMAND"
  log_info "Setup command:  $SETUP_COMMAND"
  log_info "Dev command:    $DEV_COMMAND"
  log_info "Target dir:     $TARGET"
  printf "\n"
  read -r -p "$(printf "${YELLOW}Continue?${RESET} [Y/n] ")" CONFIRM
  CONFIRM="${CONFIRM:-Y}"
  if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    log_warn "Aborted."
    exit 0
  fi
fi

# ---------------------------------------------------------------------------
# GraphQL: discover project fields (both modes — update refreshes IDs)
# ---------------------------------------------------------------------------
log_section "Discovering GitHub Project fields via GraphQL"

ORG_QUERY='
query($owner: String!, $num: Int!) {
  organization(login: $owner) {
    projectV2(number: $num) {
      id
      fields(first: 30) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
        }
      }
    }
  }
}
'

USER_QUERY='
query($owner: String!, $num: Int!) {
  user(login: $owner) {
    projectV2(number: $num) {
      id
      fields(first: 30) {
        nodes {
          ... on ProjectV2SingleSelectField {
            id
            name
            options { id name }
          }
        }
      }
    }
  }
}
'

GQL_RESULT=""
PROJECT_DATA=""

log_info "Trying organization query..."
if GQL_RESULT=$(gh api graphql \
    -f query="$ORG_QUERY" \
    -f owner="$OWNER" \
    -F num="$PROJECT_NUMBER" 2>&1); then
  PROJECT_DATA=$(echo "$GQL_RESULT" | jq -r '.data.organization.projectV2 // empty' 2>/dev/null) || true
fi

if [[ -z "$PROJECT_DATA" || "$PROJECT_DATA" == "null" ]]; then
  log_info "Organization query returned no data, trying user query..."
  if GQL_RESULT=$(gh api graphql \
      -f query="$USER_QUERY" \
      -f owner="$OWNER" \
      -F num="$PROJECT_NUMBER" 2>&1); then
    PROJECT_DATA=$(echo "$GQL_RESULT" | jq -r '.data.user.projectV2 // empty' 2>/dev/null) || true
  fi
fi

if [[ -z "$PROJECT_DATA" || "$PROJECT_DATA" == "null" ]]; then
  log_error "Could not find project #$PROJECT_NUMBER for '$OWNER'."
  log_error "Verify the project number and that '$OWNER' owns it."
  log_error "Raw GraphQL response:"
  echo "$GQL_RESULT" | head -30 >&2
  exit 1
fi

log_ok "Project found"
PROJECT_ID=$(echo "$PROJECT_DATA" | jq -r '.id')
log_info "Project ID: $PROJECT_ID"

# ---------------------------------------------------------------------------
# Field/option helpers
# ---------------------------------------------------------------------------
get_field_id() {
  local field_name="$1"
  echo "$PROJECT_DATA" | jq -r --arg name "$field_name" \
    '.fields.nodes[] | select(.name == $name) | .id // empty'
}

get_option_id() {
  local field_name="$1"
  local option_name="$2"
  echo "$PROJECT_DATA" | jq -r --arg fname "$field_name" --arg oname "$option_name" \
    '.fields.nodes[] | select(.name == $fname) | .options[] | select(.name == $oname) | .id // empty'
}

log_section "Mapping project fields"

FIELD_WORKFLOW=$(get_field_id "Workflow")
FIELD_PRIORITY=$(get_field_id "Priority")
FIELD_AREA=$(get_field_id "Area")
FIELD_ISSUE_TYPE=$(get_field_id "Issue Type")
FIELD_RISK=$(get_field_id "Risk")
FIELD_ESTIMATE=$(get_field_id "Estimate")

report_field() {
  local name="$1"
  local value="$2"
  if [[ -z "$value" ]]; then
    log_warn "Field '$name' not found in project — placeholder will be left with TODO comment"
  else
    log_ok "  $name: $value"
  fi
}

report_field "Workflow"   "$FIELD_WORKFLOW"
report_field "Priority"   "$FIELD_PRIORITY"
report_field "Area"       "$FIELD_AREA"
report_field "Issue Type" "$FIELD_ISSUE_TYPE"
report_field "Risk"       "$FIELD_RISK"
report_field "Estimate"   "$FIELD_ESTIMATE"

# Workflow field is required — everything else is optional
if [[ -z "$FIELD_WORKFLOW" ]]; then
  log_error "Workflow field not found in project #$PROJECT_NUMBER."
  log_error "This is required for the toolkit to function."
  log_error "Add a 'Workflow' single-select field to your project with options:"
  log_error "  Backlog, Ready, Active, Review, Rework, Done"
  exit 1
fi

# Workflow options
OPT_WF_BACKLOG=$(get_option_id "Workflow" "Backlog")
OPT_WF_READY=$(get_option_id  "Workflow" "Ready")
OPT_WF_ACTIVE=$(get_option_id "Workflow" "Active")
OPT_WF_REVIEW=$(get_option_id "Workflow" "Review")
OPT_WF_REWORK=$(get_option_id "Workflow" "Rework")
OPT_WF_DONE=$(get_option_id   "Workflow" "Done")

# Priority options
OPT_PRI_CRITICAL=$(get_option_id "Priority" "Critical")
OPT_PRI_HIGH=$(get_option_id     "Priority" "High")
OPT_PRI_NORMAL=$(get_option_id   "Priority" "Normal")

# Area options
OPT_AREA_FRONTEND=$(get_option_id  "Area" "Frontend")
OPT_AREA_BACKEND=$(get_option_id   "Area" "Backend")
OPT_AREA_CONTRACTS=$(get_option_id "Area" "Contracts")
OPT_AREA_INFRA=$(get_option_id     "Area" "Infra")
OPT_AREA_DESIGN=$(get_option_id    "Area" "Design")
OPT_AREA_DOCS=$(get_option_id      "Area" "Docs")
OPT_AREA_PM=$(get_option_id        "Area" "PM")

# Issue Type options
OPT_TYPE_BUG=$(get_option_id     "Issue Type" "Bug")
OPT_TYPE_FEATURE=$(get_option_id "Issue Type" "Feature")
OPT_TYPE_SPIKE=$(get_option_id   "Issue Type" "Spike")
OPT_TYPE_EPIC=$(get_option_id    "Issue Type" "Epic")
OPT_TYPE_CHORE=$(get_option_id   "Issue Type" "Chore")

# Risk options
OPT_RISK_LOW=$(get_option_id    "Risk" "Low")
OPT_RISK_MEDIUM=$(get_option_id "Risk" "Medium")
OPT_RISK_HIGH=$(get_option_id   "Risk" "High")

# Estimate options
OPT_EST_SMALL=$(get_option_id  "Estimate" "Small")
OPT_EST_MEDIUM=$(get_option_id "Estimate" "Medium")
OPT_EST_LARGE=$(get_option_id  "Estimate" "Large")

# ---------------------------------------------------------------------------
# Replacement map (stride-3: placeholder, value, fallback)
# ---------------------------------------------------------------------------
declare -a REPLACE_PAIRS
REPLACE_PAIRS=(
  "{{OWNER}}"               "$OWNER"               ""
  "{{REPO}}"                "$REPO"                ""
  "{{PROJECT_ID}}"          "$PROJECT_ID"          ""
  "{{PROJECT_NUMBER}}"      "$PROJECT_NUMBER"      ""
  "{{DISPLAY_NAME}}"        "$DISPLAY_NAME"        ""
  "{{PREFIX}}"              "$PREFIX_UPPER"        ""
  "{{prefix}}"              "$PREFIX_LOWER"        ""
  "{{TEST_COMMAND}}"        "$TEST_COMMAND"        ""
  "{{SETUP_COMMAND}}"       "$SETUP_COMMAND"       ""
  "{{DEV_COMMAND}}"         "$DEV_COMMAND"         ""
  "{{FIELD_WORKFLOW}}"      "$FIELD_WORKFLOW"      "TODO: add Workflow field to project"
  "{{FIELD_PRIORITY}}"      "$FIELD_PRIORITY"      "TODO: add Priority field to project"
  "{{FIELD_AREA}}"          "$FIELD_AREA"          "TODO: add Area field to project"
  "{{FIELD_ISSUE_TYPE}}"    "$FIELD_ISSUE_TYPE"    "TODO: add Issue Type field to project"
  "{{FIELD_RISK}}"          "$FIELD_RISK"          "TODO: add Risk field to project"
  "{{FIELD_ESTIMATE}}"      "$FIELD_ESTIMATE"      "TODO: add Estimate field to project"
  "{{OPT_WF_BACKLOG}}"      "$OPT_WF_BACKLOG"      "TODO: add Backlog option to Workflow field"
  "{{OPT_WF_READY}}"        "$OPT_WF_READY"        "TODO: add Ready option to Workflow field"
  "{{OPT_WF_ACTIVE}}"       "$OPT_WF_ACTIVE"       "TODO: add Active option to Workflow field"
  "{{OPT_WF_REVIEW}}"       "$OPT_WF_REVIEW"       "TODO: add Review option to Workflow field"
  "{{OPT_WF_REWORK}}"       "$OPT_WF_REWORK"       "TODO: add Rework option to Workflow field"
  "{{OPT_WF_DONE}}"         "$OPT_WF_DONE"         "TODO: add Done option to Workflow field"
  "{{OPT_PRI_CRITICAL}}"    "$OPT_PRI_CRITICAL"    "TODO: add Critical option to Priority field"
  "{{OPT_PRI_HIGH}}"        "$OPT_PRI_HIGH"        "TODO: add High option to Priority field"
  "{{OPT_PRI_NORMAL}}"      "$OPT_PRI_NORMAL"      "TODO: add Normal option to Priority field"
  "{{OPT_AREA_FRONTEND}}"   "$OPT_AREA_FRONTEND"   "TODO: add Frontend option to Area field"
  "{{OPT_AREA_BACKEND}}"    "$OPT_AREA_BACKEND"    "TODO: add Backend option to Area field"
  "{{OPT_AREA_CONTRACTS}}"  "$OPT_AREA_CONTRACTS"  "TODO: add Contracts option to Area field"
  "{{OPT_AREA_INFRA}}"      "$OPT_AREA_INFRA"      "TODO: add Infra option to Area field"
  "{{OPT_AREA_DESIGN}}"     "$OPT_AREA_DESIGN"     "TODO: add Design option to Area field"
  "{{OPT_AREA_DOCS}}"       "$OPT_AREA_DOCS"       "TODO: add Docs option to Area field"
  "{{OPT_AREA_PM}}"         "$OPT_AREA_PM"         "TODO: add PM option to Area field"
  "{{OPT_TYPE_BUG}}"        "$OPT_TYPE_BUG"        "TODO: add Bug option to Issue Type field"
  "{{OPT_TYPE_FEATURE}}"    "$OPT_TYPE_FEATURE"    "TODO: add Feature option to Issue Type field"
  "{{OPT_TYPE_SPIKE}}"      "$OPT_TYPE_SPIKE"      "TODO: add Spike option to Issue Type field"
  "{{OPT_TYPE_EPIC}}"       "$OPT_TYPE_EPIC"       "TODO: add Epic option to Issue Type field"
  "{{OPT_TYPE_CHORE}}"      "$OPT_TYPE_CHORE"      "TODO: add Chore option to Issue Type field"
  "{{OPT_RISK_LOW}}"        "$OPT_RISK_LOW"        "TODO: add Low option to Risk field"
  "{{OPT_RISK_MEDIUM}}"     "$OPT_RISK_MEDIUM"     "TODO: add Medium option to Risk field"
  "{{OPT_RISK_HIGH}}"       "$OPT_RISK_HIGH"       "TODO: add High option to Risk field"
  "{{OPT_EST_SMALL}}"       "$OPT_EST_SMALL"       "TODO: add Small option to Estimate field"
  "{{OPT_EST_MEDIUM}}"      "$OPT_EST_MEDIUM"      "TODO: add Medium option to Estimate field"
  "{{OPT_EST_LARGE}}"       "$OPT_EST_LARGE"       "TODO: add Large option to Estimate field"
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
      # Use awk with index() for fixed-string matching (no regex interpretation)
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

  rm -f "$tmp_src"
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
    rm -f "$tmp_sections"
    log_ok "Created CLAUDE.md"
    return
  fi

  # Check if sentinels already present (idempotent: replace block)
  if grep -qF "$SENTINEL_START" "$target_claude_md"; then
    log_info "Updating existing claude-pm-toolkit section in CLAUDE.md ..."
    local tmp_md
    tmp_md=$(mktemp)
    awk -v start="$SENTINEL_START" -v end="$SENTINEL_END" \
        -v replacement_file="$tmp_sections" \
        'BEGIN { printing=1 }
         $0 == start { printing=0; print; while ((getline line < replacement_file) > 0) print line; close(replacement_file); next }
         $0 == end   { printing=1 }
         printing    { print }
        ' "$target_claude_md" > "$tmp_md"
    mv "$tmp_md" "$target_claude_md"
    rm -f "$tmp_sections"
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
  rm -f "$tmp_sections"
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
SKIP_FILES=("setup.sh" "install.sh" "validate.sh" "claude-md-sections.md" ".gitignore" "README.md" "LICENSE")
SKIP_FILES+=("CLAUDE.md")

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

  # Skip .git internals
  if [[ "$rel" == .git/* || "$rel" == ".git" ]]; then
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
      apply_replacements_to_content "$src_file" "$tmp_dst"
      cp "$tmp_dst" "$dst_file"
      rm -f "$tmp_dst"
      log_ok "Created: $rel"
      COUNT_COPIED=$((COUNT_COPIED+1))
    fi
    continue
  fi

  # In update mode: overwrite toolkit-managed files, skip user configs
  if $UPDATE_MODE; then
    if is_user_config "$rel"; then
      log_skip "Preserved (user config): $rel"
      COUNT_SKIPPED=$((COUNT_SKIPPED+1))
      continue
    fi

    # Overwrite with latest version
    if [[ ! -d "$dst_dir" ]]; then
      mkdir -p "$dst_dir"
      COUNT_CREATED_DIRS=$((COUNT_CREATED_DIRS+1))
    fi
    tmp_dst=$(mktemp)
    apply_replacements_to_content "$src_file" "$tmp_dst"
    cp "$tmp_dst" "$dst_file"
    rm -f "$tmp_dst"
    if [[ -f "$dst_file" ]]; then
      log_ok "Updated: $rel"
      COUNT_UPDATED=$((COUNT_UPDATED+1))
    else
      log_ok "Created: $rel"
      COUNT_COPIED=$((COUNT_COPIED+1))
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
  apply_replacements_to_content "$src_file" "$tmp_dst"
  cp "$tmp_dst" "$dst_file"
  rm -f "$tmp_dst"
  log_ok "Copied: $rel"
  COUNT_COPIED=$((COUNT_COPIED+1))

done < <(find "$TOOLKIT_DIR" \
  -not -path "*/.git/*" \
  -not -path "*/.git" \
  -not -path "*/node_modules/*" \
  -type f | sort)

# ---------------------------------------------------------------------------
# Special handling: CLAUDE.md
# ---------------------------------------------------------------------------
log_section "Handling CLAUDE.md"
merge_claude_md

# ---------------------------------------------------------------------------
# Fix .gitignore if .claude is fully ignored
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

  if ! grep -qF '.codex-work/' "$GITIGNORE_FILE"; then
    echo '.codex-work/' >> "$GITIGNORE_FILE"
  fi

  log_ok "Updated .gitignore: .claude/settings.json and .claude/skills/ now trackable"
fi

# Ensure essential ignore entries exist (even if no .claude wildcard)
if [[ -f "$GITIGNORE_FILE" ]]; then
  for entry in '.claude/settings.local.json' '.claude/plans/' '.codex-work/'; do
    if ! grep -qF "$entry" "$GITIGNORE_FILE"; then
      echo "$entry" >> "$GITIGNORE_FILE"
    fi
  done
fi

# ---------------------------------------------------------------------------
# Clean up unresolved optional placeholders (area options not in project)
# ---------------------------------------------------------------------------
while IFS= read -r file_with_opt; do
  # Replace any remaining {{OPT_*}} placeholders with empty strings
  awk '{
    while (match($0, /\{\{OPT_[A-Z_]+\}\}/)) {
      $0 = substr($0, 1, RSTART-1) substr($0, RSTART+RLENGTH)
    }
    print
  }' "$file_with_opt" > "${file_with_opt}.tmp" && mv "${file_with_opt}.tmp" "$file_with_opt"
done < <(grep -rl '{{OPT_' "$TARGET" --include='*.sh' --include='*.json' --include='*.md' 2>/dev/null || true)

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
# Save metadata for future updates
# ---------------------------------------------------------------------------
log_section "Saving configuration metadata"

TOOLKIT_VERSION=$(cd "$TOOLKIT_DIR" && git log --oneline -1 --format='%h' 2>/dev/null || echo "unknown")

jq -n \
  --arg toolkit_version "$TOOLKIT_VERSION" \
  --arg installed_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg owner "$OWNER" \
  --arg repo "$REPO" \
  --arg project_number "$PROJECT_NUMBER" \
  --arg project_id "$PROJECT_ID" \
  --arg prefix_lower "$PREFIX_LOWER" \
  --arg prefix_upper "$PREFIX_UPPER" \
  --arg display_name "$DISPLAY_NAME" \
  --arg test_command "$TEST_COMMAND" \
  --arg setup_command "$SETUP_COMMAND" \
  --arg dev_command "$DEV_COMMAND" \
  '{
    toolkit_version: $toolkit_version,
    installed_at: $installed_at,
    owner: $owner,
    repo: $repo,
    project_number: $project_number,
    project_id: $project_id,
    prefix_lower: $prefix_lower,
    prefix_upper: $prefix_upper,
    display_name: $display_name,
    test_command: $test_command,
    setup_command: $setup_command,
    dev_command: $dev_command
  }' > "$METADATA_FILE"

log_ok "Saved .claude-pm-toolkit.json (used by --update mode)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Install complete"

printf "${GREEN}%-20s${RESET} %s\n" "Target:"         "$TARGET"
printf "${GREEN}%-20s${RESET} %s\n" "Owner:"          "$OWNER"
printf "${GREEN}%-20s${RESET} %s\n" "Repo:"           "$REPO"
printf "${GREEN}%-20s${RESET} %s\n" "Project ID:"     "$PROJECT_ID"
printf "${GREEN}%-20s${RESET} %s\n" "Project number:" "$PROJECT_NUMBER"
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

if grep -rqF '{{' "$TARGET/tools" "$TARGET/.claude" \
    --include="*.sh" \
    --include="*.md" \
    --include="*.json" \
    2>/dev/null; then
  printf "\n"
  log_warn "Some placeholders may still remain (fields/options not found in your project)."
  log_warn "Search for remaining placeholders in target:"
  log_warn "  grep -r '{{' $TARGET --include='*.sh' --include='*.md' --include='*.json'"
fi

if $UPDATE_MODE; then
  printf "\n${GREEN}Update complete.${RESET} Toolkit files refreshed in:\n  $TARGET\n"
  printf "\nUser config files were preserved:\n"
  for ucf in "${USER_CONFIG_FILES[@]}"; do
    printf "  - %s\n" "$ucf"
  done
  printf "\nRun ./validate.sh $TARGET to verify the installation.\n\n"
else
  printf "\n${GREEN}Done.${RESET} The PM toolkit has been installed into:\n  $TARGET\n"
  printf "\nNext steps:\n"
  printf "  1. Review and customize: docs/PM_PROJECT_CONFIG.md\n"
  printf "  2. Configure port services: tools/scripts/worktree-ports.conf\n"
  printf "  3. Validate: (cd $TOOLKIT_DIR && ./validate.sh $TARGET)\n"
  printf "  4. Commit the new files\n\n"
fi

#!/usr/bin/env bash
set -euo pipefail

# setup.sh - DEPRECATED: use install.sh instead
#
# This script is preserved for backward compatibility with existing
# documentation and template repos. New users should use install.sh:
#
#   ./install.sh /path/to/your/repo            # Install into existing repo
#   ./install.sh --update /path/to/your/repo   # Update existing installation
#
# For template mode (this repo IS your project), use:
#   ./install.sh .
#
# setup.sh still works for in-place template configuration but will be
# removed in a future version.

echo ""
echo "WARNING: setup.sh is deprecated and will be removed in a future version."
echo ""
echo "Use install.sh instead:"
echo "  ./install.sh /path/to/repo        # Install into existing repo"
echo "  ./install.sh --update /path/to/repo  # Update existing installation"
echo "  ./install.sh .                     # Template mode (this repo)"
echo ""
echo "Continuing with setup.sh in 3 seconds... (Ctrl-C to cancel)"
sleep 3

# Original setup.sh follows:
# setup.sh - Configure this repository by replacing template placeholders
#
# Run this script after cloning or using the template.
# It prompts for project details, auto-discovers GitHub Project field IDs via
# GraphQL, and replaces all {{PLACEHOLDER}} tokens across the codebase.
#
# This script is idempotent: safe to re-run to update values.
#
# Usage:
#   ./setup.sh           # Interactive mode
#   ./setup.sh --help    # Show this help

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
# Help
# ---------------------------------------------------------------------------
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
setup.sh - Configure the claude-pm-toolkit template

USAGE
  ./setup.sh            Interactive setup
  ./setup.sh --help     Show this help

DESCRIPTION
  Prompts for GitHub owner, repo name, project number, short prefix, and
  display name. Then auto-discovers all GitHub Projects v2 field and option
  IDs via GraphQL, and replaces every {{PLACEHOLDER}} token in all files.

PREREQUISITES
  - gh CLI (authenticated, with 'project' scope)
  - jq

IDEMPOTENT
  Safe to re-run. Existing values are used as defaults for the prompts.
EOF
  exit 0
fi

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
  log_warn "If project board writes fail, run:"
  log_warn "  gh auth refresh -s project --hostname github.com"
fi

# ---------------------------------------------------------------------------
# Detect script location (repo root)
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

# ---------------------------------------------------------------------------
# Helper: read existing placeholder value from pm.config.sh (if present)
# ---------------------------------------------------------------------------
CONFIG_FILE="$REPO_ROOT/tools/scripts/pm.config.sh"

# Try to detect owner/repo from git remote
detect_git_remote_owner() {
  local url
  url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || true
  if [[ -z "$url" ]]; then echo ""; return; fi
  echo "$url" | sed -E 's#(git@github\.com:|https://github\.com/)##' | sed 's/\.git$//' | cut -d'/' -f1
}

detect_git_remote_repo() {
  local url
  url=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null) || true
  if [[ -z "$url" ]]; then echo ""; return; fi
  echo "$url" | sed -E 's#(git@github\.com:|https://github\.com/)##' | sed 's/\.git$//' | cut -d'/' -f2
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
# Gather inputs
# ---------------------------------------------------------------------------
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
    log_warn "Project create failed for owner '$OWNER', trying personal account (@me)..."
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
  read -r -p "$(printf "${CYAN}Area options (comma-separated)${RESET} [${BOLD}Frontend,Backend,Infra,Docs${RESET}]: ")" AREA_OPTS
  AREA_OPTS="${AREA_OPTS:-Frontend,Backend,Infra,Docs}"
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
printf "\n"
read -r -p "$(printf "${YELLOW}Continue?${RESET} [Y/n] ")" CONFIRM
CONFIRM="${CONFIRM:-Y}"
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
  log_warn "Aborted."
  exit 0
fi

# ---------------------------------------------------------------------------
# GraphQL: discover project fields
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
  # Check if the org path actually returned data (not null)
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
# Helper: extract option ID by field name + option name (case-insensitive)
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

# ---------------------------------------------------------------------------
# Map fields
# ---------------------------------------------------------------------------
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
# Build sed replacement map
# ---------------------------------------------------------------------------
# Each entry: "placeholder" "value" "fallback_todo_comment"
declare -a SED_PAIRS
SED_PAIRS=(
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
# Apply replacements to a single file
# ---------------------------------------------------------------------------
apply_replacements_to_file() {
  local file="$1"

  # Build sed expression from SED_PAIRS
  # SED_PAIRS is: placeholder value fallback (stride 3)
  local tmp
  tmp=$(mktemp)
  cp "$file" "$tmp"

  local i=0
  while [[ $i -lt ${#SED_PAIRS[@]} ]]; do
    local placeholder="${SED_PAIRS[$i]}"
    local value="${SED_PAIRS[$((i+1))]}"
    local fallback="${SED_PAIRS[$((i+2))]}"
    i=$((i+3))

    if [[ -n "$value" ]]; then
      # Use awk for reliable cross-platform replacement (no regex escaping issues)
      # Use awk with index() for fixed-string matching (no regex interpretation)
      awk -v ph="$placeholder" -v val="$value" '
        {
          while (idx = index($0, ph)) {
            $0 = substr($0, 1, idx-1) val substr($0, idx+length(ph))
          }
          print
        }
      ' "$tmp" > "${tmp}.awk" && mv "${tmp}.awk" "$tmp"
    fi
    # If value is empty, the placeholder remains — the summary will warn about it
  done

  cp "$tmp" "$file"
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# Walk all files (excluding .git, binaries, and this script itself)
# ---------------------------------------------------------------------------
log_section "Applying replacements"

SKIP_PATTERNS=(
  ".git"
  "*.png" "*.jpg" "*.jpeg" "*.gif" "*.ico" "*.svg"
  "*.woff" "*.woff2" "*.ttf" "*.eot"
  "*.zip" "*.tar" "*.gz" "*.bz2"
  "*.lock"
  "node_modules"
  "setup.sh"
  "install.sh"
)

# Build a find command that excludes the skip patterns
find_args=("$REPO_ROOT" -type f)

# Exclude directories
for pat in .git node_modules; do
  find_args+=(-not -path "*/$pat/*" -not -path "*/$pat")
done

# Exclude binary file extensions
for pat in "*.png" "*.jpg" "*.jpeg" "*.gif" "*.ico" "*.woff" "*.woff2" "*.ttf" "*.eot" "*.zip" "*.tar" "*.gz" "*.bz2"; do
  find_args+=(-not -name "$pat")
done

# Exclude lockfiles
find_args+=(-not -name "*.lock" -not -name "package-lock.json")

# Exclude setup.sh and install.sh themselves
find_args+=(-not -name "setup.sh" -not -name "install.sh")

CHANGED=0
SKIPPED_BINARY=0

while IFS= read -r file; do
  # Skip non-text files (check with file command if available)
  if command -v file &>/dev/null; then
    mime=$(file --mime-type -b "$file" 2>/dev/null) || mime="text/plain"
    case "$mime" in
      text/*|application/json|application/x-sh|application/x-shellscript|application/xml)
        : ;;  # text, proceed
      *)
        SKIPPED_BINARY=$((SKIPPED_BINARY+1))
        continue
        ;;
    esac
  fi

  # Check if file contains any placeholder
  if grep -qF '{{' "$file" 2>/dev/null; then
    apply_replacements_to_file "$file"
    log_ok "Updated: ${file#$REPO_ROOT/}"
    CHANGED=$((CHANGED+1))
  fi
done < <(find "${find_args[@]}" 2>/dev/null | sort)

log_info "Files updated: $CHANGED"
if [[ $SKIPPED_BINARY -gt 0 ]]; then
  log_info "Binary files skipped: $SKIPPED_BINARY"
fi

# ---------------------------------------------------------------------------
# Make all shell scripts executable
# ---------------------------------------------------------------------------
log_section "Making shell scripts executable"

while IFS= read -r shfile; do
  chmod +x "$shfile"
  log_ok "chmod +x: ${shfile#$REPO_ROOT/}"
done < <(find "$REPO_ROOT" \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  \( -name "*.sh" -o -name "setup.sh" -o -name "install.sh" \) \
  -type f | sort)

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
log_section "Setup complete"

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

MISSING_OPTS=()
for field_val in "$FIELD_WORKFLOW" "$FIELD_PRIORITY" "$FIELD_AREA" "$FIELD_ISSUE_TYPE" "$FIELD_RISK" "$FIELD_ESTIMATE"; do
  if [[ -z "$field_val" ]]; then
    MISSING_OPTS+=("$field_val")
  fi
done

if grep -rqF '{{' "$REPO_ROOT" \
    --include="*.sh" \
    --include="*.md" \
    --include="*.json" \
    --include="*.ts" \
    2>/dev/null; then
  printf "\n"
  log_warn "Some placeholders may still remain (fields/options not in your project)."
  log_warn "Search for remaining placeholders:"
  log_warn "  grep -r '{{' $REPO_ROOT --include='*.sh' --include='*.md' --include='*.json'"
fi

printf "\n${GREEN}Done.${RESET} Your project is configured.\n\n"

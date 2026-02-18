#!/bin/bash
# pm.config.sh - Centralized PM project configuration
# Source this file in other scripts: source "$(dirname "$0")/pm.config.sh"

# Organization (explicit - don't derive from repo remote)
PM_OWNER="{{OWNER}}"

# Project identifiers
PM_PROJECT_NUMBER="{{PROJECT_NUMBER}}"
PM_PROJECT_ID="{{PROJECT_ID}}"

# Field IDs
PM_FIELD_WORKFLOW="{{FIELD_WORKFLOW}}"
PM_FIELD_PRIORITY="{{FIELD_PRIORITY}}"
PM_FIELD_AREA="{{FIELD_AREA}}"
PM_FIELD_ISSUE_TYPE="{{FIELD_ISSUE_TYPE}}"
PM_FIELD_RISK="{{FIELD_RISK}}"
PM_FIELD_ESTIMATE="{{FIELD_ESTIMATE}}"

# Workflow option IDs
PM_WORKFLOW_BACKLOG="{{OPT_WF_BACKLOG}}"
PM_WORKFLOW_READY="{{OPT_WF_READY}}"
PM_WORKFLOW_ACTIVE="{{OPT_WF_ACTIVE}}"
PM_WORKFLOW_REVIEW="{{OPT_WF_REVIEW}}"
PM_WORKFLOW_REWORK="{{OPT_WF_REWORK}}"
PM_WORKFLOW_DONE="{{OPT_WF_DONE}}"

# Priority option IDs
PM_PRIORITY_CRITICAL="{{OPT_PRI_CRITICAL}}"
PM_PRIORITY_HIGH="{{OPT_PRI_HIGH}}"
PM_PRIORITY_NORMAL="{{OPT_PRI_NORMAL}}"

# Area option IDs
PM_AREA_FRONTEND="{{OPT_AREA_FRONTEND}}"
PM_AREA_BACKEND="{{OPT_AREA_BACKEND}}"
PM_AREA_CONTRACTS="{{OPT_AREA_CONTRACTS}}"
PM_AREA_INFRA="{{OPT_AREA_INFRA}}"
PM_AREA_DESIGN="{{OPT_AREA_DESIGN}}"
PM_AREA_DOCS="{{OPT_AREA_DOCS}}"
PM_AREA_PM="{{OPT_AREA_PM}}"

# Issue Type option IDs
PM_TYPE_BUG="{{OPT_TYPE_BUG}}"
PM_TYPE_FEATURE="{{OPT_TYPE_FEATURE}}"
PM_TYPE_SPIKE="{{OPT_TYPE_SPIKE}}"
PM_TYPE_EPIC="{{OPT_TYPE_EPIC}}"
PM_TYPE_CHORE="{{OPT_TYPE_CHORE}}"

# Risk option IDs
PM_RISK_LOW="{{OPT_RISK_LOW}}"
PM_RISK_MEDIUM="{{OPT_RISK_MEDIUM}}"
PM_RISK_HIGH="{{OPT_RISK_HIGH}}"

# Estimate option IDs
PM_ESTIMATE_S="{{OPT_EST_SMALL}}"
PM_ESTIMATE_M="{{OPT_EST_MEDIUM}}"
PM_ESTIMATE_L="{{OPT_EST_LARGE}}"

# Validate config before use
pm_validate_config() {
  local missing=()

  # Check required IDs
  [ -z "$PM_PROJECT_ID" ] && missing+=("PM_PROJECT_ID")
  [ -z "$PM_FIELD_WORKFLOW" ] && missing+=("PM_FIELD_WORKFLOW")
  [ -z "$PM_WORKFLOW_ACTIVE" ] && missing+=("PM_WORKFLOW_ACTIVE (re-run install.sh --update to discover field IDs)")

  # Check gh CLI auth
  if ! gh auth status &>/dev/null; then
    echo "Error: gh CLI not authenticated. Run: gh auth login" >&2
    return 1
  fi

  # Check for project scope (required for project mutations)
  if ! gh auth status 2>&1 | grep -q "'project'"; then
    echo "Error: gh CLI token missing 'project' scope (required for project board writes)" >&2
    echo "Run: gh auth refresh -s project --hostname github.com" >&2
    return 1
  fi

  # Check jq installed
  if ! command -v jq &>/dev/null; then
    echo "Error: jq not installed." >&2
    echo "  macOS:  brew install jq" >&2
    echo "  Ubuntu: sudo apt-get install jq" >&2
    echo "  Fedora: sudo dnf install jq" >&2
    return 1
  fi

  if [ ${#missing[@]} -gt 0 ]; then
    echo "Error: Missing config in pm.config.sh:" >&2
    printf '  - %s\n' "${missing[@]}" >&2
    return 1
  fi

  # Check for unreplaced template placeholders
  local config_file
  config_file="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pm.config.sh"
  if grep -qE '^\w+=".*\{\{' "$config_file" 2>/dev/null; then
    echo "Error: pm.config.sh contains unreplaced {{placeholders}}" >&2
    echo "Run: install.sh --update /path/to/repo  (to re-discover field IDs)" >&2
    return 1
  fi
}

# Helper: get repo name from git remote
pm_get_repo() {
  if ! git rev-parse --git-dir &>/dev/null; then
    echo "Error: Not inside a git repository" >&2
    return 1
  fi
  local url
  url=$(git remote get-url origin 2>/dev/null)
  if [ -z "$url" ]; then
    echo "Error: No 'origin' remote configured" >&2
    echo "Run: git remote add origin <url>" >&2
    return 1
  fi
  echo "$url" | sed -E 's#(git@github\.com:|https://github\.com/)##' | sed 's/\.git$//' | cut -d'/' -f2
}

# Helper: get project item ID for an issue (O(1) via issue's projectItems)
pm_get_item_id() {
  local issue_num="$1"
  local repo
  if ! repo=$(pm_get_repo); then
    return 1
  fi

  local result
  result=$(gh api graphql -f query='
    query($owner: String!, $repo: String!, $issue: Int!) {
      repository(owner: $owner, name: $repo) {
        issue(number: $issue) {
          projectItems(first: 20) {
            nodes {
              id
              project { number }
            }
          }
        }
      }
    }
  ' -f owner="$PM_OWNER" -f repo="$repo" -F issue="$issue_num" 2>&1)
  local gql_exit=$?

  if [ $gql_exit -ne 0 ]; then
    echo "Error: GraphQL query failed: $result" >&2
    return 1
  fi

  local item_id
  item_id=$(echo "$result" | jq -r ".data.repository.issue.projectItems.nodes[] | select(.project.number == $PM_PROJECT_NUMBER) | .id")

  if [ -z "$item_id" ]; then
    return 1  # Not found - caller handles error message
  fi

  echo "$item_id"
}

#!/usr/bin/env bash
set -euo pipefail

# project-status.sh - Show current workflow state and labels for an issue
# Usage: project-status.sh <issue-number>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/pm.config.sh"

show_help() {
  cat <<'HELPEOF'
project-status.sh - Show current workflow state and labels for an issue

USAGE
  project-status.sh <issue-number>

OUTPUT
  JSON object with: title, state, assignees, labels, workflow

EXAMPLES
  project-status.sh 123
  project-status.sh 123 | jq -r '.workflow'

NOTES
  Requires: gh CLI with 'project' scope, jq
HELPEOF
}

ISSUE_NUM="${1:-}"

if [ "$ISSUE_NUM" = "--help" ] || [ "$ISSUE_NUM" = "-h" ]; then
  show_help
  exit 0
fi

if [ -z "$ISSUE_NUM" ]; then
  echo "Usage: project-status.sh <issue-number>"
  echo "Run project-status.sh --help for details"
  exit 1
fi

# Check gh CLI auth (but don't require Active ID for status checks)
if ! gh auth status &>/dev/null; then
  echo "Error: gh CLI not authenticated. Run: gh auth login" >&2
  exit 1
fi

if ! command -v jq &>/dev/null; then
  echo "Error: jq not installed." >&2
  echo "  macOS:  brew install jq" >&2
  echo "  Ubuntu: sudo apt-get install jq" >&2
  exit 1
fi

REPO=$(pm_get_repo) || {
  echo "Error: Not in a git repository or no origin remote" >&2
  exit 1
}

# Get issue info + project item state in one query
RESULT=$(gh api graphql -f query='
  query($owner: String!, $repo: String!, $issue: Int!) {
    repository(owner: $owner, name: $repo) {
      issue(number: $issue) {
        title
        state
        assignees(first: 5) { nodes { login } }
        labels(first: 10) { nodes { name } }
        projectItems(first: 5) {
          nodes {
            project { number title }
            fieldValueByName(name: "Workflow") {
              ... on ProjectV2ItemFieldSingleSelectValue { name }
            }
          }
        }
      }
    }
  }
' -f owner="$PM_OWNER" -f repo="$REPO" -F issue="$ISSUE_NUM" 2>&1) || {
  echo "Error: Failed to fetch issue #$ISSUE_NUM" >&2
  echo "" >&2
  # Parse common GraphQL errors
  if echo "$RESULT" | grep -q "Could not resolve to a Repository"; then
    echo "Cause: Repository '$PM_OWNER/$REPO' not found or not accessible" >&2
    echo "Check: PM_OWNER in pm.config.sh and your gh CLI authentication" >&2
  elif echo "$RESULT" | grep -q "INSUFFICIENT_SCOPES\|insufficient_scope"; then
    echo "Cause: gh CLI token missing required scopes" >&2
    echo "Fix: gh auth refresh -s project,read:org" >&2
  elif echo "$RESULT" | grep -q "Could not resolve to an Issue"; then
    echo "Cause: Issue #$ISSUE_NUM does not exist in this repository" >&2
  else
    echo "Raw error:" >&2
    echo "$RESULT" >&2
  fi
  exit 1
}

# Check if issue exists
ISSUE_EXISTS=$(echo "$RESULT" | jq -r '.data.repository.issue')
if [ "$ISSUE_EXISTS" = "null" ]; then
  echo "Error: Issue #$ISSUE_NUM not found"
  exit 1
fi

# Extract and display info
echo "$RESULT" | jq -r --argjson pnum "$PM_PROJECT_NUMBER" '.data.repository.issue | {
  title,
  state,
  assignees: [.assignees.nodes[].login],
  labels: [.labels.nodes[].name],
  workflow: ([.projectItems.nodes[] | select(.project.number == $pnum) | .fieldValueByName.name] | if length > 0 then .[0] else "Not in project" end)
}'

#!/usr/bin/env bash
# pm-codex-gate.sh — PreToolUse:Bash hook that blocks Review transition
# without Codex review evidence when Codex is available.
#
# Structural enforcement of the mandatory Codex review gate.
# Behavioral instructions ("run Codex review before Review") drift under
# token pressure. This hook makes it structurally impossible to skip.
#
# Intercepts: `pm move <num> Review` commands
# Checks:
#   1. Is Codex available? (codex --version)
#   2. If yes, does review evidence exist?
#      - Review ledger at /tmp/codex-review-ledger-<num>.json
#      - Explicit override marker at /tmp/codex-review-override-<num>
#   3. If no evidence → deny the command
#
# The review ledger is created by the Codex Implementation Review sub-playbook.
# Its existence proves the review was attempted. Zero open findings proves it passed.
#
# Override for trivial changes:
#   touch /tmp/codex-review-override-<num>

set -euo pipefail

# ---------- helpers ----------

deny() {
    jq -n --arg reason "$1" \
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason}}'
    exit 0
}

# ---------- read input ----------

input=$(cat 2>/dev/null) || exit 0
command=$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null) || exit 0
[[ -z "$command" ]] && exit 0

# ---------- detect `pm move <num> Review` ----------

# Match: pm move 123 Review (with optional PATH export prefix)
# Case-sensitive on "Review" — that's the exact workflow state name
if ! printf '%s' "$command" | grep -qE 'pm\s+move\s+[0-9]+\s+Review'; then
    exit 0
fi

# Extract issue number from the pm move command
ISSUE_NUM=$(printf '%s' "$command" | grep -oP 'pm\s+move\s+\K[0-9]+')
[[ -z "$ISSUE_NUM" ]] && exit 0

# ---------- check Codex availability ----------

if ! command -v codex &>/dev/null || ! codex --version &>/dev/null; then
    # Codex not available — no gate to enforce, allow through
    exit 0
fi

# ---------- check for explicit override ----------

if [[ -f "/tmp/codex-review-override-${ISSUE_NUM}" ]]; then
    # Explicit override (trivial changes, manual bypass)
    exit 0
fi

# ---------- check for review evidence ----------

LEDGER="/tmp/codex-review-ledger-${ISSUE_NUM}.json"

if [[ ! -f "$LEDGER" ]]; then
    deny "CODEX REVIEW GATE: Cannot move #${ISSUE_NUM} to Review — no Codex review evidence found.

Codex is available but the review ledger does not exist at:
  ${LEDGER}

You MUST run the Codex Implementation Review before transitioning to Review.
Follow post-implementation.md Step 2.

For trivial changes (≤1 file, ≤20 lines): touch /tmp/codex-review-override-${ISSUE_NUM}"
fi

# Ledger exists — check for open findings
OPEN_COUNT=$(jq '[.findings[]? | select(.status == "open")] | length' "$LEDGER" 2>/dev/null || echo "-1")

if [[ "$OPEN_COUNT" == "-1" ]]; then
    deny "CODEX REVIEW GATE: Review ledger for #${ISSUE_NUM} exists but is malformed (cannot parse JSON). Fix the ledger at ${LEDGER} and retry."
fi

if [[ "$OPEN_COUNT" -gt 0 ]]; then
    deny "CODEX REVIEW GATE: Cannot move #${ISSUE_NUM} to Review — ${OPEN_COUNT} open finding(s) in the review ledger.

All findings must be resolved (fixed, justified, or withdrawn) before Review.
Run the Codex Implementation Review fix loop to address remaining findings.

Ledger: ${LEDGER}"
fi

# Evidence exists and all findings resolved — allow
exit 0

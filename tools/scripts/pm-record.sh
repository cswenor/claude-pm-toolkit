#!/usr/bin/env bash
set -euo pipefail

# pm-record.sh — Record decisions and outcomes to JSONL memory files
#
# Used by /issue skill and Claude Code to build persistent project memory.
# Files are git-tracked, human-readable, and machine-queryable via jq.
#
# Usage:
#   pm-record.sh decision --issue 42 --area frontend --decision "Use stores" --rationale "Composable"
#   pm-record.sh outcome --issue 42 --pr 123 --result merged --rounds 1 --summary "Used stores"
#   pm-record.sh board --active 1 --review 2 --rework 0 --done 15

show_help() {
  cat <<'HELPEOF'
pm-record.sh — Record decisions and outcomes to JSONL memory

USAGE
  pm-record.sh decision [options]     Record an architectural decision
  pm-record.sh outcome [options]      Record a work outcome
  pm-record.sh board [options]        Cache project board state

DECISION OPTIONS
  --issue NUM          Issue number
  --area AREA          Area (frontend, backend, contracts, infra)
  --type TYPE          Decision type (architectural, library, approach, workaround)
  --decision TEXT      The decision made
  --rationale TEXT     Why this was chosen
  --alternatives TEXT  Comma-separated alternatives considered
  --files TEXT         Comma-separated affected files

OUTCOME OPTIONS
  --issue NUM          Issue number
  --pr NUM             PR number
  --result RESULT      Result (merged, rework, reverted, abandoned)
  --rounds NUM         Number of review rounds
  --rework TEXT        Comma-separated rework reasons
  --area AREA          Area
  --summary TEXT       Approach summary
  --lessons TEXT       Lessons learned

BOARD OPTIONS
  --active NUM         Active issue count
  --review NUM         Review issue count
  --rework NUM         Rework issue count
  --done NUM           Done issue count
  --backlog NUM        Backlog issue count
  --ready NUM          Ready issue count

EXAMPLES
  pm-record.sh decision \
    --issue 42 --area frontend \
    --decision "Use Svelte stores for wallet state" \
    --rationale "Stores are composable outside components"

  pm-record.sh outcome \
    --issue 42 --pr 123 --result merged --rounds 1 \
    --summary "Svelte stores for wallet state"

  pm-record.sh board --active 1 --review 2 --rework 0 --done 15

FILES
  .claude/memory/decisions.jsonl   Architectural decisions
  .claude/memory/outcomes.jsonl    Work outcomes (merged/rework/reverted)
  .claude/memory/board-cache.json  Cached board state (not JSONL)
HELPEOF
}

[[ "${1:-}" == "--help" || "${1:-}" == "-h" ]] && { show_help; exit 0; }
[[ $# -lt 1 ]] && { show_help; exit 1; }

COMMAND="$1"
shift

# Find repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: Not in a git repository" >&2
  exit 1
fi

MEMORY_DIR="$REPO_ROOT/.claude/memory"
mkdir -p "$MEMORY_DIR"

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

case "$COMMAND" in
  decision)
    ISSUE="" AREA="" TYPE="architectural" DECISION="" RATIONALE="" ALTERNATIVES="" FILES=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --issue) ISSUE="$2"; shift 2 ;;
        --area) AREA="$2"; shift 2 ;;
        --type) TYPE="$2"; shift 2 ;;
        --decision) DECISION="$2"; shift 2 ;;
        --rationale) RATIONALE="$2"; shift 2 ;;
        --alternatives) ALTERNATIVES="$2"; shift 2 ;;
        --files) FILES="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ -z "$DECISION" ]]; then
      echo "ERROR: --decision is required" >&2
      exit 1
    fi

    # Convert comma-separated to JSON arrays
    ALTS_JSON="[]"
    if [[ -n "$ALTERNATIVES" ]]; then
      ALTS_JSON=$(echo "$ALTERNATIVES" | jq -R 'split(",") | map(ltrimstr(" ") | rtrimstr(" "))')
    fi

    FILES_JSON="[]"
    if [[ -n "$FILES" ]]; then
      FILES_JSON=$(echo "$FILES" | jq -R 'split(",") | map(ltrimstr(" ") | rtrimstr(" "))')
    fi

    jq -cn \
      --arg ts "$TIMESTAMP" \
      --argjson issue "${ISSUE:-null}" \
      --arg area "$AREA" \
      --arg type "$TYPE" \
      --arg decision "$DECISION" \
      --arg rationale "$RATIONALE" \
      --argjson alts "$ALTS_JSON" \
      --argjson files "$FILES_JSON" \
      '{
        timestamp: $ts,
        issue_number: (if $issue then $issue else null end),
        area: (if $area != "" then $area else null end),
        type: $type,
        decision: $decision,
        rationale: (if $rationale != "" then $rationale else null end),
        alternatives_considered: $alts,
        files: $files
      }' >> "$MEMORY_DIR/decisions.jsonl"

    echo "Recorded decision: $DECISION"
    ;;

  outcome)
    ISSUE="" PR="" RESULT="" ROUNDS="" REWORK="" AREA="" SUMMARY="" LESSONS=""

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --issue) ISSUE="$2"; shift 2 ;;
        --pr) PR="$2"; shift 2 ;;
        --result) RESULT="$2"; shift 2 ;;
        --rounds) ROUNDS="$2"; shift 2 ;;
        --rework) REWORK="$2"; shift 2 ;;
        --area) AREA="$2"; shift 2 ;;
        --summary) SUMMARY="$2"; shift 2 ;;
        --lessons) LESSONS="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    if [[ -z "$ISSUE" || -z "$RESULT" ]]; then
      echo "ERROR: --issue and --result are required" >&2
      exit 1
    fi

    REWORK_JSON="[]"
    if [[ -n "$REWORK" ]]; then
      REWORK_JSON=$(echo "$REWORK" | jq -R 'split(",") | map(ltrimstr(" ") | rtrimstr(" "))')
    fi

    jq -cn \
      --arg ts "$TIMESTAMP" \
      --argjson issue "$ISSUE" \
      --argjson pr "${PR:-null}" \
      --arg result "$RESULT" \
      --argjson rounds "${ROUNDS:-null}" \
      --argjson rework "$REWORK_JSON" \
      --arg area "$AREA" \
      --arg summary "$SUMMARY" \
      --arg lessons "$LESSONS" \
      '{
        timestamp: $ts,
        issue_number: $issue,
        pr_number: (if $pr then $pr else null end),
        result: $result,
        review_rounds: (if $rounds then $rounds else null end),
        rework_reasons: $rework,
        area: (if $area != "" then $area else null end),
        approach_summary: (if $summary != "" then $summary else null end),
        lessons: (if $lessons != "" then $lessons else null end)
      }' >> "$MEMORY_DIR/outcomes.jsonl"

    echo "Recorded outcome: issue #$ISSUE → $RESULT"
    ;;

  board)
    ACTIVE=0 REVIEW=0 REWORK=0 DONE=0 BACKLOG=0 READY=0

    while [[ $# -gt 0 ]]; do
      case "$1" in
        --active) ACTIVE="$2"; shift 2 ;;
        --review) REVIEW="$2"; shift 2 ;;
        --rework) REWORK="$2"; shift 2 ;;
        --done) DONE="$2"; shift 2 ;;
        --backlog) BACKLOG="$2"; shift 2 ;;
        --ready) READY="$2"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
      esac
    done

    jq -n \
      --arg ts "$TIMESTAMP" \
      --argjson active "$ACTIVE" \
      --argjson review "$REVIEW" \
      --argjson rework "$REWORK" \
      --argjson done "$DONE" \
      --argjson backlog "$BACKLOG" \
      --argjson ready "$READY" \
      '{
        timestamp: $ts,
        active: $active,
        review: $review,
        rework: $rework,
        done: $done,
        backlog: $backlog,
        ready: $ready
      }' > "$MEMORY_DIR/board-cache.json"

    echo "Updated board cache"
    ;;

  *)
    echo "Unknown command: $COMMAND" >&2
    echo "Usage: pm-record.sh {decision|outcome|board} [options]" >&2
    exit 1
    ;;
esac

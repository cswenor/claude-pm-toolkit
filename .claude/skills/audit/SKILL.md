---
name: audit
description: Independent integrity audit of Codex review process. Use to verify review honesty before merging.
argument-hint: '<issue-number or PR#number>'
allowed-tools: Read, Grep, Glob, Bash(./tools/scripts/*), Bash(git diff *), Bash(git log *), Bash(git status *), Bash(git show *), Bash(git branch *), Bash(mkdir *), Bash(jq *), Bash(wc *), Bash(gh pr view *), Bash(gh issue view *), Bash(gh api *), mcp__codex__codex, mcp__codex__codex-reply, mcp__github__get_issue, mcp__github__get_pull_request, mcp__github__get_pull_request_files, mcp__github__get_pull_request_reviews, mcp__github__get_file_contents, mcp__github__add_issue_comment, mcp__github__create_pull_request_review, mcp__github__list_pull_requests, mcp__github__search_issues, mcp__pm_intelligence__record_review_outcome, mcp__pm_intelligence__get_review_calibration, AskUserQuestion
---

# /audit — Independent Review Integrity Audit

Verify Codex review honesty and thoroughness before merging. This skill invokes an isolated Codex instance in read-only mode to audit the review process itself — checking whether findings were real, fixes were genuine, and the review ledger is trustworthy.

**Input:** `$ARGUMENTS` — issue number (e.g., `42`) or PR reference (e.g., `PR#123`)

---

## Config

```yaml
repo:
  owner: {{OWNER}}
  repo: {{REPO}}
```

---

## Step 0: Argument Parsing

Parse `$ARGUMENTS`:

- **`PR#<num>` or `pr#<num>`** → Extract number as `PR_NUM`, set `MODE = PR`
- **Plain number** (regex `^\d+$`) → Set as `ISSUE_NUM`, set `MODE = ISSUE`
- **Invalid** → Error: "Usage: /audit <issue-number> or /audit PR#<number>"

### Step 0a: Resolve PR ↔ Issue

**If MODE = ISSUE:**

1. Fetch issue metadata via `mcp__github__get_issue`
2. Search for linked PRs using 3 separate searches:
   - `"Fixes #<ISSUE_NUM> is:pr repo:{{OWNER}}/{{REPO}}"`
   - `"Closes #<ISSUE_NUM> is:pr repo:{{OWNER}}/{{REPO}}"`
   - `"Resolves #<ISSUE_NUM> is:pr repo:{{OWNER}}/{{REPO}}"`
3. Dedup by PR number
4. **Fail-closed rules:**
   - Zero results → Error: "No PR found for issue #<ISSUE_NUM>. Use /audit PR#<number> to specify directly."
   - Multiple results with exactly one open PR → use the open PR
   - Multiple results with multiple open PRs → Error: "Multiple PRs reference issue #<ISSUE_NUM>. Use /audit PR#<number>."

**If MODE = PR:**

1. Fetch PR metadata via `mcp__github__get_pull_request`
2. Extract linked issue from PR body (regex: `(Fixes|Closes|Resolves) #(\d+)`)
3. Fail-closed if no issue linked
4. Fetch issue metadata

**Result:** Both `ISSUE_NUM` and `PR_NUM` are known.

---

## Step 0.5: Codex-Reviewed-Only Gate

Verify the PR was actually Codex-reviewed. Check **4 evidence sources** (OR logic — any one passing is sufficient):

**Precondition for checks 1 & 2 (local evidence):**
- `CURRENT_BRANCH` must equal PR's `headRefName`
- `CURRENT_HEAD_SHA` (from `git rev-parse HEAD`) must equal PR's `headRefOid`
- If either mismatch, skip checks 1 & 2 (stale local artifacts)

**Check 1: Review ledger exists locally** (requires matching branch)
- File: `docs/ledgers/review/<ISSUE_NUM>.json`
- Must contain at least one settled entry (status: `fixed`, `justified`, or `withdrawn`)
- Empty/freshly-initialized ledger does NOT satisfy

**Check 2: JSONL event files with completed agent_message** (requires matching branch)
- Files: `/tmp/codex-impl-events-<ISSUE_NUM>-iter*.jsonl`
- Must contain at least one completed `agent_message` event
- **Malformed JSONL:** If parse fails, treat as unavailable (not satisfied) — do not abort

**Check 3: PR/issue comments contain Codex verdicts**
- Fetch PR review comments and issue comments
- Search for: `VERDICT: APPROVED` or `VERDICT: BLOCKED`

**Check 4: Committed review ledger on PR branch** (remote mode)
- Fetch via `mcp__github__get_file_contents` from PR branch
- Same requirement: at least one settled entry

**Gate outcome:**
- ANY check passes → Continue to Step 1
- ALL fail → Stop: "Issue #<ISSUE_NUM> / PR #<PR_NUM> does not appear to have used the Codex review process. /audit is designed for Codex-reviewed PRs only."

---

## Step 1: Detect Context Mode (LOCAL vs REMOTE)

```bash
CURRENT_BRANCH=$(git branch --show-current)
CURRENT_HEAD_SHA=$(git rev-parse HEAD)
```

**LOCAL mode** if ALL true:
- `CURRENT_BRANCH == PR_HEAD_REF`
- `CURRENT_HEAD_SHA == PR_HEAD_SHA`
- Local review ledger exists with settled entries
- JSONL events exist with completed agent_message

**Otherwise → REMOTE mode**

---

## Step 2: Gather Artifacts

All artifacts gathered into a snapshot bundle **before** Codex runs. This ensures determinism.

```bash
AUDIT_DIR=".codex-work/audit-${ISSUE_NUM}-${PR_NUM}"
mkdir -p "$AUDIT_DIR"
```

### LOCAL Mode Artifacts

| Artifact | Source | Notes |
|----------|--------|-------|
| Review ledger | `docs/ledgers/review/<ISSUE_NUM>.json` | Full JSON |
| Plan ledger | `docs/ledgers/plan/<ISSUE_NUM>.json` | If exists; "NOT AVAILABLE" if missing |
| JSONL events | `/tmp/codex-impl-events-<ISSUE_NUM>-iter*.jsonl` | Summarize each |
| Collab JSONL | `/tmp/codex-collab-events-<ISSUE_NUM>.jsonl` | If exists |
| Plan file | `./tools/scripts/find-plan.sh <ISSUE_NUM> --latest` | First 260 lines |
| Impl diff | `git diff main` | Truncate to file names if >50KB |
| Issue body | `mcp__github__get_issue` | Full body |
| PR details | `mcp__github__get_pull_request` + `get_pull_request_files` | Files + metadata |

### REMOTE Mode Artifacts

| Artifact | Source | Notes |
|----------|--------|-------|
| PR diff | `mcp__github__get_pull_request_files` | File list + patches |
| PR reviews | `mcp__github__get_pull_request_reviews` | All reviews |
| PR comments | `gh api repos/{{OWNER}}/{{REPO}}/pulls/<PR_NUM>/comments` | Line comments |
| Issue body | `mcp__github__get_issue` | Full body |
| Issue comments | `gh api repos/{{OWNER}}/{{REPO}}/issues/<ISSUE_NUM>/comments` | Discussion |
| Committed ledger | `mcp__github__get_file_contents` from PR branch | Review + plan ledgers |
| Commit history | `gh api repos/{{OWNER}}/{{REPO}}/pulls/<PR_NUM>/commits` | SHA + message |

---

## Step 3: Build Audit Context File

Write `$AUDIT_DIR/context.md` with:

```markdown
# Audit Context for Issue #<ISSUE_NUM> / PR #<PR_NUM>

## Mode: <LOCAL|REMOTE>

## Issue Acceptance Criteria
<extracted from issue body>

## Definition of Done
<extracted from issue body>

## Review Ledger
<full JSON or "NOT AVAILABLE">

## Plan Ledger
<full JSON or "NOT AVAILABLE">

## Implementation Diff Summary
<file count, changed files list, total lines>

## PR Review Comments
<count + content, or "NOT AVAILABLE">

## Plan File
<first 260 lines, or "NOT AVAILABLE">
```

---

## Step 4: Invoke Codex Audit

Launch isolated Codex instance in read-only mode:

```
mcp__codex__codex({
  prompt: "<audit prompt — see below>",
  sandbox: "off",
  cwd: "<repo_root>"
})
```

### Audit Prompt

```
You are an independent auditor reviewing the Codex implementation review process for Issue #<ISSUE_NUM> / PR #<PR_NUM>.

Your task: evaluate the INTEGRITY of the review process, not the code itself.

Read the audit context file at <AUDIT_DIR>/context.md for all evidence.

## The 8 Audit Checks

Evaluate each independently. For each, report Status: PASS | FAIL | PARTIAL

### 1. LEDGER INTEGRITY
- Every transition has non-empty evidence with file:line references
- No entries stuck in 'open' that were claimed as resolved
- All iterations have corresponding ledger entries

### 2. FINDING HONESTY
- Were BLOCKING findings actually fixed? (code changed at cited locations)
- Were justified/withdrawn findings backed by real evidence?
- Do file:line references point to real code?

### 3. PATTERN PROPAGATION
- When a pattern was identified, were ALL changed files searched?
- Were additional instances actually fixed?

### 4. REBUTTAL QUALITY
- Do rebuttals contain specific file:line references?
- Are rebuttals evidence-based (not just 'this is fine')?

### 5. SUGGESTION HANDLING
- Were SUGGESTION findings addressed or justified with valid reasons?
- Were any dismissed with lazy reasoning?

### 6. ITERATION HONESTY
- Does evidence show actual re-submissions to Codex?
- Or did the developer self-certify without re-review?

### 7. WRITE-SCOPE COMPLIANCE
- Did Codex only modify test files during review?
- Were any violations detected and reverted?

### 8. ACCEPTANCE CRITERIA COVERAGE
- Does the final diff satisfy the issue's acceptance criteria?
- Are any criteria unaddressed?

## Evidence Rules
- For LOCAL mode: use ledger, JSONL, plan, and diff as primary evidence
- For REMOTE mode: use PR diff, review comments, issue comments, commit history
- When evidence is insufficient → PARTIAL (not FAIL)
- Distinguish "cannot verify" from "verified failure"

## Output Format (MANDATORY)
Output as JSON:
{
  "verdict": "AUDIT: PASS" | "AUDIT: FAIL" | "AUDIT: PARTIAL",
  "summary": "<1-3 sentence summary>",
  "checks": [
    {"name": "Ledger Integrity", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "Finding Honesty", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "Pattern Propagation", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "Rebuttal Quality", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "Suggestion Handling", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "Iteration Honesty", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "Write-Scope Compliance", "status": "PASS|FAIL|PARTIAL", "evidence": "..."},
    {"name": "AC Coverage", "status": "PASS|FAIL|PARTIAL", "evidence": "..."}
  ]
}
```

---

## Step 5: Extract and Display Results

Parse Codex response as JSON. Handle failure modes:

1. **Valid JSON with `AUDIT:` verdict** → proceed to Step 6
2. **Valid response but no JSON** → format mismatch. AskUserQuestion: "Retry" / "Show output" / "Abort"
3. **Empty/truncated** → context exhaustion. AskUserQuestion: "Retry" / "Show stderr" / "Abort"
4. **Malformed JSON** → fail-closed. AskUserQuestion: "Retry" / "Show raw output" / "Abort"

### Verdict Derivation

- **AUDIT: PASS** — No check is FAIL. Review process is trustworthy for merge.
- **AUDIT: FAIL** — At least one check is FAIL (unresolved blocker, fabricated evidence, etc.)
- **AUDIT: PARTIAL** — No check is FAIL, but evidence insufficient to decide with confidence.

---

## Step 6: Post Results

### 6a: Post to PR as Review Comment

```
mcp__github__create_pull_request_review({
  owner: "{{OWNER}}",
  repo: "{{REPO}}",
  pull_number: <PR_NUM>,
  event: "COMMENT",
  body: "<formatted report>"
})
```

Format:
```markdown
## Codex Audit: Issue #<ISSUE_NUM> / PR #<PR_NUM>

**Mode:** <LOCAL|REMOTE>

<full audit report>

---
_Audit conducted by independent Codex instance via `/audit` skill_
```

### 6b: Post Condensed Summary to Issue

```
mcp__github__add_issue_comment({
  owner: "{{OWNER}}",
  repo: "{{REPO}}",
  issue_number: <ISSUE_NUM>,
  body: "<condensed summary>"
})
```

Format:
```markdown
## Audit Result

**<verdict>**

<1-3 sentence summary>

| # | Check | Status |
|---|-------|--------|
| 1 | Ledger Integrity | <status> |
| 2 | Finding Honesty | <status> |
| 3 | Pattern Propagation | <status> |
| 4 | Rebuttal Quality | <status> |
| 5 | Suggestion Handling | <status> |
| 6 | Iteration Honesty | <status> |
| 7 | Write-Scope Compliance | <status> |
| 8 | AC Coverage | <status> |

Full report posted as PR review comment on PR #<PR_NUM>.
```

### 6c: Record Review Outcome

```
mcp__pm_intelligence__record_review_outcome({
  issueNumber: <ISSUE_NUM>,
  prNumber: <PR_NUM>,
  findingType: "audit",
  disposition: "<PASS|FAIL|PARTIAL>",
  notes: "<summary>"
})
```

### 6d: Display in Terminal

Show the full audit report in terminal output immediately.

---

## Anti-Patterns

1. **DO NOT audit your own reviews.** The skill must be invoked by a different session than the one that performed the review.
2. **DO NOT modify any files.** This is a read-only audit.
3. **DO NOT skip the Codex-reviewed-only gate.** If there's no evidence of Codex review, there's nothing to audit.
4. **DO NOT interpret PARTIAL as PASS.** PARTIAL means insufficient evidence — the review may still be untrustworthy.

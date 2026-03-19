# Sub-Playbook: Codex Implementation Review

## Goal

Evidence-based adversarial code review from Codex after implementation. Codex writes failing tests as proof of bugs — the test IS the finding. Code quality is evaluated as a first-class review concern. Convergence tracked via the review ledger.

## Prerequisites

- `codex_available` is true
- Implementation complete, changes staged (`git add` — Codex sees staged changes via `git diff`)

## Codex Has Full Codebase Access

**Do NOT pre-generate diffs, patches, or summaries for Codex.** Codex has full filesystem access. It independently runs `git diff`, `git status`, reads files, browses the codebase, and writes test scripts. Just give it the issue number and let it work.

## IMPL_REVIEW_PROMPT (Single Source of Truth)

This canonical block is used in ALL review invocations (initial, follow-up, post-commit). Never inline variants — always reference this block.

```
EVIDENCE-BASED BUG FINDING: When you find a bug or unhandled edge case, write a failing test that demonstrates the problem. The test IS the finding. Follow the project's existing test conventions:
- Discover the test framework, file locations, and naming patterns from the codebase
- Place tests in the correct location per project conventions
- Use existing mock factories and patterns
WRITE SCOPE: You may ONLY create or modify test files. Do NOT modify implementation/source code.
After writing tests, report: (1) which test files were created or modified, (2) the command to run them.

CODE QUALITY REVIEW: Evaluate the implementation for:
- Efficiency (unnecessary computation, suboptimal patterns)
- Best practices (idiomatic patterns, framework conventions)
- Readability and maintainability
Report quality findings as BLOCKING or SUGGESTION with description of the better pattern.

INSTANCE VERIFICATION (BLOCKING severity gate): Before classifying a theoretical edge case as BLOCKING, search the relevant surfaces (changed files, callers, tests) for concrete instances. If zero instances exist, classify as SUGGESTION — not BLOCKING. BLOCKING requires real instances or provably reachable code paths.

PATTERN-LEVEL REPORTING: For every finding (bug or quality), assign a pattern label — a short slug describing the abstract bug class (e.g., missing-null-check, unhandled-error). Search ALL changed files for every instance of the same pattern. Report findings grouped by pattern:
PATTERN: <label> — <description of the bug class>
  - <file>:<line> — <instance-specific detail>
  - <file>:<line> — <instance-specific detail>
Each instance is a separate finding. Do NOT stop after finding one instance — exhaustively search all changed files.

Verify each acceptance criterion is met or has documented justification for deferral. End with exactly VERDICT: APPROVED or VERDICT: BLOCKED — <reason>. APPROVED requires: all tests pass (including any you wrote) AND no BLOCKING quality findings AND code quality is acceptable.
```

## Risk-Proportional Depth

Before launching the full review loop, assess change size:

```bash
FILES_CHANGED=$(git diff --name-only main...HEAD | wc -l | tr -d ' ')
LINES_CHANGED=$(git diff --shortstat main...HEAD | grep -oE '[0-9]+ insertion|[0-9]+ deletion' | grep -oE '[0-9]+' | paste -sd+ | bc)
```

| Change Size | Threshold | Review Depth |
|-------------|-----------|-------------|
| **Trivial** | ≤ 1 file AND ≤ 20 lines | Skip Codex review entirely (user can override) |
| **Small** | ≤ 3 files AND ≤ 100 lines | Single-pass review (no iteration loop) |
| **Standard** | Everything else | Full adversarial review loop |

## Flow

### Step 0a: Initialize Review Ledger (MANDATORY)

**Create the review ledger before the first Codex call.** The ledger's existence is checked by the `pm-codex-gate.sh` hook — if it doesn't exist, `pm move <num> Review` is structurally blocked. Initialize even if you expect zero findings:

```bash
cat > /tmp/codex-review-ledger-<issue_num>.json <<'LEDGER'
{
  "issue": "<issue_num>",
  "iteration": 0,
  "findings": []
}
LEDGER
```

**This is the structural evidence that Codex review was attempted.** The hook checks:
1. Ledger exists → review was run
2. Zero `open` findings → review passed
3. Missing ledger → review was skipped → **transition blocked**

### Step 0b: Pre-seed Review Context File

Generate a review context file that gives Codex a head start on navigating the implementation:

```bash
mkdir -p .codex-work
PLAN_PATH=$(./tools/scripts/find-plan.sh <issue_num> --latest 2>/dev/null || echo "")
```

Claude reads the plan (if found), extracts key file paths, architecture notes, test locations, and documentation references, then writes:

```bash
cat > .codex-work/review-context-<issue_num>.md <<'REVIEW_CTX'
# Review Context for Issue #<issue_num>

## Key Files
<extracted file paths from plan — files mentioned in implementation sections>

## Architecture Notes
<extracted design decisions, patterns, constraints from the plan>

## Test Locations
<extracted test file paths and commands from the plan>

## Related Documentation
<extracted doc references from the plan>
REVIEW_CTX
```

If no plan found, skip context file creation — Codex still works without it.

### Step 1: Initial Review

Codex has full filesystem access in `workspace-write` sandbox. It independently explores the codebase, runs git commands, and writes failing tests as proof of bugs.

```
mcp__codex__codex({
  prompt: "Review the implementation for issue #<issue_num>. Run git diff main to see all tracked changes relative to main. Run git status to check for untracked files — if any are part of the implementation, read their contents directly. A review context file is available at .codex-work/review-context-<issue_num>.md — read it first to orient your review if it exists.\n\n<IMPL_REVIEW_PROMPT>",
  sandbox: "workspace-write",
  approval-policy: "never",
  cwd: "<repo_root>"
})
```

**Why `workspace-write`:** Codex writes failing tests as evidence of bugs. The test IS the finding. `workspace-write` allows writing to any file in the workspace — the "test files only" constraint is prompt-enforced. Step 1.5 mechanically verifies compliance.

**Key properties:**
- Codex has full codebase access — no pre-generated diff needed
- Codex independently runs `git diff main`, `git status`, reads files, writes tests
- Any files Codex creates during review are visible to Claude for evaluation

### Step 1.5: Write-Scope Verification

After Codex returns, mechanically verify it only wrote test files:

```bash
# Check what files Codex created or modified (compare to pre-review state)
git diff --name-only  # Shows modified tracked files
git status --short    # Shows new untracked files
```

For each file Codex touched:
- Test files (matching project test conventions: `*.test.*`, `*.spec.*`, `__tests__/*`, `test/*`) → OK
- Non-test files → **Write-scope violation.** Revert the non-test changes: `git checkout -- <file>`. Log the violation.

### Step 2: Check for Failures (Evidence Gate Hardening)

1. If MCP tool returns an error: AskUserQuestion with "Retry" / "Override" / "Show error".
2. If response is empty or truncated: context exhaustion. AskUserQuestion with "Retry" / "Override".
3. **Verdict extraction:** Look for `VERDICT: APPROVED` or `VERDICT: BLOCKED` in the response. If neither found and response seems truncated → fail-closed.
4. **Suspicious output:** If `VERDICT: APPROVED` with zero test files written AND diff has >100 lines → warn "Review approved a large diff with zero evidence." Offer: "Accept" / "Retry" / "Override".

### Step 3: Parse Findings

Extract findings from Codex output. Codex may output structured patterns or prose — handle both:

**Preferred (pattern-level reporting):**
```
PATTERN: missing-null-check — Missing null guard on optional field
  - src/auth.ts:45 — user.email accessed without null check
  - src/profile.ts:22 — same pattern on user.name
```

**Also accepted (VERDICT + prose):**
```
VERDICT: BLOCKED — 2 bugs found
- src/auth.ts:45: Unsanitized user input
- lib/parse.ts:12: Missing null check
```

Claude parses findings into the review ledger format regardless of output style.

**Blocking thresholds (applied by Claude after parsing):**

| Category | Blocking Threshold |
|----------|--------------------|
| **Failing test written by Codex** | Always blocks (the test IS proof) |
| **BLOCKING quality finding** | 1+ blocks |
| **SUGGESTION quality finding** | Never auto-blocks |

**Evidence enforcement:** Findings without `file:line` citations are automatically downgraded to advisory.

### Review Ledger

The Review Ledger is a JSON file at `/tmp/codex-review-ledger-<issue_num>.json` that tracks all findings across iterations. This is the source of truth for convergence — not Codex's verdict.

```json
{
  "issue": "<issue_num>",
  "iteration": 2,
  "findings": [
    {
      "id": "F1",
      "pattern_label": "missing-null-check",
      "file": "src/auth.ts",
      "line": 45,
      "description": "Unsanitized user input passed to query builder",
      "test_file": "src/__tests__/auth.test.ts",
      "raised_iteration": 1,
      "status": "fixed",
      "resolution": "Switched to parameterized query"
    }
  ]
}
```

**Statuses:** `open`, `fixed`, `justified`, `withdrawn`.

**Claude updates the ledger** after each iteration:
- New findings from Codex → added as `open`
- Findings Claude fixed → `fixed` with what changed
- Findings Claude justified → `justified` with explanation
- Findings Codex withdrew → `withdrawn`

### Step 4: User Choice

AskUserQuestion:

```
question: "Codex raised findings on the implementation. How do you want to proceed?"
header: "Impl Review"
options:
  - label: "Continue — fix and re-submit (Recommended)"
    description: "Claude addresses feedback and re-submits for review"
  - label: "Override — proceed without fixing"
    description: "Skip remaining findings"
  - label: "Show full Codex output"
    description: "Display the complete review output"
```

### Step 5: Fix Loop

1. **Run Codex's test files** — if Codex wrote tests, run them. Failures are proven bugs that MUST be fixed.
2. **Address BLOCKING quality findings** — fix each one.
3. **Handle SUGGESTION findings** — address or justify (with specific reason, not "it's just a suggestion").
4. **Pattern propagation** — for each finding, search ALL changed files for the same pattern. Fix all instances.
5. **Re-run ALL tests** (`{{TEST_COMMAND}}` + Codex's test commands) — fixes must not break anything.
6. **Stage changes** — `git add` so Codex sees them in the next review.

After fixes, start a **fresh Codex session** (not a thread continuation — each iteration is independent):

```
mcp__codex__codex({
  prompt: "Review the implementation for issue #<issue_num>. The review ledger at /tmp/codex-review-ledger-<issue_num>.json shows what was found and fixed in prior iterations — read it first. Run git diff main to see current changes. A review context file is at .codex-work/review-context-<issue_num>.md if it exists.\n\nThis is iteration <N>. Changes since last review: [summary with file:line references].\n\n<IMPL_REVIEW_PROMPT>",
  sandbox: "workspace-write",
  approval-policy: "never",
  cwd: "<repo_root>"
})
```

**Key: fresh sessions, not thread continuations.** Each iteration is a new `mcp__codex__codex` call. The review ledger provides historical context — Codex reads it directly at the start of each session. This prevents context exhaustion from accumulated conversation history.

Run Steps 1.5, 2, 3, 4 again after each iteration.

### Step 5.5: Autonomous Refactor Trigger

After fixes, check the ledger for pattern clusters:

1. Group findings by `pattern_label`
2. If any label has 3+ instances in the same class/module → extract shared helper
3. If refactor is out of scope → Discovered Work issue

### Step 6: Termination

Loop terminates when:

- **Codex outputs `VERDICT: APPROVED`** AND **ledger has zero `open` findings** AND **all Codex-written tests pass**, OR
- User chooses "Override"
- **5-iteration hard cap:** Force AskUserQuestion with "Accept" / "Override" / "Show ledger"

**Anti-shortcut rule:** Claude MUST NOT self-certify. Every fix MUST be re-submitted to Codex via a fresh session. Claude fixing findings, updating the ledger to "fixed", and declaring "done" without re-submission is the exact failure mode this loop prevents.

**Ledger cleanup:** Preserved for /pm-review self-check step. Cleaned up after Post-Implementation Sequence completes.

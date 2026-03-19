# Sub-Playbook: Post-Implementation Sequence

## Goal

Enforced ordered sequence from completed implementation to Review transition. Prevents steps from being skipped. **Codex review is mandatory when codex is available — no exceptions.**

## Prerequisites

- Implementation complete
- On a feature branch (not main)

## Execution Model

**After ExitPlanMode (START/CONTINUE):** The skill has completed. Claude Code resumes normal operation with its standard tool permissions (Bash, Edit, Write, etc.). The skill's `allowed-tools` frontmatter only restricts tools during skill execution — it does not apply after the skill ends. Claude Code follows this sequence as behavioral guidance.

**During REWORK mode:** The skill presents feedback and instructs Claude Code to follow this sequence. Claude Code executes each step with its normal capabilities. This is the same pattern used today — REWORK already instructs `{{TEST_COMMAND}}` which is not in the skill's `allowed-tools` but is executed by Claude Code.

## Sequence (MANDATORY — execute in order, do not skip steps)

> **Why tests before Codex review:** If Codex reviews first and approves, then tests fail, the fixes go in without re-review. Running tests first ensures Codex only reviews mechanically-correct code.
>
> **Why commit after Codex review:** Committing before review forces premature commits and messy fixup history. Committing after Codex approval produces clean history. Codex can see uncommitted changes via `git diff` and `git status`.

### Step 1: Run Tests

**⚠️ STOP — do not skip this step.**

`{{TEST_COMMAND}}`

Fix any failures — do NOT bypass. If fixes require code changes, re-run tests after fixing.

### Step 2: Codex Implementation Review (MANDATORY when codex available)

**Applies to ALL issue types.** Codex review is mandatory for every issue — docs, chores, CI, infra, refactors, tooling, policy changes, features, and bug fixes alike. There are no exemptions based on change type.

If `codex_available` is true:

1. Run **Sub-Playbook: Codex Implementation Review** (full adversarial review loop)
2. Address all findings: fix proven bugs, address BLOCKING findings, handle SUGGESTION findings
3. If code changed, re-run ALL tests (Step 1) before re-submitting to Codex
4. Loop until: no BLOCKING findings + Codex VERDICT: APPROVED
5. **Evidence produced:** Review ledger at `/tmp/codex-review-ledger-<issue_num>.json` and JSONL events

If `codex_available` is false:
Display: "Codex not available — skipping implementation review."

**⚠️ NON-NEGOTIABLE:** Claude MUST NOT:
- Skip Codex review and self-certify code quality
- Recommend any override or bypass of the Codex review gate
- Proceed to Step 3 without Codex VERDICT: APPROVED (when codex available)
- Treat "Codex is slow" or "changes are trivial" as justification for skipping

### Step 3: Commit

Commit all implementation changes:

```
git add <specific files>
git commit -m "<type>(<scope>): <description>"
```

**Codex test files:** Any test files Codex created during review MUST be included in the commit. These serve as regression tests.

**Ledger files:** If review/plan ledgers exist for this issue, stage them:
```bash
for f in docs/ledgers/plan/<issue_num>.json docs/ledgers/review/<issue_num>.json; do
  [ -f "$f" ] && git add "$f"
done
```

### Step 3.5: Post-Commit Codex Review (fresh verification)

**Applies to ALL issue types — same universality as Step 2.**

If `codex_available` is true:

Run a fresh Codex review against **committed** code. This is a single verification pass (not an iterative loop) that produces evidence for the Review transition gate. Codex has full codebase access — do NOT pre-generate diffs.

```
mcp__codex__codex({
  prompt: "Review the implementation for issue #<issue_num>. Run git diff main to see committed changes. Run git status for any uncommitted changes. If untracked files exist that are part of the implementation, read their contents directly. A review context file is at .codex-work/review-context-<issue_num>.md — read it first if it exists.\n\n<IMPL_REVIEW_PROMPT>",
  sandbox: "workspace-write",
  cwd: "<repo_root>"
})
```

Uses the same canonical `IMPL_REVIEW_PROMPT` block from Sub-Playbook: Codex Implementation Review. Codex independently explores the codebase, writes failing tests as evidence, and reports findings with pattern labels.

- If `VERDICT: APPROVED` → proceed to Step 4
- If `VERDICT: BLOCKED` → address findings, amend commit, re-run Step 3.5
- Evidence: JSONL events at `/tmp/codex-impl-events-<issue_num>-iterPC.jsonl`

If `codex_available` is false: skip to Step 4.

### Step 4: Create or Update PR

If no PR exists yet: create PR with `Fixes #<issue_num>` in body.
If PR already exists: push changes.

**Note:** Tests and Codex review both passed before PR creation.

### Step 5: Self-Review with /pm-review

Run `/pm-review <pr-or-issue-number>` as a self-check. When invoking /pm-review in this context, select the **ANALYSIS_ONLY** action — do NOT select APPROVE_ONLY, POST_REVIEW_COMMENTS, MERGE_AND_CHECKLIST, or any other mutating action. This step is diagnostic only. State transitions happen in Step 7.

**⚠️ Constraint:** When /pm-review prompts for PM-process fixes, select **SKIP_PM_FIXES**. When prompted for a verdict action, select **ANALYSIS_ONLY**. Even if /pm-review's output includes automatic PM-fix actions (workflow moves, label changes, comment posting), Claude MUST NOT execute them during this step. Read the analysis output, discard any mutation recommendations, and act only on the diagnostic findings. Structural enforcement of a non-mutating /pm-review mode is a follow-up enhancement.

If /pm-review identifies **code/implementation issues** (missing AC, scope drift, policy violations in the diff):

1. Address the feedback
2. If code changed, commit fixes and return to Step 1 (full loop: tests → Codex → commit → post-commit review)
3. Re-run /pm-review until code findings are resolved

**PM-process findings** (workflow state, labels, project fields, missing issue comments) are NOT code issues — do not loop on them. Step 7 handles the Review transition, and post-merge checklist handles Done.

If user overrides: proceed to Step 6 with acknowledgment.

### Step 6: Acceptance Criteria Checkbox Gate

Before transitioning to Review, verify all acceptance criteria are checked off:

1. **Fetch issue body:** `mcp__github__get_issue` with owner, repo, issue_number
2. **Parse `## Acceptance Criteria` section:** Extract all `- [ ]` and `- [x]` items
3. **Evaluate:**
   - If no AC section found → warn "No Acceptance Criteria section found" but do not block
   - If all items checked (`- [x]`) → proceed to Step 7
   - If unchecked items exist → display and offer choices:

```
question: "X of Y acceptance criteria are unchecked. PRs should not reach Review with incomplete AC."
header: "AC Gate"
options:
  - label: "Check off completed criteria (Recommended)"
    description: "Update the issue body to mark completed items"
  - label: "Override — proceed anyway"
    description: "Move to Review with unchecked items (adds warning comment)"
  - label: "Show unchecked items"
    description: "Display the items that are still unchecked"
```

**On "Check off completed":**
- For each unchecked item, verify it's actually done (check code, tests, PR diff)
- Update issue body: replace `- [ ]` with `- [x]` for completed items via `mcp__github__update_issue`
- Re-evaluate: if still unchecked items remain, re-prompt

**On "Override":**
- Add warning comment to the issue via `mcp__github__add_issue_comment`:
  ```
  ⚠️ Moving to Review with X unchecked acceptance criteria (overridden by developer).
  Unchecked: [list items]
  ```
- Proceed to Step 7

**On "Show unchecked items":**
- Display each unchecked item with its text
- Re-prompt with "Check off" / "Override"

### Step 7: Transition to Review

`pm move <num> Review`

Verify with `pm status <num>` that workflow is now "Review".

## Sequence Summary

```
Step 1: Tests           ──→ fix failures, re-run
Step 2: Codex Review    ──→ fix findings, re-run tests, re-submit (MANDATORY when codex available)
Step 3: Commit          ──→ include Codex test files + ledgers
Step 3.5: Post-Commit   ──→ fresh Codex verification against committed code
Step 4: PR              ──→ create or push
Step 5: /pm-review      ──→ analysis only, loop on code findings
Step 6: AC Gate         ──→ verify all criteria checked off
Step 7: Review          ──→ pm move <num> Review
```

## Precedence Note

This sequence deliberately extends CLAUDE.md's generic "After Opening PR → move to Review" (CLAUDE.md §"After Opening PR") and PM_PLAYBOOK.md's Review entry criteria (PM_PLAYBOOK.md §"Review") by inserting quality gates (Codex review, /pm-review, AC gate) between implementation and Review transition. The purpose is to catch issues BEFORE signaling "ready for human review." This precedence applies ONLY to /issue-managed work; non-skill workflows still follow the generic CLAUDE.md rule.

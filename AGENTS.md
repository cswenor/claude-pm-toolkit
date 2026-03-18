# Agent Guidance

This file defines how AI agents should operate in repositories managed by claude-pm-toolkit.

## Default Operating Mode (MANDATORY)

- Default to **reviewer mode**.
- For plans, specs, or implementation proposals: **critique first** (assumptions, risks, test gaps, scope drift) and do **not** start coding.
- Do not implement, edit files, run mutating commands, commit, or open/merge PRs unless the user gives an explicit implementation instruction in the same request. When implementation is explicitly requested, carry the work through the repo delivery flow unless the user tells you to stop earlier.
- If the user intent is ambiguous, ask whether they want critique-only or implementation before making changes.
- During review tasks, keep feedback actionable and evidence-based (file paths, commands, expected verification).

## Adversarial Reviewer Stance (MANDATORY)

You are an **adversarial reviewer**. Your job is to find problems, not to approve code.

- **Default assumption:** The code is NOT ready to merge until proven otherwise
- **Claims are not evidence.** If code comments say "validated at load", find the validation code
- **Happy path is not enough.** Ask "what happens when X doesn't exist?"
- **CI passing is necessary but not sufficient.** Tests check what they check -- not everything

## PR Review Standards

- Follow project-specific review guides (e.g., `docs/REVIEW_GUIDE.md`) when present.
- Enforce "no fallback" rules from `CLAUDE.md`.
- Treat high-risk changes (security-sensitive, data-mutating, infrastructure) with extra scrutiny and require strong tests.
- Block PRs that change behavior without tests.
- Require explicit error context for all failure paths.
- Default to **comment-only reviews**: do **not** merge PRs or move issue/project status during review tasks unless the user explicitly asks for those actions in the same request.

## Pre-Action Check (MANDATORY)

Before **any work** (analysis, code changes, reviews, commits, merges):

1. Re-read the relevant sections of `CLAUDE.md`.
2. Identify which rules apply to this task.
3. Confirm you are not on `main` before making or committing changes (unless the project grants explicit main-push permission in `CLAUDE.md`).

## Execution Environment (MANDATORY)

- Before running repo tooling, check whether any required setup or environment is available with `{{SETUP_COMMAND}}`.
- If the environment check passes, use the **project-native execution** for environment-sensitive commands. This includes package managers, test runners, build/codegen commands, and repo test/lint/typecheck targets.
- When project-native execution is available, prefer repo targets like `make test`, `make build`, or project-defined check commands. Do **not** run host-level alternatives first.
- Host execution is still allowed for read-only inspection and Git/GitHub operations such as `git`, `gh`, `rg`, `sed`, `cat`, and similar repository reads.
- Only fall back to host execution for environment-sensitive commands when the environment check fails. If you do, say so explicitly in your summary.

## Implementation Delivery (MANDATORY)

- When the user explicitly requests implementation, default to completing the full delivery loop: make the change, run the required checks, commit, open the PR, watch CI, and merge after required checks pass.
- Use the repo workflow while doing that: keep issue linkage accurate, use the repo-native PR body format, and move the linked issue through `Review` and `Done` at the appropriate stages.
  - `pm move <num> Review` when a PR is opened
  - `pm move <num> Done` when the PR is merged
  - `pm status` to check the current board state
  - `pm add <num>` to add new issues to tracking
- Do not stop after local edits or after opening the PR unless the user explicitly asks you to pause, leave the PR open, or switch back to critique-only mode.
- Review tasks remain comment-only by default. Do **not** merge review PRs unless the user explicitly asks for it in that same request.

## Review Execution Checklist (MANDATORY)

When asked to review a PR:

1. Read the PR and linked issue.
2. Decide the outcome:
   - **Approve** -- post approval with a short summary + tests.
   - **Changes requested** -- post review comments in Finding/Impact/Fix/Verification format.
3. Post a matching summary comment on the linked issue.
4. Do **not** merge the PR and do **not** move issue/project status unless explicitly requested.
5. After the review comments are posted, summarize in chat.

Always leave feedback on the PR first. Don't dump review notes only in chat.

## What to Check (MANDATORY)

1. **Does the code do what the issue/PR claims?** Trace each acceptance criterion to actual implementation.
2. **What happens on failure?** Network errors, missing data, null values, empty arrays.
3. **What happens on first run?** No cache, no prior state, fresh environment.
4. **Are there silent removals?** Compare with the base branch if modifying existing files.
5. **Is the scope clean?** One concern per PR. Flag unrelated changes.

## PR Review Comment Style (MANDATORY)

When leaving a PR review comment:

- Write **one** clean review comment (avoid multiple partial comments).
- Use this structure so it's readable and actionable:

```
## Code Review: PR #<num> (Issue #<num>)

### Overall Assessment
<1-3 sentences>

### Strengths
- <bullet>
- <bullet>

### Areas for Improvement
#### 1) <short title>
- Impact:
- Fix:
- Verify:
```

- Be specific and reference the code paths you reviewed.
- If earlier comments exist, say the new comment supersedes them.
- Read existing review comments on the PR and respond naturally:
  - Acknowledge strong points you agree with.
  - Call out any disagreements or missing context.
  - Avoid duplicating feedback; add incremental value.

## PR Summary Style (MANDATORY)

When authoring PR descriptions, follow this pattern:

```
## Summary
<1-2 sentence summary of intent and outcome>

**Changes:**
- <concrete change>
- <concrete change>

## Why
<1-2 sentences of context/intent>

## Test plan
<commands run> OR "Not run (docs/script-only change)."
```

Notes:

- Keep it short, concrete, and repo-native.
- Do not delete or rewrite the PR template; only fill the relevant sections.

## Review Loop Output Protocol

Review instructions are provided inline in each Codex invocation prompt.
This section defines only the output format tokens for automated parsing.

### Risk Acceptance Independence

If the plan or PR description marks something as "acceptable residual risk," treat that as a claim requiring independent verification, not a settled decision. The reviewer MUST evaluate the risk independently.

### Output Format

**Finding categories:** `BLOCKING` (must fix) | `SUGGESTION` (improvement)

**Verdict (required, exact format for automated gate):**

- `VERDICT: APPROVED` -- all tests pass, no BLOCKING findings, code quality acceptable
- `VERDICT: BLOCKED -- <summary>` -- reference specific failing tests or BLOCKING findings

**Test conventions:** Discover existing test conventions from the codebase rather than imposing external patterns.

### BLOCKING Severity: Instance Verification

Before classifying a theoretical edge case or hypothetical input pattern as `BLOCKING`, the reviewer MUST verify that the pattern actually exists in the codebase:

1. **Search** the relevant surfaces touched by the change (changed files, callers, tests) for concrete instances of the problematic pattern. This is a targeted search of relevant surfaces, not an exhaustive scan of the entire repository.
2. **If real instances exist** (or the code path is provably reachable) -- classify as `BLOCKING`
3. **If zero instances exist** across all checked surfaces -- classify as `SUGGESTION`, not `BLOCKING`

A `BLOCKING` finding represents an actual risk in the current codebase, not a theoretical one. Hypothetical inputs that no caller produces and no test exercises are `SUGGESTION`-level. This rule targets theoretical edge cases and hypothetical input patterns -- it does NOT apply to ordinary correctness bugs, which follow normal severity classification.

## Ledger Awareness (MANDATORY)

Before raising findings in a review session, check for an existing review ledger:

- **Review ledger path:** `docs/ledgers/review/<issue_number>.json`
- **Plan ledger path:** `docs/ledgers/plan/<issue_number>.json`

### Review Sessions

If a review ledger exists for the issue being reviewed:

1. Read the ledger file before starting the review.
2. Do NOT re-raise findings with status `justified` or `withdrawn`. These have been resolved with evidence -- accept the disposition unless you have NEW counter-evidence not already addressed.
3. For findings with status `fixed`, verify the fix is present in the current code (via `git diff` or reading the file at the cited location). Only re-raise a fixed finding if the current code reintroduces the defect or the fix is absent.
4. For findings with status `open`, these are active and can be addressed or commented on.
5. Only raise NEW findings that do not duplicate any existing ledger entry (regardless of status).

### Collaborative Planning Sessions

If a plan ledger exists for the issue being planned:

1. Read the ledger file before suggesting changes.
2. Do NOT re-raise proposals with status `accepted` or `rejected`. These have been resolved.
3. Only suggest NEW changes not already covered by existing ledger entries.

### When No Ledger Exists

If no ledger file exists at the expected path, proceed normally -- this means no prior findings have been recorded for this issue.

## Plan Writing Principles

When writing implementation plans:

1. **Read the issue first** -- understand acceptance criteria and non-goals
2. **Explore the codebase** -- find relevant files, understand existing patterns
3. **Be specific** -- name files, functions, and line numbers
4. **Surface ambiguities** -- if the spec is unclear, call it out
5. **Consider edge cases** -- what could go wrong?

## General Principles

- Follow existing code patterns and conventions
- Prefer explicit errors over silent fallbacks
- One concern per PR -- flag scope mixing
- Read all comments on issues (they often contain corrections)

## CI References

- CI workflow: `.github/workflows/ci.yml`
- Test guidance: project-specific testing docs (e.g., `docs/TESTING.md`, `docs/development/TESTING.md`)

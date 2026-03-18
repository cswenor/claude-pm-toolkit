# PR Review Guide

This guide defines how PRs are reviewed in projects managed by the claude-pm-toolkit. It complements `docs/PM_PLAYBOOK.md` and `CLAUDE.md`.

## Review Principles

1. **Correctness first** — Verify logic, edge cases, and error handling.
2. **No silent failures** — All failure paths must be explicit and typed.
3. **Security awareness** — Any changes touching authentication, authorization, secrets, or data validation require security review and strong tests.
4. **Traceability** — Tier 1 changes must link to issues and follow the workflow in `CLAUDE.md`.
5. **Minimal risk** — Prefer small, focused changes with clear intent.

## Required Review Checks

### All PRs

- Diff scope is tight and matches the PR title.
- No fallback code or silent error handling.
- Error paths include context (operation + identifiers).
- Tests are updated for new behavior.
- README/docs updated if behavior or usage changes.

### Infrastructure / Config

- No unbounded loops or unbounded state growth.
- Access control is explicit for all state-changing operations.
- Schema or migration changes include clear rollout notes.
- Environment variable changes are documented.

### API / Services

- Type safety is preserved (no new `any`, no ignored errors).
- Network boundaries are explicit; failures are surfaced.
- Authentication and authorization checks are present on all endpoints.
- Rate limiting and input validation are considered.

### Frontend / Clients

- Type safety is preserved (no new `any`, no ignored errors).
- Network boundaries are explicit; failures are surfaced.
- User-facing error messages are clear and actionable.

## Test Expectations

- Run relevant package tests for the change.
- If behavior changes, add or update tests to lock it in.
- For high-risk changes, add a targeted regression test.

## Risk Flags (call out in review)

- Silent error handling or "best effort" behavior.
- Security-sensitive changes without security review.
- Schema or migration changes without clear rollout notes.
- New external dependencies or API contracts.
- Behavior changes without test coverage.
- Changes to shared utilities with broad impact.
- Files with high knowledge risk (single-author ownership).

## Review Output Format

Use this structure in review comments:

- **Finding:** What is wrong and why it matters.
- **Impact:** User, security, or operational risk.
- **Fix:** Concrete change needed.
- **Verification:** How to test or prove the fix.

## Toolkit Review Calibration Tools

The PM Intelligence MCP server provides tools to make reviews data-driven and improve over time.

### Pre-Review Intelligence

| Tool | Purpose |
| ---- | ------- |
| `review_pr` | Structured PR analysis: file classification, scope check, acceptance criteria verification, risk assessment (secrets, knowledge risk, large files), quality signals, and verdict recommendation. Start every review here. |
| `analyze_pr_impact` | Blast radius analysis before merging. Shows dependency impact (what issues get unblocked), knowledge risk (bus factor for affected files), and cascading effects. Use to understand merge consequences. |
| `predict_rework` | Predicts probability that an issue will require rework. Analyzes historical rework patterns, development signals, and area-specific baselines. Run before moving to Review to catch high-risk PRs early. |
| `get_knowledge_risk` | Knowledge risk analysis for files in the PR. Identifies bus factor concerns and concentration of ownership. |
| `check_readiness` | Verifies an issue meets the quality bar before Review (acceptance criteria, tests, docs). |

### Post-Review Feedback Loop

| Tool | Purpose |
| ---- | ------- |
| `record_review_outcome` | Record the disposition of each review finding (accepted, dismissed, modified, deferred). Called after a review cycle completes. This data feeds calibration. |
| `get_review_calibration` | Analyze review finding history to calculate hit rates (accepted vs. dismissed), identify false positive patterns, and generate calibration data by finding type, severity, and area. Includes trend analysis and recommendations for adjusting review focus. |

### Calibration Workflow

1. **Before review:** Run `review_pr` and `predict_rework` to get structured analysis.
2. **During review:** Use `analyze_pr_impact` for changes with broad scope.
3. **After review:** Call `record_review_outcome` for each finding to log its disposition.
4. **Periodically:** Run `get_review_calibration` to identify patterns — which finding types have high hit rates vs. high false positive rates — and adjust review focus accordingly.

## Reference Links

- Workflow and commit rules: `CLAUDE.md`
- PM processes and tier classification: `docs/PM_PLAYBOOK.md`
- Instruction architecture: `docs/INSTRUCTION_ARCHITECTURE.md`

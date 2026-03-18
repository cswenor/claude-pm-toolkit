# Verification Checklist

> **This file is NOT loaded at runtime.** It exists for developer reference only — use it when testing or modifying the /issue skill to verify no regressions.

## Create Mode - New Issue

- [ ] `/issue` (no args) triggers Create Mode
- [ ] PM interview asks relevant questions (1-2 at a time)
- [ ] Duplicate scan runs before draft (at least 3 searches)
- [ ] Draft matches template structure
- [ ] Confirmation required before creation
- [ ] Priority reasoning shown with factor table after draft confirmation, before issue creation
- [ ] User given choice to accept or override recommended priority
- [ ] Selected priority (including overrides) is passed to pm add

## Create Mode - Update Existing

- [ ] Candidates shown with overlap explanation
- [ ] Diff preview shown
- [ ] Existing issue updated, not new created

## Create Mode - Merge

- [ ] Merge plan shown
- [ ] Canonical updated, duplicates closed with comment

## Execute Mode (MUST NOT DEGRADE)

**These behaviors from the original `/issue ####` command MUST be preserved:**

- [ ] `/issue <number>` triggers Execute Mode (not Create Mode)
- [ ] Gathers state in parallel: issue details, comments, project status, PR discovery
- [ ] Issue readiness check runs (offers upgrade, doesn't block)
- [ ] Blocker check gates progress if `blocked:*` labels present
- [ ] Mode detection uses all 12 rules in correct order
- [ ] Loads context based on area labels and keywords
- [ ] Loads external library docs via context7
- [ ] "Comment if Approach Differs" step runs for START/CONTINUE
- [ ] Briefing packet displays all required sections
- [ ] START mode: move to Active, run {{SETUP_COMMAND}} in background, enter plan mode with full detail
- [ ] CONTINUE mode: git sync, run {{SETUP_COMMAND}} in background, enter plan mode with full detail
- [ ] REVIEW mode: offers /pm-review or make changes
- [ ] APPROVED mode: shows merge instructions
- [ ] REWORK mode: moves to Active, syncs git, displays feedback and guardrails
- [ ] CLOSED mode: offers reopen instructions
- [ ] MISMATCH modes: detect and offer fixes for all 4 variants
- [ ] Handoff works from Create Mode to Execute Mode

## Discovered Work Handling

- [ ] When discovering work outside current scope, STOP before bundling
- [ ] Duplicate scan runs for discovered work (maybe issue already exists)
- [ ] Blocker relationship established when discovered work blocks current issue
- [ ] Comment posted on current issue explaining the blocker
- [ ] User offered choice: work on blocker first, continue anyway, or pause

## Worktree Support

- [ ] `/issue <num>` in START mode from main repo creates worktree at `../{{prefix}}-<num>/`
- [ ] Worktree setup prints shell exports for port offsets (via `--print-env`)
- [ ] If worktree already exists + tmux, spawns/focuses tmux window (not recreated)
- [ ] If worktree already exists + no tmux, user is directed there (not recreated)
- [ ] If already in correct worktree, proceeds normally without redirection
- [ ] If in wrong worktree + tmux, spawns worktree + window in background
- [ ] If in wrong worktree + no tmux, user is directed to correct location
- [ ] Broken worktree (stale metadata) is detected and fix offered
- [ ] Port isolation allows `{{DEV_COMMAND}}` in multiple worktrees simultaneously
- [ ] CONTINUE mode detects worktree and proceeds if in correct location

## Background Setup

- [ ] /issue <num> in START mode runs {{SETUP_COMMAND}} in background before plan mode
- [ ] /issue <num> in CONTINUE mode runs {{SETUP_COMMAND}} in background before plan mode
- [ ] Bash tool called with run_in_background: true (returns task_id within 2 seconds)
- [ ] TaskOutput called with block: false after ExitPlanMode to check result
- [ ] Completed setup: user told "Environment ready"
- [ ] Failed setup: user shown error output and told to run {{SETUP_COMMAND}} manually
- [ ] Still-running setup: user informed, not blocked
- [ ] Background setup only runs in correct worktree (not during worktree creation handoff)

## Portfolio Manager (tmux)

- [ ] `tmux-session.sh init` creates session `{{prefix}}` with `main` window
- [ ] `tmux-session.sh start <num> <branch>` creates worktree + window + state
- [ ] `tmux-session.sh list` shows all tracked issues with status
- [ ] `tmux-session.sh focus <num>` switches to correct window
- [ ] `tmux-session.sh stop <num>` closes window and updates state
- [ ] Hooks fire and update `~/.{{prefix}}/portfolio/<num>/status`
- [ ] `portfolio-notify.sh` is a no-op when `{{PREFIX}}_ISSUE_NUM` not set
- [ ] tmux bell triggers on `needs-input` events — window shows alert indicator in status bar
- [ ] `/issue <num>` in START mode + tmux spawns background window instead of stopping
- [ ] `/issue <num>` in START mode without tmux uses existing fallback behavior

## Codex Review Loops

### Collaborative Planning

- [ ] `codex --version` check in Step 1e (parallel)
- [ ] Graceful skip when codex unavailable (notice shown, not silent)
- [ ] Collaborative Planning fires inside plan mode, BEFORE ExitPlanMode, in START and CONTINUE
- [ ] Codex Plan B launches BEFORE Claude writes Plan A (ordering-based independence)
- [ ] Plan B written to `.codex-work/plan-<issue_num>-<prefix>.md` (gitignored)
- [ ] `-s workspace-write` ONLY for Plan B creation (Phase 1)
- [ ] `-s read-only` for collaborative planning iterative review (Phase 3)
- [ ] Plan Ledger tracks proposals across iterations (open/accepted/rejected)
- [ ] Convergence based on ledger (zero open items), not subjective "Codex agrees"
- [ ] No `--full-auto` in collaborative planning (would override read-only to workspace-write)
- [ ] Each Codex iteration is a fresh session — no resume
- [ ] `-o` flag always on `exec` level, BEFORE subcommands
- [ ] `set -o pipefail` on all `codex exec | tee` pipelines
- [ ] Claude prompts Codex with what was incorporated and what wasn't (with reasons)
- [ ] Convergence when Codex agrees — no user arbitration
- [ ] 3-iteration checkpoint with user choice (continue / accept Claude's / use Codex's / show output)
- [ ] On exec failure: error context surfaced, explicit user choice required (Retry/Claude-only/Show error)
- [ ] Never auto-skip on failure (no-fallback compliance)
- [ ] Stderr captured to file on original invocation (`2>/tmp/codex-collab-stderr-<num>.txt`), never via rerun
- [ ] Phase 3 iterations use per-iteration output files (`-<issue_num>-${COLLAB_ITER}.txt`)
- [ ] Phase 3 iterations capture stderr to per-iteration files (NOT `2>/dev/null`)
- [ ] No write-capable (`-s workspace-write`) rerun in error paths
- [ ] User can override at any iteration
- [ ] 0-byte output file detected as failure (context exhaustion)
- [ ] Structural convergence detection (Codex proposes no concrete file/section modifications)
- [ ] Artifact cleanup runs after convergence or user override (Plan B + temp files deleted)

### Behavioral Verification (START/CONTINUE flow)

- [ ] START mode step 4: AskUserQuestion fires BEFORE Plan A is written (step 5)
- [ ] START mode step 4 "Skip": step 6 (refinement) is skipped, flow goes directly to step 7 (ExitPlanMode)
- [ ] START mode step 4 "Yes": Phase 1 runs, Plan B exists on disk before Plan A is written
- [ ] CONTINUE mode step 5: same AskUserQuestion fires BEFORE Plan A is written (step 6)
- [ ] CONTINUE mode step 5 → step 7 → step 8: same flow as START 4 → 6 → 7
- [ ] `codex_available = false`: both START step 4 and CONTINUE step 5 display skip notice, no AskUserQuestion
- [ ] Plan A file does NOT exist on disk when Codex Plan B `codex exec` starts (ordering invariant)
- [ ] After convergence (Phase 3 Codex agrees): flow reaches ExitPlanMode with no further Codex calls
- [ ] After 3-iteration checkpoint "Accept Claude's plan": loop terminates, ExitPlanMode called
- [ ] After 3-iteration checkpoint "Use Codex's plan": Plan B content replaces Plan A in plan file

### Implementation Review

- [ ] Implementation review fires as parallel quality gate (with tests) in Post-Implementation
- [ ] `-s workspace-write` on all implementation review invocations (Codex can write tests/scripts)
- [ ] Uses `exec` with structured review prompt (NOT `review --base main`)
- [ ] Codex explores codebase freely (no pre-generated patch file)
- [ ] `resume "$CODEX_SESSION_ID"` for follow-ups (NOT `--last`)
- [ ] Per-iteration summary with weighted finding categories (Security/Correctness/Performance/Style)
- [ ] Per-iteration output files (`-<issue_num>-${ITER}.txt`) prevent collision
- [ ] Stderr captured per iteration (NOT discarded with `2>/dev/null`)
- [ ] Evidence requirement: findings must cite file:line or downgrade to advisory
- [ ] Codex outputs findings as JSON schema (verdict, findings[], summary)
- [ ] Prose fallback with warning if JSON parsing fails
- [ ] Review Ledger tracks findings across iterations (open/fixed/justified/withdrawn)
- [ ] Termination based on ledger (zero open blockers), not Codex verdict
- [ ] Claude self-identifies when resuming sessions
- [ ] Resume prompt includes review ledger path
- [ ] Resume loop supports two-way dialogue (questions + revisions)
- [ ] SUGGESTION findings addressed or justified (not just BLOCKING)
- [ ] Ledger preserved for /pm-review self-check step
- [ ] 5-iteration hard cap with user choice prevents infinite loops
- [ ] Risk-proportional depth: trivial (skip), small (single-pass), standard (full loop)
- [ ] Revisions re-submitted to Codex (Claude cannot self-certify)

## Post-Implementation Sequence

- [ ] Sequence enforced: tests → Codex review → commit → post-commit Codex → PR → /pm-review → AC gate → Review
- [ ] Tests run BEFORE Codex review (Codex only reviews mechanically-correct code)
- [ ] Commit happens AFTER Codex approval (clean history, no fixup commits)
- [ ] Codex review is MANDATORY when codex_available (no skip option, no AskUserQuestion)
- [ ] Dev Complete gate requires Codex VERDICT: APPROVED in JSONL when codex available
- [ ] Post-Dev Ready gate requires codex-impl-events JSONL with APPROVED when codex available
- [ ] Post-commit Codex review (Step 3.5) produces fresh evidence against committed code
- [ ] Claude MUST NOT self-certify, recommend override, or skip Codex review
- [ ] Tests run before PR creation (aligned with CLAUDE.md "Before Creating PR")
- [ ] No step can be skipped (each validates the previous)
- [ ] /pm-review runs as self-check after PR creation (analysis only)
- [ ] Only after /pm-review passes (or user override) does Claude move to Review
- [ ] START mode "After ExitPlanMode" references Post-Implementation Sequence
- [ ] CONTINUE mode "After ExitPlanMode" references Post-Implementation Sequence
- [ ] REWORK mode references Post-Implementation Sequence
- [ ] Code changes from /pm-review trigger full loop: tests → Codex → commit → post-commit
- [ ] Execution model documented (skill guidance vs Claude Code capabilities)
- [ ] Post-Implementation Sequence includes Precedence Note re: quality gates
- [ ] Suggestion handling is in Continue path (not before user choice) in both sub-playbooks
- [ ] AC Traceability Table present in plan and used during /pm-review verification

## Codex Review Enforcement (NON-NEGOTIABLE)

- [ ] Collaborative planning is mandatory when codex_available (no AskUserQuestion skip option)
- [ ] Phase Gate: Plan Complete requires collab evidence when codex_available
- [ ] Phase Gate: Dev Complete requires Codex VERDICT: APPROVED when codex_available
- [ ] Phase Gate: Post-Dev Ready requires JSONL evidence when codex_available
- [ ] Post-implementation Step 2 blocks commit without Codex approval
- [ ] Post-implementation Step 3.5 runs fresh post-commit verification
- [ ] Claude never recommends --skip-codex-gate or any bypass

## HoV Backport Features (v0.16.0)

### Mode-Conditional Doc Loading (1.1)

- [ ] START/CONTINUE/REWORK modes load full P0 (CLAUDE.md + PM_PLAYBOOK.md)
- [ ] REVIEW/APPROVED modes load only selected sections (## Workflow States, ## Commands, ## STOP CHECKS, ## PM CLI)
- [ ] CLOSED/MISMATCH modes skip P0 entirely
- [ ] No inline summaries — always reads from canonical source files

### Instance Verification Gate (1.2)

- [ ] Step 3.5 verifies each finding's cited code exists
- [ ] Unverified BLOCKING findings auto-downgrade to SUGGESTION
- [ ] Zero-instance theoretical findings → SUGGESTION
- [ ] `verified` field added to ledger findings
- [ ] Pattern labels assigned to each finding
- [ ] Pattern propagation searches ALL changed files after each fix
- [ ] 3+ instances in same class/module triggers autonomous refactor
- [ ] Evidence gate hardening: malformed JSON → fail-closed
- [ ] Suspicious empty APPROVED on large diff → warning

### AC Checkbox Gating (1.3)

- [ ] Step 4.5 in post-implementation checks all AC items
- [ ] Unchecked items block Review transition (with override option)
- [ ] Override path adds warning comment to issue
- [ ] "Check off completed" verifies items before marking

### Audit Skill (1.4)

- [ ] `/audit <num>` parses issue number and finds linked PR
- [ ] `/audit PR#<num>` parses PR number and finds linked issue
- [ ] Codex-reviewed-only gate checks 4 evidence sources
- [ ] LOCAL vs REMOTE mode detection based on branch alignment
- [ ] 8 audit checks evaluated independently
- [ ] Results posted to both PR (review comment) and issue (summary)
- [ ] Review outcome recorded via `record_review_outcome`

### Worktree REWORK Enforcement (1.5)

- [ ] REWORK mode runs worktree detection (Step 4.5)
- [ ] REVIEW mode does NOT run worktree detection
- [ ] REWORK "Continue addressing feedback" verifies worktree before `gh pr checkout`

### Evidence Gate Hardening (1.6)

- [ ] Collaborative planning: Plan B < 200 bytes → suspicious
- [ ] Collaborative planning: Missing completion markers → fail-closed
- [ ] Implementation review: Malformed JSON response → fail-closed
- [ ] Implementation review: Empty APPROVED on large diff → warning

### Structured Agent Payloads (2.3)

- [ ] Planner agent returns JSON with plan_file_path, collab_evidence, convergence_status, discovered_work
- [ ] Developer agent returns JSON with files_changed, test_results, codex_review_result, discovered_work
- [ ] Common Context Block includes Environment Context (branch, dirty, review_gate, codex_available)
- [ ] Post-return verification parses JSON first, falls back to prose with warning

### Release/Resume Tools (2.1)

- [ ] `pm release <num> <reason>` captures recovery context and moves to Ready
- [ ] `pm resume <num>` returns recovery context from most recent release
- [ ] MCP tools `release_work` and `resume_work` registered and functional

### Naming Convention (3.1)

- [ ] Issue titles validated against `<type>(<area>): <description>` format before creation
- [ ] Max 90 chars enforced
- [ ] Auto-correction applied for minor deviations

## Regression Prevention

**If any of these break, the skill has regressed:**

1. `/issue` (no args) user-invoked MUST display "Tell me what you want to change, fix, or build" as first output
2. `/issue` (no args) MUST NOT list existing issues before prompting user
3. `/issue 123` should NOT ask "what do you want to build?"
4. `/issue 123` should NOT run duplicate scan
5. `/issue 123` should display issue title, acceptance criteria, non-goals
6. `/issue 123` in START mode from main repo should create worktree (+ tmux window if in tmux, or direct user there if not)
7. `/issue 123` in START mode from correct worktree should move to Active, enter plan mode
8. Plan mode content should include acceptance criteria as checkboxes
9. Plan mode content should include non-goals as DO NOT items
10. Plan mode content should include scope boundary check
11. Discovered work during implementation triggers separate issue creation
12. `/issue 123` in REWORK mode → "Continue addressing feedback" should move to Active and sync git

# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0] - 2026-02-18

### Added
- `pm-post-merge.yml`: GitHub Actions workflow — auto-moves issues to Done when PRs merge with `Fixes #N`
- `pm-pr-check.yml`: GitHub Actions workflow — validates conventional commit format, issue link, workflow state, project board membership
- `install.sh`: Copies GitHub Actions workflow templates to target `.github/workflows/` with placeholder replacement
- `install.sh`: Displays PROJECT_WRITE_TOKEN setup instructions during install
- `validate.sh`: Optional file checks for `pm-post-merge.yml` and `pm-pr-check.yml`
- `docs/RESEARCH-DYNAMIC-INTELLIGENCE.md`: Research synthesis — MCP servers, memory, GitHub automation, competitive analysis, P0-P10 roadmap
- `pm-session-context.sh`: SessionStart hook — injects worktree context, recent decisions/outcomes, and cached board state at session start
- `pm-record.sh`: CLI utility for recording decisions (`decision`), outcomes (`outcome`), and board state (`board`) to `.claude/memory/` JSONL files
- `.claude/memory/`: Persistent memory directory for cross-session learning (decisions.jsonl, outcomes.jsonl, board-cache.json)
- `settings.json`: SessionStart hook configuration (5-second timeout, fires on all session types)
- `project-move.sh`: Auto-records outcome to `.claude/memory/outcomes.jsonl` on Done transition (linked PR, review rounds, area label)
- `tools/mcp/pm-intelligence/`: MCP server exposing project state as native tools and resources
  - **Tools:** `get_issue_status`, `get_board_summary`, `move_issue`, `get_velocity`, `record_decision`, `record_outcome`, `get_memory_insights`
  - **Resources:** `pm://board/overview`, `pm://memory/decisions`, `pm://memory/outcomes`, `pm://memory/insights`
  - Board health score (0-100) with stale item detection
  - Velocity metrics (7-day and 30-day windows, average days-to-merge)
  - Memory analytics (rework rate, review round patterns, area distribution)
- `install.sh`: MCP server copy with placeholder replacement in config, `.mcp.json` merge
- `validate.sh`: Optional file checks for MCP server sources and `.mcp.json`
- `templates/mcp.json`: MCP server registration template
- `pm-event-log.sh`: Structured JSONL event logger for all PM hooks (session_start, state_change, needs_input, error, etc.)
  - Auto-detects issue from env vars or worktree directory name
  - Writes to `.claude/memory/events.jsonl` with null-field omission
- `portfolio-notify.sh`: Event stream integration (logs all portfolio events non-blocking)
- `pm-session-context.sh`: Event stream integration (logs session_start with source metadata)
- `project-move.sh`: Event stream integration (logs state_change on workflow transitions)
- MCP `get_event_stream` tool: Query structured event stream with filters (limit, issueNumber, eventType)
- MCP `pm://events/recent` resource: Last 50 events from the event stream

## [0.4.0] - 2026-02-18

### Added
- `/issue` SKILL.md: Design Principles section documenting structure-over-behavior, evidence-over-opinion, parallel-over-sequential, risk-proportional-depth, one-concern-per-PR, fail-explicit
- `/issue` SKILL.md: Risk-proportional review depth (trivial/small/standard thresholds skip or simplify Codex review)
- `/issue` SKILL.md: Weighted finding categories for implementation review (Security 0.45, Correctness 0.35, Performance 0.15, Style 0.05)
- `/issue` SKILL.md: Evidence requirement — Codex review findings must cite `file:line` or are downgraded to advisory
- `/issue` SKILL.md: AC Traceability Table — mandatory plan section mapping acceptance criteria to implementation and test files
- `/issue` SKILL.md: Parallel quality gates — tests and Codex review run concurrently in Post-Implementation Sequence
- `/issue` SKILL.md: Plan Ledger — JSON file tracking proposals across collaborative planning iterations (open/accepted/rejected); prevents re-litigation of settled decisions
- `/issue` SKILL.md: Review Ledger — JSON file tracking findings across implementation review iterations (open/fixed/justified/withdrawn); ledger-based convergence replaces subjective "Codex agrees"
- `/issue` SKILL.md: JSON schema for Codex review output — structured findings with id, category, severity, file, line, description, suggestion; deterministic parsing replaces prose interpretation
- `/issue` SKILL.md: Artifact cleanup step — deletes Plan B files, temp files, and ledger files after completion
- `/issue` SKILL.md: 5-iteration hard cap on implementation review loop (prevents infinite loops)
- `/issue` SKILL.md: Per-iteration output/stderr/event files for both collaborative planning and implementation review
- `/pm-review` SKILL.md: Draft PR detection in Step 2 (warns and offers analysis-only for draft PRs)
- `/pm-review` SKILL.md: CI status check via `mcp__github__get_pull_request_status` in Step 4
- `/pm-review` SKILL.md: AC Traceability Table verification in Step 4
- `install.sh`: Auto-link project to repository via `gh project link` (shows project on repo page)
- `install.sh`: Auto-set project description and public visibility via GraphQL `updateProjectV2`
- `install.sh`: Project board URL shown in summary output
- `install.sh`: Board view setup instructions in post-install next steps (GitHub API doesn't support view creation)
- `install.sh`: Stack auto-detection — detects SvelteKit, Next.js, React, Vue, Python, Rust, Go, Solidity/Anchor and suggests area options
- `pm-dashboard.sh`: Health Score (0-100) — WIP compliance, rework pileup, review bottleneck, backlog bloat, config health
- `validate.sh`: Checks for decomposed sub-playbooks (7 files) and appendices (6 files) + VERIFICATION.md
- `/issue` SKILL.md: Context budget tracking — tiered loading (P0–P3) with skip rules based on issue weight (light/medium/heavy)
- `/issue` SKILL.md: Sub-Playbook Index and Appendix Index — file reference tables for on-demand loading
- `/issue` SKILL.md: VERIFICATION.md — developer reference checklist extracted from inline appendix
- `/issue` sub-playbooks: 7 extracted playbooks (duplicate-scan, update-existing, merge-consolidate, discovered-work, collaborative-planning, implementation-review, post-implementation)
- `/issue` appendices: 6 extracted files (templates, briefing-format, worktrees, priority, codex-reference, design-rationale)

### Changed
- `/issue` SKILL.md: Decomposed from 3,309-line monolith to 1,283-line router + 14 extracted files (~62% reduction in initial context load)
- `/issue` SKILL.md: Implementation review uses `exec -s workspace-write` — Codex can write tests and verification scripts to prove findings ("agents that prove, not guess")
- `/issue` SKILL.md: Implementation review uses `exec` with structured prompt instead of `review --base main` (fixes 0-byte output, flag exclusion, unreliable stdin issues)
- `/issue` SKILL.md: No pre-generated patch file — Codex explores codebase freely with full filesystem access
- `/issue` SKILL.md: Post-Implementation Sequence reduced from 6 steps to 5 (parallel quality gates merge Codex + tests)
- `/issue` SKILL.md: REWORK mode reordered — fetch review comments BEFORE mutating state (prevents state change on fetch failure)
- `/issue` SKILL.md: Collaborative planning Phase 3 captures stderr per iteration (was `2>/dev/null`)
- `/issue` SKILL.md: `allowed-tools` frontmatter now includes `Bash(git diff *)`
- `/pm-review` SKILL.md: `allowed-tools` frontmatter now includes `Bash(git rev-parse *)` and `mcp__github__get_pull_request_status`
- `/pm-review` SKILL.md: MERGE_AND_CHECKLIST git sync is now worktree-safe (fetch-only in worktrees vs checkout+pull in main repo)
- `README.md`: Rewritten with problem/solution framing, before/after comparison, collapsible troubleshooting

### Fixed
- `validate.sh`: False positive on pm.config.sh guard function — echo/printf lines with literal `{{placeholders}}` are no longer counted
- `install.sh`: `TEMP_FILES[@]` unbound variable with `set -u` when array is empty (fixed with `${TEMP_FILES[@]+"${TEMP_FILES[@]}"}`)
- `project-move.sh`: Same `TEMP_FILES[@]` unbound variable fix

## [0.3.1] - 2026-02-18

### Fixed
- `project-move.sh`: Use dynamic `DEFAULT_BRANCH` instead of hardcoded `origin/main` for fetch/rebase
- `validate.sh`: Replace `eval` with `printf -v` for safe config parsing (security hardening)
- `pm.config.sh`: Use idiomatic exit code capture instead of fragile `$?` checks
- `pm.config.sh`: Validate `PM_PROJECT_NUMBER` is numeric before passing to jq `--argjson`
- `tmux-session.sh`: Quote path variables in tmux `new-window` command string (spaces in paths)
- `install.sh`: Add EXIT trap for temp file cleanup (8 mktemp calls registered)
- `install.sh`/`setup.sh`: Log warning before falling back to `@me` for project creation
- `setup.sh`: Add prefix validation (2-10 lowercase alphanumeric) matching install.sh
- `setup.sh`: Remove dead `existing_value()` function
- `worktree-setup.sh`: Use `BASH_SOURCE[0]` instead of `$0` for symlink/sourcing portability
- `claude-secret-check-path.sh`: Only expand `~` and `~/...`, not `~user/...` form
- `project-add.sh`: Replace `seq` with C-style for loop (word-splitting, POSIX portability)
- `worktree-cleanup.sh`: Add main/master fallback for DEFAULT_BRANCH detection (consistent with project-move.sh)
- `codex-mcp-overrides.sh`: Replace unquoted for-in loops with while-read (word-splitting safety)
- `project-archive-done.sh`: Add early guard for unsubstituted `{{PREFIX}}` placeholders
- `install.sh`: Initialize `ORIGINAL_INSTALLED_AT` and `PREVIOUS_VERSION` before conditional assignment

### Changed
- All scripts: Standardized shebang to `#!/usr/bin/env bash` (11 scripts updated)
- `tmux-session.sh`: Replace fragile `shift || true` with explicit arg count check
- `claude-secret-bash-guard.sh`: Added documentation comment explaining fail-closed empty-command behavior
- `project-add.sh`: Use centralized `pm_validate_config` instead of duplicated auth/jq checks

## [0.3.0] - 2026-02-18

### Added
- `install.sh --update`: Workflow option validation (warns on missing Backlog/Ready/Active/Review/Rework/Done options)
- `install.sh --update`: Field/option counting summary shows discovered vs missing items
- `install.sh --update`: Project ID change detection
- `install.sh --update`: Separate `updated_at` timestamp in metadata (preserves `installed_at`)
- `validate.sh`: Quick inline validation in `pm-validate` Makefile target (file presence + placeholder check)
- `install.sh`: EXIT trap for temp file cleanup (8 mktemp calls registered)
- `project-move.sh`: EXIT trap for temp file cleanup (prevents leak on early exit)
- `worktree-setup.sh`: Numeric validation for issue number
- `worktree-setup.sh`: Port offset bounds validation (3200-11000 range)
- `claude-secret-check-path.sh`: Regex validation for custom patterns from `secret-paths.conf`
- `claude-secret-detect.sh`: Comprehensive grep exit code handling for pattern validation

### Fixed
- `uninstall.sh`: Replaced python3 with jq for hook removal (fewer dependencies)
- `uninstall.sh`: Added EXIT trap for temp file cleanup
- `project-move.sh`: Temp file leak on early exit due to `set -e`
- `makefile-targets.mk`: `pm-validate` now performs actual validation, not just dashboard

### Changed
- CI: Replaced python3 with jq for `secret-patterns.json` validation
- CI: Added `uninstall.sh` to ShellCheck linting
- CI: Expanded install-test job (--help checks, template/permission/skill verification)
- `setup.sh`: Strengthened deprecation notice (WARNING + 3s delay + Ctrl-C hint)
- `claude-command-guard.sh`: Added documentation comment explaining fail-open vs fail-closed design
- `makefile-targets.mk`: Standardized help text (removed duplicate comments above targets)

## [0.2.0] - 2026-02-18

### Added
- Config-driven command guard (`tools/config/command-guard.conf`)
- Custom secret path patterns (`tools/config/secret-paths.conf`)
- Secret token pattern detection (`tools/config/secret-patterns.json`)
- Path sensitivity checker (`claude-secret-check-path.sh`)
- MIT License
- CONTRIBUTING.md
- Weekly report directory scaffolding

### Fixed
- `project-add.sh`: AREA_ID unbound variable with `set -u`
- `project-move.sh`: Docker cleanup no longer assumes Make targets exist
- `project-archive-done.sh`: Added user query fallback for personal GitHub accounts
- `project-status.sh`: Fixed `$?` dead code after `set -e`
- `pm.config.sh`: Fixed empty-string check, added cross-platform jq hints
- `install.sh`: Fixed awk sentinel replacement (newline in string error)
- `install.sh`: Unresolved `{{OPT_*}}` placeholders now cleaned up automatically

### Changed
- `claude-command-guard.sh` reads patterns from config file instead of hardcoded variables
- All scripts use `|| {}` pattern instead of `$?` check after `set -e`
- Area labels genericized (no project-specific defaults)
- PM_PLAYBOOK.md project references parameterized

## [0.1.0] - 2026-02-18

### Added
- Initial extraction from house-of-voi-monorepo
- `/issue` skill — full issue lifecycle management
- `/pm-review` skill — adversarial PM reviewer
- `/weekly` skill — AI narrative analysis
- `install.sh` with fresh install and `--update` modes
- `setup.sh` for template-based new repos
- `validate.sh` for installation verification
- GitHub Projects v2 field auto-discovery
- Git worktree management with port isolation
- tmux portfolio manager
- Security hooks (command guard, secret detection)
- `PM_PLAYBOOK.md` and `PM_PROJECT_CONFIG.md`
- 41-placeholder parameterization system

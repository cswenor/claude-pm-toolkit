# Changelog

All notable changes to this project will be documented in this file.

## [0.12.0] - 2026-02-19

### Added
- **Operational Intelligence:**
  - MCP `suggest_next_issue` tool: "What should I work on next?" recommendation engine. Scores all unblocked Ready/Backlog issues by priority weight (+30 critical, +20 high), dependency value (issues that unblock others rank higher), bottleneck bonus, rework risk, estimated completion time (quick wins score higher), and workflow readiness. Returns top recommendation with score breakdown and reasoning, up to 3 alternatives, and context (total candidates, active count, blocked count). Integrates predictions from `predict_completion` and `predict_rework` for each candidate.
  - MCP `generate_standup` tool: auto-generates daily standup reports from project activity. Sections: Completed (issues that moved to Done in lookback window), In Progress (active issues with days-since-active and last event), Blocked (issues with unresolved dependency blockers), Upcoming (ready issues ranked by priority and unblocked status). Includes velocity metrics (7-day merge/close rates), WIP count, and workflow health score. Configurable lookback window (default 24 hours).
  - MCP `generate_retro` tool: data-driven sprint retrospective. Analyzes velocity trends, rework patterns, bottlenecks, cycle times, flow efficiency, dependency health, and team capacity to produce structured What Went Well / What Could Improve / Action Items. Each observation backed by quantitative evidence. Identifies patterns: top rework reasons, bottleneck states, busy areas, peak activity hours. Action items prioritized by impact with area tags. Includes highlights and a natural-language summary.
- `validate.sh`: Added check for operations.ts
- **Explanatory Intelligence:**
  - MCP `explain_delay` tool: "Why is issue #X taking so long?" root cause analysis. Examines dependency chains (unresolved blockers, deep upstream chains), rework cycles (count and reasons), bottleneck states (avg hours per state), completion risk signals, rework probability signals, and capacity constraints (time waiting in Backlog/Ready). Builds a chronological timeline from event stream. Returns prioritized delay factors sorted by severity (critical → low), each with category, evidence, estimated days contributed, and actionable suggestion. Calculates active vs wait time split.
  - MCP `compare_estimates` tool: prediction accuracy tracking across completed issues. Compares `predict_completion` P50/P80/P95 forecasts against actual cycle times and `predict_rework` probability against actual rework occurrence. Calculates calibration metrics: P50/P80/P95 hit rates (should be ~50%/80%/95%), average overrun percentage, and systematic bias detection (optimistic = predictions too low, calibrated = predictions accurate, pessimistic = predictions too high). Identifies area-specific estimation blind spots and recommends which confidence level to use for commitments.
- `validate.sh`: Added check for explain.ts
- **Anomaly Detection:**
  - MCP `detect_patterns` tool: cross-cutting early warning system that surfaces unusual patterns across the entire project. Scans 11 data sources in parallel and checks for: velocity drops (7d vs 30d comparison), backlog growth (creation outpacing closure), rework trends (rate and worsening trajectory), DORA change failure rate, process violations (WIP limit, stale items, review bottleneck, low flow efficiency), dependency issues (cycles, critical bottlenecks, orphaned blocked), capacity risks (decelerating contributors, bus factor 1 areas), and knowledge decay (critical risk files, decay alerts). Each anomaly includes category, severity, trend direction (worsening/new/stable/improving), evidence, affected issues, and suggested action. Returns a health snapshot and natural-language summary. The "things you should know about" early warning system.
- `validate.sh`: Added check for anomaly.ts

## [0.11.0] - 2026-02-19

### Added
- **Project Health Dashboard:**
  - MCP `get_project_dashboard` tool: comprehensive project health report that synthesizes ALL intelligence modules into one view. Gathers board state, velocity, DORA metrics, workflow health, dependency graph, team capacity, Monte Carlo simulation, and memory insights in parallel (9 concurrent queries). Returns: overall health score (0-100) computed as weighted average across 7 dimensions (velocity 20%, workflow 20%, DORA 15%, dependencies 15%, capacity 15%, knowledge risk 10%, learning 5%). Output is a formatted markdown report with: health signal table, board snapshot with active/stale items, velocity comparison table, dependency summary with critical path and bottlenecks, team capacity forecast, Monte Carlo throughput histogram, DORA metrics table, and top 5 prioritized recommendations. The "how is my project doing?" single call.
- **Dependency Visualization:**
  - MCP `visualize_dependencies` tool: renders the issue dependency graph as human-readable ASCII art and Mermaid diagrams. Two modes: (1) Full graph — tree-style dependency rendering with critical path highlight, bottleneck summary, cycle warnings, orphaned blocked issues, and network metrics. (2) Single issue — focused upstream/downstream view showing blockers (with resolution status), dependents, chain visualization, and execution order. ASCII output uses status indicators: `[x]` Done, `[>]` Active, `[?]` Review, `[!]` Rework, `[ ]` Ready, `[-]` Backlog. Mermaid output produces color-coded flowcharts (green=Done, blue=Active, yellow=Review, gray=Ready, dashed=Backlog) with resolved dependencies as dotted lines and critical path edges highlighted in red. Renders natively in GitHub PRs/issues, Notion, and Obsidian.
- `validate.sh`: Added checks for visualize.ts and dashboard.ts

## [0.10.0] - 2026-02-19

### Added
- **Sprint Planning Assistant:**
  - MCP `plan_sprint` tool: AI-powered sprint planning that combines all intelligence modules into actionable recommendations. Gathers dependency graph, team capacity, Monte Carlo simulation, and backlog state in parallel. Scores issues by priority weight, workflow state, blocking bonus (items that unblock others get priority), blocked penalty, and estimate factor. Returns: ordered recommended items with suggested assignees and prerequisites, stretch goals (up to 30% over capacity), deferred items with reasons, carry-over from in-progress work, Monte Carlo confidence intervals (all-items and top-priority probability), capacity summary with area coverage, dependency warnings (cycles, orphaned blocked, critical bottlenecks), and actionable recommendations. The "killer feature" that ties all intelligence together for sprint planning and commitment decisions.
- `validate.sh`: Added check for planner.ts

## [0.9.0] - 2026-02-19

### Added
- **Dependency Graph Analysis:**
  - MCP `analyze_dependency_graph` tool: builds a directed acyclic graph from issue relationships (blocked-by labels, cross-references, "Blocks #X"/"Blocked by #X" body/comment markers). Returns critical path (longest unresolved dependency chain), bottleneck issues (with transitive dependent counts and severity ratings), cycle detection, orphaned blocked issues (all blockers resolved but still marked blocked), and network metrics (max depth, density, connected components, largest component). Parses multiple relationship patterns: "## Blocks" sections, "**Blocker:** #X" inline markers, and structured "## Dependencies" sections.
  - MCP `get_issue_dependencies` tool: full dependency analysis for a single issue — direct blockers with resolution status, direct blocks, transitive upstream chain, transitive downstream chain, unblocked status check, and execution order position. Use to evaluate if an issue is ready to work on or understand its blast radius.
- **Team Capacity Modeling:**
  - MCP `get_team_capacity` tool: multi-contributor throughput analysis from git/GitHub history. Builds individual contributor profiles (merge velocity, areas, active days, lines per PR, velocity trend), calculates team-wide metrics (parallelism factor, combined throughput, avg merge time), forecasts sprint capacity (pessimistic/expected/optimistic with risk factors and opportunities), maps area coverage with bus factor per area, and generates actionable recommendations. Identifies accelerating/decelerating contributors, inactive contributors, and review bottlenecks.
- `validate.sh`: Added checks for graph.ts and capacity.ts

## [0.8.0] - 2026-02-19

### Added
- **Monte Carlo Simulation:**
  - MCP `simulate_sprint` tool: probabilistic sprint throughput forecasting via Monte Carlo simulation (10,000 trials default). Answers "how many items will we finish in N days?" with P10-P90 throughput percentiles, completion probability for target item count, confidence levels, histogram distribution, and data quality assessment. Uses bootstrap sampling from historical cycle time distributions.
  - MCP `forecast_backlog` tool: "when will we finish N items?" with P50/P80/P95 completion dates, sprint-by-sprint breakdown (cumulative progress, remaining items, per-sprint probability of completion), risk analysis (tail risk, variability ratio), and automatic synthetic fallback when historical data is insufficient.
  - Core simulation engine: WIP-aware sequential processing (default WIP=1 per PM policy), 0.25-day resolution, 50,000 trial cap, area-filtered cycle times with automatic all-area fallback
  - Synthetic distribution generation when fewer than 3 historical cycle times exist (3-7 day uniform, clearly warned)
- **Runtime Guardrails:**
  - MCP `detect_scope_creep` tool: compares implementation plan to actual file changes in the working tree. Extracts planned files from plan content (backtick paths, bullet lists, file sections), diffs against git changes (staged, unstaged, branch vs main), calculates scope creep ratio, flags infrastructure/dependency drift patterns, and recommends when to trigger Discovered Work sub-playbook
  - MCP `get_context_efficiency` tool: per-issue AI context efficiency metrics — session count, rework cycles, needs-input frequency, error rate, time-in-state analysis, session gap detection, and overall efficiency score (0-100). Identifies context waste patterns and generates specific recommendations
  - MCP `get_workflow_health` tool: cross-issue portfolio health — per-issue health scores, stale issue detection (state-aware thresholds), bottleneck identification (which workflow state has the most stuck items), and systemic pattern analysis
- `validate.sh`: Added checks for simulate.ts and guardrails.ts

## [0.7.0] - 2026-02-19

### Added
- **Predictive Intelligence:**
  - MCP `predict_completion` tool: P50/P80/P95 completion date predictions with risk scoring (0-100), confidence levels, similar issue comparison, and state-adjusted estimates
  - MCP `predict_rework` tool: rework probability prediction with weighted signal analysis (rework history, rushed pace, missing decisions, area baseline), risk levels, and specific mitigations
  - MCP `get_dora_metrics` tool: automated DORA metrics — deployment frequency, lead time for changes, change failure rate, mean time to restore — rated against industry benchmarks (elite/high/medium/low)
  - MCP `get_knowledge_risk` tool: bus factor analysis, knowledge decay detection, per-file risk scoring (single contributor + high churn = critical), area-level aggregation, and decay alerts for stale files
- **Review Learning:**
  - MCP `record_review_outcome` tool: track review finding dispositions (accepted/dismissed/modified/deferred) to close the feedback loop
  - MCP `get_review_calibration` tool: hit rate analysis by finding type/severity/area, false positive pattern detection, trend analysis (improving/stable/declining), calibration recommendations
  - MCP `check_decision_decay` tool: detects stale architectural decisions based on age, file churn, potential supersession, and area activity — returns decay score (0-100) with review recommendations
- MCP `pm://analytics/dora` resource: DORA metrics as a resource
- `validate.sh`: Added checks for predict.ts and review-learning.ts

## [0.6.0] - 2026-02-19

### Added
- MCP `get_sprint_analytics` tool: deep sprint analytics with cycle time (avg/median/p90), time-in-state, bottleneck detection, flow efficiency, rework analysis, session patterns, and velocity/rework trend comparison
- MCP `suggest_approach` tool: queries past decisions and outcomes to suggest approaches for new work based on area and keywords, with warnings about common rework reasons
- MCP `check_readiness` tool: pre-review validation checking event stream for proper workflow (Active transition, sessions, rework addressed, decisions documented) with 0-100 readiness score
- MCP `get_history_insights` tool: git history mining for file change hotspots, coupling analysis (files that always change together), commit patterns, PR size patterns, and risk area identification
- MCP `pm://analytics/sprint` resource: current sprint analytics as a resource
- `pm-commit-guard.sh`: PreToolUse:Bash hook that validates conventional commit format, auto-fixes missing colons (e.g., `feat add` → `feat: add`) via `updatedInput`, and suggests type prefixes for untyped messages
- `pm-stop-guard.sh`: Stop hook that detects incomplete work (uncommitted changes, unpushed commits, issue still Active, no PR) and injects reminders as additionalContext
- `settings.json`: Added pm-commit-guard.sh to PreToolUse:Bash hooks, pm-stop-guard.sh to Stop hooks

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

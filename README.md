# Claude PM Toolkit

**Stop Claude Code from winging it.**

Claude Code is powerful — but without structure, it creates duplicate issues, bundles unrelated work into unmergeable PRs, rubber-stamps reviews, loses context between sessions, and ignores workflow discipline.

This toolkit gives Claude a PM brain: structured workflows, adversarial reviews, parallel development, and persistent memory — all backed by a local-first SQLite database that syncs with GitHub.

**Install into any existing repo in 2 minutes. No framework dependencies.**

```bash
git clone https://github.com/cswenor/claude-pm-toolkit.git
cd claude-pm-toolkit
./install.sh /path/to/your/repo
```

---

## Before & After

| Without Toolkit | With Toolkit |
|----------------|-------------|
| Claude creates 3 partial issues for the same problem | Duplicate scan catches it before creation |
| Feature PR includes surprise Docker upgrade | Scope discipline creates separate issue + blocker |
| "LGTM" review misses unhandled edge cases | Adversarial review with mandatory failure mode analysis |
| Context lost between sessions — starts over | `/issue 42` loads full state: issue, comments, PR, plan |
| Workflow state drifts and nobody notices | Local DB enforces transitions with WIP limits |
| One issue at a time, serial development | Worktrees + tmux = parallel Claude sessions |
| No memory of past decisions or rework reasons | SQLite event stream tracks everything across sessions |

---

## What You Get

### Four Skills

| Skill | Purpose |
|-------|---------|
| **`/start`** | **Session kickoff.** Risk radar, session optimizer, standup generator, anomaly detection — full situational awareness in one command. |
| **`/issue`** | Full lifecycle. Create via PM interview with AI triage + auto-labeling. Execute with worktree isolation, plan mode with predictive intelligence, and scope creep detection. |
| **`/pm-review`** | Adversarial reviewer. Enriched with automated PR analysis, blast radius modeling, knowledge risk, rework prediction, and review calibration learning. |
| **`/weekly`** | AI narrative from weekly snapshots. Enhanced with risk radar, DORA metrics, Monte Carlo forecasts, anomaly detection, and delivery metrics. |

### MCP Server (pm-intelligence) — 49 Tools

A native MCP server that gives Claude direct access to project intelligence. All workflow state lives in a local SQLite database (`.pm/state.db`) that syncs from GitHub.

| Category | Tool | Description |
|----------|------|-------------|
| **Core** | `get_issue_status` | Workflow state, priority, labels from local DB |
| | `get_board_summary` | Full board with health score (0-100) and stale items |
| | `move_issue` | Transition issue with WIP limit enforcement |
| | `get_velocity` | Merge/close/open rates (7d and 30d windows) |
| | `sync_from_github` | Pull latest issues/PRs into local DB |
| | `add_dependency` | Create dependency edges with cycle detection |
| | `get_cycle_times` | Per-issue cycle time analytics from event stream |
| **Memory** | `record_decision` | Log architectural decisions to persistent DB |
| | `record_outcome` | Log work outcomes (merged, rework, etc.) |
| | `get_memory_insights` | Analytics: rework rate, review patterns, area distribution |
| | `get_event_stream` | Query structured event stream with filters |
| **Analytics** | `get_sprint_analytics` | Cycle time, bottlenecks, flow efficiency, trends |
| | `suggest_approach` | Query past work to suggest approaches for new issues |
| | `check_readiness` | Pre-review validation with readiness score (0-100) |
| | `get_history_insights` | Git history mining: hotspots, coupling, risk areas |
| **Prediction** | `predict_completion` | P50/P80/P95 completion dates with risk score (0-100) |
| | `predict_rework` | Rework probability with weighted signals and mitigations |
| | `get_dora_metrics` | DORA metrics rated against industry benchmarks |
| | `get_knowledge_risk` | Bus factor, knowledge decay, per-file risk scoring |
| **Simulation** | `simulate_sprint` | Monte Carlo sprint throughput (P10-P90, histogram) |
| | `forecast_backlog` | "When will we finish N items?" with sprint breakdown |
| **Guardrails** | `detect_scope_creep` | Compare plan to actual changes, flag drift |
| | `get_context_efficiency` | AI context waste metrics per issue (0-100 score) |
| | `get_workflow_health` | Cross-issue health, bottlenecks, stale detection |
| **Graph** | `analyze_dependency_graph` | Critical path, bottleneck issues, cycle detection |
| | `get_issue_dependencies` | Upstream/downstream chains, execution order |
| | `visualize_dependencies` | ASCII + Mermaid dependency graph rendering |
| **Capacity** | `get_team_capacity` | Contributor profiles, sprint forecast, area coverage |
| **Planning** | `plan_sprint` | AI-powered sprint planning combining all intelligence |
| **Dashboard** | `get_project_dashboard` | Full health report synthesizing all intelligence |
| **Operations** | `suggest_next_issue` | "What should I work on next?" ranked recommendations |
| | `generate_standup` | Auto-generated daily standup from project activity |
| | `generate_retro` | Data-driven sprint retrospective with evidence |
| **Explanatory** | `explain_delay` | "Why is this issue slow?" root cause analysis |
| | `compare_estimates` | Prediction accuracy and calibration tracking |
| **Anomaly** | `detect_patterns` | Early warning system for project anomalies |
| **Triage** | `triage_issue` | One-call issue classification, priority, risk, assignment |
| | `analyze_pr_impact` | Pre-merge dependency, knowledge, coupling analysis |
| | `decompose_issue` | AI-powered issue decomposition with execution order |
| **What-If** | `simulate_dependency_change` | "What if #X slips N days?" cascade modeling |
| **Release** | `generate_release_notes` | Automated release notes from merged PRs |
| **Session** | `optimize_session` | Context-aware session planning and prioritization |
| **Review** | `review_pr` | Structured PR analysis with scope, risk, verdict |
| | `auto_label` | Automatic issue classification with confidence scores |
| **Context** | `get_session_history` | Cross-session event history for an issue |
| | `recover_context` | Full context recovery ("pick up where you left off") |
| **Batch** | `bulk_triage` | Triage all untriaged issues in one call |
| | `bulk_move` | Move multiple issues between states (with dry-run) |
| **Risk** | `get_risk_radar` | Unified risk dashboard synthesizing all intelligence |
| **Learning** | `record_review_outcome` | Track review finding dispositions for calibration |
| | `get_review_calibration` | Hit rate analysis, false positive patterns, trends |
| | `check_decision_decay` | Detect stale decisions based on context drift |

Plus 7 MCP resources for direct context access: `pm://board/overview`, `pm://memory/*`, `pm://events/recent`, `pm://analytics/*`.

### CLI (`pm`)

Terminal commands for managing workflow state without Claude:

```bash
pm board                 # Color-coded kanban board
pm status 42             # Issue details and workflow state
pm move 42 Active        # Transition with WIP limit enforcement
pm sync                  # Pull latest from GitHub
pm add 42 high           # Create issue in local DB with priority
pm dep 42 --blocks 57    # Add dependency edge
pm history 42            # Event timeline for an issue
pm dashboard             # Full project health summary
```

### GitHub Actions (Automated)

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| **`pm-post-merge.yml`** | PR merged with `Fixes #N` | Moves issue to Done, posts completion comment |
| **`pm-pr-check.yml`** | PR opened/edited | Validates conventional commit, issue link, workflow state |

### How Intelligence Tools Get Used

Every tool is wired into the workflow — Claude calls them automatically at the right moments:

| Moment | What Fires | Tools Used |
|--------|-----------|------------|
| **Session start** | `/start` skill or SessionStart hook | `optimize_session`, `get_risk_radar`, `detect_patterns`, `generate_standup`, `get_workflow_health`, `check_decision_decay` |
| **Creating an issue** | `/issue` Create Mode Step 3 | `triage_issue`, `auto_label` |
| **Loading an issue** | `/issue` Execute Mode Step 1 | `recover_context`, `get_issue_dependencies` |
| **Planning work** | `/issue` START plan mode | `suggest_approach`, `predict_completion`, `predict_rework`, `get_history_insights`, `decompose_issue` |
| **Resuming work** | `/issue` CONTINUE mode | `recover_context`, `get_session_history` |
| **Before creating PR** | CLAUDE.md proactive rules | `check_readiness`, `detect_scope_creep` |
| **Reviewing a PR** | `/pm-review` Step 1 | `review_pr`, `analyze_pr_impact`, `predict_rework`, `get_knowledge_risk` |
| **After review** | `/pm-review` Step 7 | `record_review_outcome`, `record_outcome` |
| **After merging** | CLAUDE.md proactive rules | `record_outcome` |
| **Weekly reports** | `/weekly` Step 2.7 | `get_risk_radar`, `get_dora_metrics`, `detect_patterns`, `get_workflow_health`, `compare_estimates`, `generate_release_notes`, `forecast_backlog`, `simulate_sprint` |
| **Cleaning backlog** | `/start` triage action | `bulk_triage`, `bulk_move` |
| **Issue stuck** | CLAUDE.md proactive rules | `explain_delay` |
| **Design decisions** | CLAUDE.md proactive rules | `record_decision` |
| **Sprint planning** | On demand | `plan_sprint`, `simulate_sprint`, `get_team_capacity`, `visualize_dependencies` |
| **What-if analysis** | On demand | `simulate_dependency_change` |

---

## Quick Start

### Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) — authenticated
- [Node.js](https://nodejs.org) 18+ (for MCP server)
- [jq](https://jqlang.github.io/jq/)

### Install

```bash
./install.sh /path/to/your/repo
```

The installer:
1. Prompts for GitHub owner and repo name
2. **Auto-detects your stack** (React, Svelte, Next.js, Python, etc.) and suggests area options
3. Copies skills, scripts, hooks, and actions with all placeholders resolved
4. Installs the MCP server (`npm install && npm run build`)
5. Merges hooks into `.claude/settings.json`
6. Initializes the local database (`.pm/state.db`) on first sync

### First Run

After install, sync your GitHub data into the local DB:

```bash
cd /path/to/your/repo
pm sync        # or: Claude will auto-sync via MCP tool
```

### Update

```bash
cd claude-pm-toolkit && git pull
./install.sh --update /path/to/your/repo
```

Reads saved config, overwrites toolkit files, preserves your customizations.

### Validate

```bash
./validate.sh /path/to/your/repo            # Full validation suite
./validate.sh --fix /path/to/your/repo      # Auto-fix permissions, .gitignore
```

### Uninstall

```bash
./uninstall.sh /path/to/your/repo           # Dry run
./uninstall.sh --confirm /path/to/your/repo # Remove
```

---

## Daily Workflow

```bash
/start                 # Session briefing → risk radar → recommended work → standup
/start 30 frontend     # 30-minute session focused on frontend work
/issue                 # Create issue → PM interview → AI triage → duplicate scan
/issue 42              # Load context → intelligence recovery → detect state → plan mode
/pm-review 123         # Adversarial review with blast radius analysis and rework prediction
/weekly                # AI analysis with DORA metrics, risk dashboard, and forecasts
```

### Workflow States

| State | What Claude Can Do | Transitions |
|-------|--------------------|-------------|
| **Backlog** | Analyze only | → Ready |
| **Ready** | Plan only | → Active |
| **Active** | **Implement** (only state where coding is allowed) | → Review |
| **Review** | Wait for feedback | → Done or → Rework |
| **Rework** | Address feedback | → Review |
| **Done** | Nothing | Archive after 30 days |

**WIP limit:** Claude may have only 1 issue in Active at a time. Enforced at the database level.

### Parallel Development

Each issue gets its own worktree with isolated ports:

```
~/Development/
├── my-project/        # Main repo
├── app-42/            # Worktree for issue #42 (ports offset by +4200)
└── app-57/            # Worktree for issue #57 (ports offset by +5700)
```

### Portfolio Mode (tmux)

Run multiple Claude sessions simultaneously:

```bash
make claude            # Start tmux session
/issue 42              # Spawns background window
/issue 57              # Spawns another window
# Status bar shows alerts when a session needs input
```

---

## Architecture

### Local-First Design

The toolkit uses a **local-first architecture** where workflow state, priorities, dependencies, and analytics live in a SQLite database (`.pm/state.db`). GitHub remains the source of truth for issue content, PRs, and git — but lifecycle management happens locally.

```
GitHub (content)              Local SQLite (lifecycle)
─────────────────             ─────────────────────────
Issues → title, body,    ←── sync ──→  workflow state
         labels, comments                priority
PRs → diff, reviews,                    dependencies
       merge status                      event history
                                         decisions
                                         outcomes
                                         cycle times
```

**Why local-first?**

- **Speed:** No GraphQL queries for every state check. Board summary in <1ms.
- **Reliability:** No rate limits, no API lag, no field ID discovery.
- **Richer model:** Dependencies, cycle detection, event sourcing — things GitHub Projects can't do.
- **Works offline:** Full workflow management without network access.

### File Layout

```
.pm/
└── state.db                             # SQLite database (gitignored)
.claude-pm-toolkit.json                  # Install metadata (enables --update)
.github/workflows/
├── pm-post-merge.yml                    # Auto-move issues to Done on merge
└── pm-pr-check.yml                      # PR quality gate
.claude/
├── settings.json                        # Hooks: security guards, portfolio notifications
└── skills/
    ├── issue/SKILL.md                   # Full issue lifecycle skill
    ├── pm-review/SKILL.md               # Adversarial reviewer
    └── weekly/SKILL.md                  # Weekly analysis
docs/
├── PM_PLAYBOOK.md                       # Workflow definitions and rules
└── PM_PROJECT_CONFIG.md                 # Your project config (user-editable)
tools/
├── config/                              # User-editable security configs
│   ├── command-guard.conf
│   ├── secret-patterns.json
│   └── secret-paths.conf
├── scripts/                             # Shell scripts
│   ├── worktree-{setup,detect,cleanup}.sh
│   ├── tmux-session.sh
│   ├── portfolio-notify.sh
│   ├── find-plan.sh
│   └── claude-{command-guard,secret-*}.sh
└── mcp/
    └── pm-intelligence/                 # MCP server (TypeScript)
        ├── src/
        │   ├── index.ts                 # MCP tool definitions (49 tools)
        │   ├── db.ts                    # SQLite schema, workflow engine
        │   ├── sync.ts                  # GitHub sync adapter
        │   ├── cli.ts                   # Terminal CLI
        │   ├── config.ts               # Repo config
        │   ├── github.ts               # Git/GitHub operations
        │   ├── memory.ts               # Decision/outcome storage
        │   └── ...                      # 15+ intelligence modules
        ├── package.json
        └── build/                       # Compiled output (gitignored)
.mcp.json                                # MCP server registration
```

### How Updates Work

| Category | Examples | Install | Update |
|----------|---------|---------|--------|
| **Managed** | SKILL.md, scripts, PM_PLAYBOOK.md | Copied | Overwritten |
| **Workflows** | pm-post-merge.yml, pm-pr-check.yml | Copied | Overwritten |
| **User Config** | PM_PROJECT_CONFIG.md, *.conf | Copied | **Preserved** |
| **MCP Server** | pm-intelligence sources, .mcp.json | Copied + merged | Overwritten + merged |
| **Merged** | settings.json | Created | Hooks merged |
| **Sentinel** | CLAUDE.md PM sections | Appended | Block replaced |
| **Local State** | .pm/state.db | Created on sync | **Never touched** |

---

## Customization

### Project Config (`docs/PM_PROJECT_CONFIG.md`)

Your main customization file. Controls:

- **Area docs** — Maps `area:frontend` to your project's architecture docs
- **Keyword docs** — Maps issue keywords to relevant docs for context loading
- **Library docs** — Maps keywords to [context7](https://github.com/upstash/context7) library lookups
- **Port services** — Your dev server, database, etc. for worktree isolation
- **Review examples** — Domain-specific examples for `/pm-review`
- **Stakeholder context** — How to frame technical work for `/weekly` reports

### CLAUDE.md Integration

PM sections are wrapped in sentinel comments:

```html
<!-- claude-pm-toolkit:start -->
...PM workflow rules, stop checks, conventions...
<!-- claude-pm-toolkit:end -->
```

Updates replace only this block. Your custom content is never touched.

---

## Troubleshooting

<details>
<summary><code>Database not found</code></summary>

The local database is created on first sync:

```bash
pm sync     # Creates .pm/state.db and pulls from GitHub
```
</details>

<details>
<summary><code>MCP server not responding</code></summary>

```bash
cd tools/mcp/pm-intelligence && npm install && npm run build
```

Check `.mcp.json` points to the correct build path.
</details>

<details>
<summary>Worktree already exists</summary>

```bash
git worktree prune     # Clean up stale metadata
```
</details>

<details>
<summary>Port conflicts</summary>

```bash
lsof -i :5173          # Check what's using the port
# Override: WORKTREE_PORT_OFFSET=5000 ./tools/scripts/worktree-setup.sh 294 feat/my-feature
```
</details>

<details>
<summary>settings.json corrupted</summary>

```bash
jq empty .claude/settings.json        # Check validity
git checkout .claude/settings.json    # Restore
./install.sh --update /path/to/repo   # Re-merge hooks
```
</details>

<details>
<summary>tmux "portfolio session not found"</summary>

```bash
make claude    # Creates tmux session and launches Claude
```
</details>

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). The short version:

1. Fork + clone
2. Install to test repo: `./install.sh /path/to/test-repo`
3. Make changes, test with `./install.sh --update`
4. Validate: `./validate.sh /path/to/test-repo`
5. PR with what changed and why

## License

MIT. See [LICENSE](LICENSE).

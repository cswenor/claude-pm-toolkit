# Claude PM Toolkit

**Stop Claude Code from winging it.**

Claude Code is powerful — but without structure, it creates duplicate issues, bundles unrelated work into unmergeable PRs, rubber-stamps reviews, loses context between sessions, and leaves your project board in shambles.

This toolkit gives Claude a PM brain: structured workflows, adversarial reviews, parallel development, and portfolio management — all backed by GitHub Projects v2.

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
| Project board stuck in "Review" for weeks | Auto-transitions: Active → Review → Done |
| One issue at a time, serial development | Worktrees + tmux = parallel Claude sessions |

---

## What You Get

### Three Skills

| Skill | Purpose |
|-------|---------|
| **`/issue`** | Full lifecycle. Create via PM interview with duplicate detection. Execute with worktree isolation, plan mode, Codex collaboration, and post-implementation review. |
| **`/pm-review`** | Adversarial reviewer. Scope verification, failure mode analysis, comment skepticism, deep code comparison, split completeness/robustness verdict. |
| **`/weekly`** | AI narrative from weekly snapshots. Stakeholder-ready summaries, health scores, trend analysis. |

### 22 Scripts

| Category | Scripts | Purpose |
|----------|---------|---------|
| **Project** | `project-add.sh`, `project-move.sh`, `project-status.sh`, `project-archive-done.sh` | GitHub Projects v2 integration |
| **Worktrees** | `worktree-setup.sh`, `worktree-detect.sh`, `worktree-cleanup.sh` | Parallel development with port isolation |
| **Portfolio** | `tmux-session.sh`, `portfolio-notify.sh` | Multi-session management with tmux alerts |
| **Security** | `claude-command-guard.sh`, `claude-secret-*.sh` | Block dangerous commands, detect secrets |
| **Smart Hooks** | `pm-commit-guard.sh`, `pm-stop-guard.sh`, `pm-event-log.sh`, `pm-session-context.sh` | Commit convention enforcement, incomplete work detection, event logging |
| **Utilities** | `find-plan.sh`, `pm-dashboard.sh`, `pm.config.sh`, `codex-mcp-overrides.sh`, `pm-record.sh` | Plan discovery, health dashboard, config, memory writer |

### GitHub Actions (Automated)

| Workflow | Trigger | What it does |
|----------|---------|-------------|
| **`pm-post-merge.yml`** | PR merged with `Fixes #N` | Moves issue to Done, posts completion comment |
| **`pm-pr-check.yml`** | PR opened/edited | Validates conventional commit, issue link, workflow state |

Requires a `PROJECT_WRITE_TOKEN` repository secret (classic PAT with `project` scope).

### MCP Server (pm-intelligence)

A native MCP server that gives Claude direct access to project state — no bash scripts needed.

| Category | What | Description |
|----------|------|-------------|
| **Core** | `get_issue_status` | Workflow state, priority, area, labels for any issue |
| | `get_board_summary` | Full board with health score (0-100) and stale items |
| | `move_issue` | Transition issue to any workflow state |
| | `get_velocity` | Merge/close/open rates (7d and 30d windows) |
| **Memory** | `record_decision` | Log architectural decisions to persistent memory |
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
| | `get_issue_dependencies` | Upstream/downstream chains, execution order, unblocked check |
| **Capacity** | `get_team_capacity` | Contributor profiles, sprint forecast, area coverage |
| **Planning** | `plan_sprint` | AI-powered sprint planning combining all intelligence |
| **Visualization** | `visualize_dependencies` | ASCII + Mermaid dependency graph rendering |
| **Dashboard** | `get_project_dashboard` | Full health report synthesizing all intelligence |
| **Operations** | `suggest_next_issue` | "What should I work on next?" ranked recommendations |
| | `generate_standup` | Auto-generated daily standup from project activity |
| | `generate_retro` | Data-driven sprint retrospective with evidence |
| **Learning** | `record_review_outcome` | Track review finding dispositions for calibration |
| | `get_review_calibration` | Hit rate analysis, false positive patterns, trends |
| | `check_decision_decay` | Detect stale decisions based on context drift |
| **Resources** | `pm://board/overview` | Board state (cached, refreshed on tool use) |
| | `pm://memory/decisions` | Recent architectural decisions |
| | `pm://memory/outcomes` | Recent work outcomes |
| | `pm://memory/insights` | Memory analytics and patterns |
| | `pm://events/recent` | Last 50 events from the event stream |
| | `pm://analytics/sprint` | Current sprint analytics |
| | `pm://analytics/dora` | DORA performance metrics |

Activate after install: `cd tools/mcp/pm-intelligence && npm install && npm run build`

Claude Code auto-discovers it from `.mcp.json`.

### Workflow Docs

| Doc | Purpose |
|-----|---------|
| `PM_PLAYBOOK.md` | Workflow states, transition rules, field IDs, command reference |
| `PM_PROJECT_CONFIG.md` | Your project's doc paths, library mappings, port services |

---

## Quick Start

### Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) — authenticated
- [jq](https://jqlang.github.io/jq/)
- `gh auth refresh -s project` (adds project scope)

### Install

```bash
./install.sh /path/to/your/repo
```

The installer:
1. Prompts for GitHub owner, repo, project number (or creates a new board)
2. **Auto-detects your stack** (React, Svelte, Next.js, Python, etc.) and suggests area options
3. Discovers all field IDs via GraphQL — you never look up IDs manually
4. Links project to repo, sets it public with description
5. Copies files with all placeholders resolved
6. Merges hooks into `.claude/settings.json`
7. Prints board view setup instructions

### Update

```bash
cd claude-pm-toolkit && git pull
./install.sh --update /path/to/your/repo
```

Reads saved config, refreshes field IDs, overwrites toolkit files, preserves your customizations.

### Validate

```bash
./validate.sh /path/to/your/repo            # 76-check validation suite
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
/issue                 # Create issue → PM interview → duplicate scan → structured issue
/issue 42              # Load context → detect state → enter plan mode
/pm-review 123         # Adversarial review with split verdict
/weekly                # AI analysis of latest weekly snapshot
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

**WIP limit:** Claude may have only 1 issue in Active at a time.

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

```
.claude-pm-toolkit.json              # Install metadata (enables --update)
.github/workflows/
├── pm-post-merge.yml                # Auto-move issues to Done on merge
└── pm-pr-check.yml                  # PR quality gate (conventions, issue link)
.claude/
├── settings.json                    # Hooks: security guards, portfolio notifications
└── skills/
    └── issue/
        ├── SKILL.md                 # Router (~1,300 lines)
        ├── VERIFICATION.md          # Regression checklist
        ├── sub-playbooks/           # 7 extracted playbooks
        │   ├── duplicate-scan.md
        │   ├── update-existing.md
        │   ├── merge-consolidate.md
        │   ├── discovered-work.md
        │   ├── collaborative-planning.md
        │   ├── implementation-review.md
        │   └── post-implementation.md
        └── appendices/              # 6 reference files
            ├── templates.md
            ├── briefing-format.md
            ├── worktrees.md
            ├── priority.md
            ├── codex-reference.md
            └── design-rationale.md
    ├── pm-review/SKILL.md           # Adversarial reviewer (~1,000 lines)
    └── weekly/SKILL.md              # Weekly analysis
docs/
├── PM_PLAYBOOK.md                   # Workflow definitions, field IDs
└── PM_PROJECT_CONFIG.md             # Your project config (user-editable)
tools/
├── config/                          # User-editable security configs
│   ├── command-guard.conf
│   ├── secret-patterns.json
│   └── secret-paths.conf
└── scripts/                         # 18 scripts (all support --help)
    ├── pm.config.sh                 # Central config (auto-generated field IDs)
    ├── project-{add,move,status,archive-done}.sh
    ├── worktree-{setup,detect,cleanup}.sh
    ├── worktree-{ports,urls}.conf   # User-editable port config
    ├── tmux-session.sh
    ├── portfolio-notify.sh
    ├── find-plan.sh
    ├── pm-dashboard.sh
    ├── codex-mcp-overrides.sh
    ├── pm-record.sh                  # JSONL memory writer
    ├── pm-session-context.sh          # SessionStart hook
    └── claude-{command-guard,secret-*}.sh
└── mcp/
    └── pm-intelligence/               # MCP server (TypeScript)
        ├── src/{index,config,github,memory}.ts
        ├── package.json
        └── build/                     # Compiled output (gitignored)
.mcp.json                               # MCP server registration
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

## GitHub Projects v2

The installer can create a board with all required fields:

| Field | Options |
|-------|---------|
| **Workflow** | Backlog, Ready, Active, Review, Rework, Done |
| **Priority** | Critical, High, Normal |
| **Area** | (auto-detected from your stack) |
| **Issue Type** | Bug, Feature, Spike, Epic, Chore |
| **Risk** | Low, Medium, High |
| **Estimate** | Small, Medium, Large |

After install, the project is linked to your repo and made public. Set up a Board view grouped by Workflow for a Kanban-style experience.

---

## Troubleshooting

<details>
<summary><code>gh CLI token missing 'project' scope</code></summary>

```bash
gh auth refresh -s project --hostname github.com
```
</details>

<details>
<summary><code>Issue #X not found in project</code></summary>

```bash
./tools/scripts/project-add.sh 123 normal
```
</details>

<details>
<summary><code>pm.config.sh contains unreplaced {{placeholders}}</code></summary>

```bash
./install.sh --update /path/to/your/repo
```
</details>

<details>
<summary><code>Could not find project #N for owner 'X'</code></summary>

- Check `PM_OWNER` in `tools/scripts/pm.config.sh`
- Verify project at `https://github.com/orgs/YOUR_ORG/projects`
- Run `gh auth refresh -s project`
- If user-owned (not org), owner = your username
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

### Placeholder Convention

| Placeholder | Case | Purpose | After Install |
|------------|------|---------|--------------|
| `{{prefix}}` | lowercase | Directory names, session names | `hov`, `myapp` |
| `{{PREFIX}}` | UPPERCASE | Environment variable names | `HOV`, `MYAPP` |

---

## Script Reference

Every script supports `--help`:

```bash
./tools/scripts/project-move.sh --help
./tools/scripts/project-add.sh --help
./tools/scripts/worktree-setup.sh --help
./tools/scripts/pm-dashboard.sh --help
```

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

# Claude PM Toolkit

A complete project management system for Claude Code. Gives your AI coding assistant structured workflows, adversarial reviews, parallel development with worktrees, and portfolio management — all driven by GitHub Projects v2.

**Works with any project.** Install into an existing repo in under 2 minutes. Update to the latest toolkit version with one command.

## What You Get

| Skill | What It Does |
|-------|-------------|
| `/issue` | Full issue lifecycle: create via PM interview, deduplicate, execute with worktree isolation, detect workflow state, plan mode, post-implementation review sequence |
| `/pm-review` | Adversarial PM reviewer: scope verification, failure mode analysis, comment skepticism, infra parity checks, split completeness/robustness verdict |
| `/weekly` | AI narrative analysis from weekly JSON snapshots with stakeholder-ready summaries |

| Scripts | What They Do |
|---------|-------------|
| `project-*.sh` | GitHub Projects v2 integration — add issues, move between states, check status |
| `worktree-*.sh` | Git worktree management with automatic port isolation for parallel development |
| `tmux-session.sh` | Portfolio manager — run multiple Claude sessions on different issues simultaneously |
| `claude-*-guard.sh` | Security hooks — block dangerous commands, detect secrets in output |

| Docs | What They Define |
|------|-----------------|
| `PM_PLAYBOOK.md` | Workflow states, transition rules, field references, command cheat sheet |
| `PM_PROJECT_CONFIG.md` | Your project's doc paths, library mappings, port services, review examples |

## Quick Start

### Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) — authenticated
- [jq](https://jqlang.github.io/jq/)
- `gh auth refresh -s project` (adds project scope for board writes)

### Fresh Install (existing repo)

```bash
git clone https://github.com/YOUR_USER/claude-pm-toolkit.git
cd claude-pm-toolkit
./install.sh /path/to/your/repo
```

The installer will:
1. Prompt for GitHub owner, repo, project number (or create a new board)
2. Auto-discover all field IDs via GraphQL
3. Copy files with placeholders resolved
4. Merge hooks into your `.claude/settings.json`
5. Append PM sections to your `CLAUDE.md` (between sentinel comments)
6. Save config to `.claude-pm-toolkit.json` for future updates

### Template Mode (new repo)

1. Use this repo as a GitHub template
2. Clone and run `./install.sh .`

### Uninstall

```bash
cd claude-pm-toolkit
./uninstall.sh /path/to/your/repo             # Dry run (show what would be removed)
./uninstall.sh --confirm /path/to/your/repo   # Actually remove
```

### Update to Latest

When the toolkit gets new features or fixes:

```bash
cd claude-pm-toolkit
git pull                                    # Get latest
./install.sh --update /path/to/your/repo    # Apply changes
```

Update mode:
- Reads your saved config from `.claude-pm-toolkit.json` (no re-prompting)
- Refreshes field IDs from GitHub (catches project board changes)
- Overwrites toolkit-managed files with the latest versions
- **Preserves your customizations**: `worktree-ports.conf`, `worktree-urls.conf`, `command-guard.conf`, `secret-paths.conf`, `secret-patterns.json`, `PM_PROJECT_CONFIG.md`
- Updates CLAUDE.md sentinel block and settings.json hooks

### Validate

```bash
cd claude-pm-toolkit
./validate.sh /path/to/your/repo            # Check installation
./validate.sh --fix /path/to/your/repo      # Auto-fix what's possible
```

Checks: required files, script permissions, unresolved placeholders, pm.config.sh values, CLAUDE.md sentinels, settings.json hooks, .gitignore correctness, GitHub connectivity.

## Daily Workflow

```bash
# Start working on an issue
/issue 42              # Load context, detect state, enter plan mode

# Create a new issue
/issue                 # PM interview → duplicate scan → structured issue

# Review a PR
/pm-review 123         # Adversarial review with split verdict

# Weekly report
/weekly                # AI analysis of latest weekly snapshot
```

### Worktree Isolation

Each issue gets its own directory with isolated ports:

```
~/Development/
├── my-project/        # Main repo
├── app-42/            # Worktree for issue #42 (own ports)
└── app-57/            # Worktree for issue #57 (own ports)
```

Configure port services in `tools/scripts/worktree-ports.conf`:

```
Dev_server    3000    DEV_PORT
Database      5432    DB_PORT
Redis         6379    REDIS_PORT
```

### Portfolio Mode (tmux)

Run multiple Claude sessions in parallel:

```bash
make claude            # Start tmux session
/issue 42              # Spawns background window
/issue 57              # Spawns another window
# Watch status bar for alerts when a session needs input
```

## Customization

### Project-Specific Config (`docs/PM_PROJECT_CONFIG.md`)

This is your main customization file. It controls:

- **Area Documentation**: Maps `area:frontend` etc. to your docs
- **Keyword Documentation**: Maps keywords in issues to relevant docs
- **Library Documentation**: Maps keywords to context7 library lookups
- **Worktree Port Services**: Your dev server, database, etc. (`worktree-ports.conf`)
- **Review Examples**: Domain-specific examples for `/pm-review`
- **Stakeholder Context**: How to frame technical work for stakeholders in `/weekly`

### Area Options

The Area field options (Frontend, Backend, etc.) are configurable during setup. After install, edit `tools/scripts/pm.config.sh` to add or remove areas. The `/issue` skill references areas by label (`area:frontend`, `area:backend`).

### CLAUDE.md Sections

PM sections in your CLAUDE.md are wrapped in sentinel comments:

```html
<!-- claude-pm-toolkit:start -->
...PM workflow rules...
<!-- claude-pm-toolkit:end -->
```

Running `--update` replaces only this block. Your custom CLAUDE.md content outside the sentinels is never touched.

## Architecture

```
.claude-pm-toolkit.json          # Install metadata (enables --update)
.claude/
├── settings.json                # Hooks: security guards, portfolio notifications
└── skills/
    ├── issue/SKILL.md           # /issue skill (2000+ lines)
    ├── pm-review/SKILL.md       # /pm-review skill (1000+ lines)
    └── weekly/SKILL.md          # /weekly skill
docs/
├── PM_PLAYBOOK.md               # Workflow definitions, field IDs, transitions
└── PM_PROJECT_CONFIG.md         # Your project's doc paths, libraries, port services
tools/
├── config/
│   ├── command-guard.conf       # Blocked command patterns (user-editable)
│   ├── secret-patterns.json     # Token detection regexes (user-editable)
│   └── secret-paths.conf        # Custom sensitive paths (user-editable)
└── scripts/
    ├── pm.config.sh             # Central config (all field/option IDs)
    ├── project-add.sh           # Add issue to project board
    ├── project-move.sh          # Move issue between workflow states
    ├── project-status.sh        # Check issue's workflow state
    ├── project-archive-done.sh  # Archive completed issues
    ├── worktree-setup.sh        # Create worktree with port isolation
    ├── worktree-detect.sh       # Detect worktree status
    ├── worktree-cleanup.sh      # Clean up after merge
    ├── worktree-ports.conf      # Port service configuration (user-editable)
    ├── worktree-urls.conf       # URL exports from ports (user-editable)
    ├── tmux-session.sh          # Portfolio manager
    ├── portfolio-notify.sh      # Hook notification handler
    ├── find-plan.sh             # Find plan files by issue number
    ├── claude-command-guard.sh  # Block dangerous bash commands (reads config/)
    ├── claude-secret-guard.sh   # Block reading secret files
    ├── claude-secret-bash-guard.sh  # Block secret patterns in bash
    ├── claude-secret-check-path.sh  # Shared path sensitivity checker
    └── claude-secret-detect.sh  # Detect secrets in tool output
reports/weekly/                   # Weekly report snapshots
└── analysis/                    # AI-generated narrative reports
```

### How Updates Work

The toolkit separates **managed files** from **user config files**:

| Category | Examples | Fresh Install | Update |
|----------|---------|---------------|--------|
| Managed | SKILL.md, scripts, PM_PLAYBOOK.md | Copied | Overwritten with latest |
| User Config | PM_PROJECT_CONFIG.md, ports.conf, urls.conf | Copied | Preserved |
| Merged | settings.json | Created/merged | Hooks merged |
| Sentinel | CLAUDE.md PM sections | Appended | Block replaced |
| Metadata | .claude-pm-toolkit.json | Created | Updated |

This means you can safely `git pull` the toolkit and run `--update` without losing your customizations.

## Workflow States

| State | What Claude Can Do | Entry | Exit |
|-------|--------------------|-------|------|
| Backlog | Analyze only | Default for new issues | Move to Ready |
| Ready | Plan only | Triaged and spec-ready | Move to Active |
| Active | **Implement** | Work begins | PR opened → Review |
| Review | Wait for feedback | Tests pass, PR ready | Approved or Changes Requested |
| Rework | Address feedback | Changes requested | Fixes applied → Review |
| Done | Nothing | PR merged | Archive after 30 days |

**WIP limit:** Claude may have only 1 issue in Active at a time.

## GitHub Projects v2 Setup

If you don't have a board yet, the installer can create one for you (enter `new` when prompted for project number). It creates these fields:

- **Workflow**: Backlog, Ready, Active, Review, Rework, Done
- **Priority**: Critical, High, Normal
- **Area**: (you choose the options)
- **Issue Type**: Bug, Feature, Spike, Epic, Chore
- **Risk**: Low, Medium, High
- **Estimate**: Small, Medium, Large

Field IDs are auto-discovered via GraphQL — you never look up IDs manually.

## Troubleshooting

### `Error: gh CLI token missing 'project' scope`

The `gh` CLI needs the `project` scope for GitHub Projects v2 operations.

```bash
gh auth refresh -s project --hostname github.com
```

### `Error: Issue #X not found in project`

The issue hasn't been added to the project board yet.

```bash
./tools/scripts/project-add.sh 123 normal    # Add with normal priority
```

### `Error: pm.config.sh contains unreplaced {{placeholders}}`

The installer didn't finish replacing template values. Re-run:

```bash
./install.sh --update /path/to/your/repo
```

### `Error: Could not find project #N for owner 'X'`

Common causes:
- **Owner misspelled** — check `PM_OWNER` in `tools/scripts/pm.config.sh`
- **Project number wrong** — verify at `https://github.com/orgs/YOUR_ORG/projects`
- **Missing scope** — run `gh auth refresh -s project`
- **Org vs user** — if the project is under your user account, the owner should be your username

Verify manually:
```bash
gh project view 2 --owner YOUR_OWNER
```

### `validate.sh` shows failures

Run with `--fix` to auto-repair permissions and .gitignore:

```bash
./validate.sh --fix /path/to/your/repo
```

If config values are empty, re-run the installer:

```bash
./install.sh --update /path/to/your/repo
```

### Worktree already exists

If you get "worktree already exists" errors but the directory is gone:

```bash
git worktree prune     # Clean up stale metadata
```

### Port conflicts

Check what's using the port:

```bash
lsof -i :5173          # Replace with conflicting port number
```

Each worktree gets a port offset calculated as `(issue_number % 79) * 100 + 3200`. Override with:

```bash
WORKTREE_PORT_OFFSET=5000 ./tools/scripts/worktree-setup.sh 294 feat/my-feature
```

### `settings.json` is corrupted

If `.claude/settings.json` has invalid JSON (can happen from failed merge):

```bash
# Check validity
jq empty .claude/settings.json

# If it fails, restore from git
git checkout .claude/settings.json
./install.sh --update /path/to/your/repo     # Re-merge hooks
```

### tmux "portfolio session not found"

Start the session first:

```bash
make claude    # Creates tmux session and launches Claude
```

### Placeholder Convention

The toolkit uses two placeholder cases with distinct meanings:

| Placeholder | Case | Purpose | Example After Install |
|------------|------|---------|----------------------|
| `{{prefix}}` | lowercase | Directory names, session names, file paths | `hov`, `myapp` |
| `{{PREFIX}}` | UPPERCASE | Environment variable names | `HOV`, `MYAPP` |

So `{{prefix}}-294` becomes `hov-294` (worktree directory) and `{{PREFIX}}_ISSUE_NUM` becomes `HOV_ISSUE_NUM` (env var).

## Script Reference

Every script supports `--help`:

```bash
./tools/scripts/project-move.sh --help
./tools/scripts/project-add.sh --help
./tools/scripts/project-status.sh --help
./tools/scripts/project-archive-done.sh --help
./tools/scripts/worktree-setup.sh --help
./tools/scripts/worktree-detect.sh --help
./tools/scripts/worktree-cleanup.sh --help
./tools/scripts/find-plan.sh --help
./tools/scripts/pm-dashboard.sh --help
```

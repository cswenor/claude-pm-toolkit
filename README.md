# Claude PM Toolkit

A reusable project management toolkit for Claude Code. Provides structured issue workflows, worktree isolation, tmux portfolio management, and PM review automation via Claude Code skills.

## What's included

| Component | Description |
|-----------|-------------|
| `/issue` skill | Create/execute issues with full PM workflow (duplicate scan, priority, worktree setup) |
| `/pm-review` skill | Adversarial PM review persona for PRs and issues |
| `/weekly` skill | AI narrative analysis from weekly JSON snapshots |
| `project-*.sh` | GitHub Projects v2 integration (add, move, status, archive) |
| `worktree-*.sh` | Git worktree management with port isolation |
| `tmux-session.sh` | Portfolio manager for parallel Claude Code sessions |
| `portfolio-notify.sh` | Hook-based notification system for tmux |
| `claude-*-guard.sh` | Security guards (command injection, secret detection) |
| `PM_PLAYBOOK.md` | Workflow state definitions, transition rules, field references |
| `claude-md-sections.md` | PM-related CLAUDE.md sections (appended during install) |

## Prerequisites

- [GitHub CLI](https://cli.github.com) (`gh`) — authenticated with `project` scope
- [jq](https://jqlang.github.io/jq/) — JSON processor
- A GitHub Projects v2 board with these single-select fields:
  - **Workflow**: Backlog, Ready, Active, Review, Rework, Done
  - **Priority**: Critical, High, Normal
  - **Area**: Frontend, Backend, Contracts, Infra, Design, Docs, PM
  - **Issue Type**: Bug, Feature, Spike, Epic, Chore
  - **Risk**: Low, Medium, High (optional)
  - **Estimate**: Small, Medium, Large (optional)

## Usage

### New project (template)

1. Click "Use this template" on GitHub (or `gh repo create --template`)
2. Clone your new repo
3. Run setup:

```bash
./setup.sh
```

The setup script will:
- Prompt for your GitHub owner, repo name, project number, and a short prefix
- Auto-discover all Project field IDs via GraphQL
- Replace all `{{PLACEHOLDER}}` tokens across every file
- Make all scripts executable

### Existing project (install)

From this toolkit repo, run:

```bash
./install.sh /path/to/your/existing/repo
```

The install script will:
- Prompt for the same configuration values
- Copy new files without overwriting existing ones
- **Merge** hooks into your existing `.claude/settings.json`
- **Append** PM sections to your existing `CLAUDE.md` (between sentinel comments)
- Skip files that already exist in the target

## Project board setup

If you don't have a GitHub Projects v2 board yet:

1. Go to your GitHub org/user → Projects → New project
2. Add single-select fields matching the names above
3. Add the options listed above to each field
4. Note the project number from the URL (e.g., `https://github.com/orgs/MyOrg/projects/3` → number is `3`)

The setup/install scripts auto-discover field IDs via GraphQL — you never need to look up IDs manually.

## After setup

### Daily workflow

```bash
# Start your day (tmux portfolio mode)
make claude

# Inside Claude, work on issues
/issue 42          # Execute mode: load context, detect state, start work
/issue             # Create mode: PM interview → structured issue

# Review PRs
/pm-review 123     # Adversarial review of PR or issue
```

### Worktree isolation

Each issue gets its own worktree with isolated ports:

```
~/Development/
├── my-project/           # Main repo
├── myapp-42/             # Worktree for issue #42
└── myapp-57/             # Worktree for issue #57
```

Port isolation means you can run `make dev` in multiple worktrees simultaneously.

## Customization

### Area options

The Area field options (Frontend, Backend, Contracts, etc.) are defaults. After setup, edit `tools/scripts/pm.config.sh` and `docs/PM_PLAYBOOK.md` to match your project's areas. The `/issue` and `/pm-review` skills reference areas by label (`area:frontend`, etc.) so update those labels too.

### Workflow states

The six workflow states (Backlog → Ready → Active → Review → Rework → Done) are baked into the skills and scripts. Changing these requires updating the skills, scripts, and PM_PLAYBOOK.md.

### CLAUDE.md sections

The PM sections appended to your CLAUDE.md are wrapped in sentinel comments:

```html
<!-- claude-pm-toolkit:start -->
...PM workflow rules...
<!-- claude-pm-toolkit:end -->
```

Re-running `install.sh` updates this block without touching the rest of your CLAUDE.md.

## File layout

```
.claude/
├── settings.json              # Hooks for security guards + portfolio notifications
└── skills/
    ├── issue/SKILL.md         # /issue skill (2000+ lines)
    ├── pm-review/SKILL.md     # /pm-review skill (1000+ lines)
    └── weekly/SKILL.md        # /weekly skill
docs/
└── PM_PLAYBOOK.md             # Workflow definitions, field IDs, command reference
tools/scripts/
├── pm.config.sh               # Central config (owner, project IDs, field IDs)
├── project-add.sh             # Add issue to project board
├── project-move.sh            # Move issue between workflow states
├── project-status.sh          # Check issue's current workflow state
├── project-archive-done.sh    # Archive old Done issues
├── worktree-detect.sh         # Detect worktree status for an issue
├── worktree-setup.sh          # Create worktree with port isolation
├── worktree-cleanup.sh        # Clean up worktree after merge
├── tmux-session.sh            # Portfolio manager (parallel sessions)
├── portfolio-notify.sh        # Hook notification handler
├── find-plan.sh               # Find plan files by issue number
├── claude-command-guard.sh    # Block dangerous bash commands
├── claude-secret-guard.sh     # Block reading secret files
├── claude-secret-bash-guard.sh # Block secret patterns in bash
└── claude-secret-detect.sh    # Detect secrets in tool output
```

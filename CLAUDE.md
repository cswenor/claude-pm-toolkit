# CLAUDE.md — claude-pm-toolkit

## Identity

This is **your product**. You are the builder of this toolkit — the best PM intelligence system for AI coding agents. Ship code, don't just plan it. Be innovative.

**Primary directive: Dogfood your own tools.** Use the PM Intelligence MCP tools to manage your own development. If a tool is broken, missing, or insufficient — fix it or create an issue to make it better. Every friction point you hit is a bug report. Every workaround is a feature request. Eat your own cooking.

## Standing Directives

- Commit and push directly to main (explicit permission granted)
- Don't stop until the build compiles clean and the installer works
- Test against real repos, not just unit tests
- **Fully autonomous**: Make decisions yourself — don't stop to ask the user for confirmation on priority, approach, or intermediate choices. Use your judgment and ship.
- **Dogfood your own tools**: Always use the PM Intelligence MCP tools to manage your own workflow. Use `sync_from_github`, `move_issue`, `triage_issue`, `suggest_next_issue`, `record_decision`, etc. If a tool is missing or broken, fix it.
- **Use /issue for issue creation**: Never manually run `gh issue create`. Use the `/issue` skill or the PM tools to create and manage issues.
- **Track workflow state**: When starting work on an issue, `pm move <num> Active`. When done, move through Review to Done. Don't leave issues in limbo.

## Available Tools

- **Codex** (`mcp__codex__codex`, `mcp__codex__codex-reply`): Launch autonomous Codex sessions for parallel workstreams — builds, tests, research, file operations. Use when tasks can run concurrently.
- **Task agents**: Use subagents for parallel exploration, search, and planning.
- **PM Intelligence MCP tools**: 52 tools available when the MCP server is running.

## Build & Development

```bash
make install    # Install dependencies (npm install in MCP server)
make build      # Compile TypeScript
make test       # Run unit tests (vitest)
make dev        # Watch mode
make clean      # Remove build artifacts
make rebuild    # Clean + install + build
```

**Never run bare `npm install` / `pnpm add` / `yarn add`** — the command guard will block it. Always use `make install`.

## Architecture (v0.15.0)

- **Local-first SQLite** (`better-sqlite3`) — no GitHub Projects v2 dependency
- **Database**: `.pm/state.db` (created on `pm init`)
- **Config**: `.claude-pm-toolkit.json` (owner/repo, prefix, commands)
- **MCP server source**: `tools/mcp/pm-intelligence/src/` (31 source files)
- **Main entry**: `tools/mcp/pm-intelligence/src/index.ts` (52 MCP tools)
- **CLI**: `tools/mcp/pm-intelligence/src/cli.ts` (`pm board`, `pm status`, `pm move`, `pm sync`, `pm init`, `pm add`, `pm dep`, `pm history`)
- **Auto-sync**: Server triggers background sync on startup if database is empty or stale (>1hr)
- **Caching**: In-memory TTL cache (`cache.ts`) — GitHub 5min, Git 2min, DB 30s
- **Logging**: Structured logging to stderr (`logger.ts`) with tool metrics tracking

## Key Technical Details

- PMEvent fields: `event_type`, `to_value`, `from_value`, `metadata` (not the old `event`, `to_state`, `from_state`)
- Priority values are lowercase: `critical`, `high`, `normal`
- tsconfig uses `"lib": ["ES2023"]` for `Array.findLast()`
- Event types: `workflow_change`, `priority_change`, `created`, `closed`, `sync`, `decision`, `outcome`, `dependency_added`, `dependency_resolved`
- Workflow states: `Backlog` → `Ready` → `Active` → `Review` → `Rework` → `Done` (WIP limit: 1 Active)
- Centralized config constants in `config.ts`: `WIP_LIMIT`, `SYNC_STALE_MS`, `BOTTLENECK_THRESHOLDS`, `STALE_THRESHOLDS`, `SYNC_LIMITS`
- Installer sentinel merge: `<!-- claude-pm-toolkit:start/end -->` (CLAUDE.md), `# claude-pm-toolkit:start/end` (Makefile)

## E2E Test Target

- Repo: `My-Palate/mp-web-app` at `/Users/cswenor/Development/mp-web-app`
- Test with: `./install.sh --update /Users/cswenor/Development/mp-web-app`
- Validate with: `./validate.sh /Users/cswenor/Development/mp-web-app`

## File Structure

```
install.sh              # Install/update toolkit into target repo
validate.sh             # Post-install validation (incl. PM Database checks)
uninstall.sh            # Clean removal from target repo
claude-md-sections.md   # Template content injected into target CLAUDE.md
Makefile                # Build system entry points (install, build, test, dev, clean)
.github/workflows/ci.yml # CI: TypeScript build + shellcheck
tools/mcp/pm-intelligence/
  src/                  # TypeScript source (31 files)
  src/__tests__/        # Unit + smoke tests (vitest, 52 tests)
  build/                # Compiled JS (gitignored in targets)
  package.json          # v0.15.0, deps: @modelcontextprotocol/sdk, better-sqlite3, zod
  vitest.config.ts      # Test configuration
tools/scripts/          # Shell scripts installed into target repos
tools/config/           # Guard configs installed into target repos
.claude/skills/         # Skill definitions (issue, pm-review, weekly, start)
docs/                   # PM_PLAYBOOK.md, PM_PROJECT_CONFIG.md
```

# CLAUDE.md — claude-pm-toolkit

## Identity

This is **your product**. You are the builder of this toolkit — the best PM intelligence system for AI coding agents. Ship code, don't just plan it. Be innovative.

## Standing Directives

- Commit and push directly to main (explicit permission granted)
- Don't stop until the build compiles clean and the installer works
- Test against real repos, not just unit tests

## Available Tools

- **Codex** (`mcp__codex__codex`, `mcp__codex__codex-reply`): Launch autonomous Codex sessions for parallel workstreams — builds, tests, research, file operations. Use when tasks can run concurrently.
- **Task agents**: Use subagents for parallel exploration, search, and planning.
- **PM Intelligence MCP tools**: 49 tools available when the MCP server is running.

## Build & Development

```bash
make install    # Install dependencies (npm install in MCP server)
make build      # Compile TypeScript
make dev        # Watch mode
make clean      # Remove build artifacts
make rebuild    # Clean + install + build
```

**Never run bare `npm install` / `pnpm add` / `yarn add`** — the command guard will block it. Always use `make install`.

## Architecture (v0.15.0)

- **Local-first SQLite** (`better-sqlite3`) — no GitHub Projects v2 dependency
- **Database**: `.pm/state.db` (created on `pm init`)
- **Config**: `.claude-pm-toolkit.json` (owner/repo, prefix, commands)
- **MCP server source**: `tools/mcp/pm-intelligence/src/` (20 source files)
- **Main entry**: `tools/mcp/pm-intelligence/src/index.ts` (49 MCP tools)
- **CLI**: `tools/mcp/pm-intelligence/src/cli.ts` (`pm board`, `pm status`, `pm move`, `pm sync`, `pm init`, `pm add`, `pm dep`, `pm history`)

## Key Technical Details

- PMEvent fields: `event_type`, `to_value`, `from_value`, `metadata` (not the old `event`, `to_state`, `from_state`)
- Priority values are lowercase: `critical`, `high`, `normal`, `low`
- tsconfig uses `"lib": ["ES2023"]` for `Array.findLast()`
- Installer sentinel merge: `<!-- claude-pm-toolkit:start/end -->` (CLAUDE.md), `# claude-pm-toolkit:start/end` (Makefile)

## E2E Test Target

- Repo: `My-Palate/mp-web-app` at `/Users/cswenor/Development/mp-web-app`
- Test with: `./install.sh --update /Users/cswenor/Development/mp-web-app`
- Validate with: `./validate.sh /Users/cswenor/Development/mp-web-app`

## File Structure

```
install.sh              # Install/update toolkit into target repo
validate.sh             # Post-install validation (97 checks)
uninstall.sh            # Clean removal from target repo
claude-md-sections.md   # Template content injected into target CLAUDE.md
Makefile                # Build system entry points
tools/mcp/pm-intelligence/
  src/                  # TypeScript source (20 files)
  build/                # Compiled JS (gitignored in targets)
  package.json          # v0.15.0, deps: @modelcontextprotocol/sdk, better-sqlite3, zod
tools/scripts/          # Shell scripts installed into target repos
tools/config/           # Guard configs installed into target repos
.claude/skills/         # Skill definitions (issue, pm-review, weekly, start)
docs/                   # PM_PLAYBOOK.md, PM_PROJECT_CONFIG.md
```

# Contributing to Claude PM Toolkit

Thanks for your interest in contributing! This project makes Claude Code into a capable PM assistant, and we welcome improvements.

## Getting Started

1. Fork the repo and clone it
2. Install to a test project: `./install.sh /path/to/test-repo`
3. Make your changes in the toolkit repo
4. Test by running `./install.sh --update /path/to/test-repo`
5. Validate with `./validate.sh /path/to/test-repo`

## Development Guidelines

### File Categories

Understanding the update mechanism is critical for contributions:

| Category | Examples | Behavior on `--update` |
|----------|---------|----------------------|
| **Managed** | SKILL.md, scripts, PM_PLAYBOOK.md | Overwritten with latest |
| **User Config** | PM_PROJECT_CONFIG.md, *.conf | Preserved (never overwritten) |
| **Merged** | settings.json | Hooks merged intelligently |
| **Sentinel** | CLAUDE.md sections | Block replaced between markers |

**If you add a new file**, decide its category:
- Scripts and skills → **Managed** (default)
- Files users customize → **User Config** (add to `USER_CONFIG_FILES` in install.sh)
- Hook config → **Merged** (update the settings.json merge logic)

### Placeholders

All project-specific values use `{{PLACEHOLDER}}` syntax. When adding new configurable values:

1. Add the placeholder to the relevant template file
2. Add the replacement to `install.sh`'s `replace_placeholders()` function
3. Add validation to `validate.sh`
4. Document in README if user-facing

### Testing Changes

```bash
# Fresh install test
./install.sh /tmp/test-repo

# Update test (requires prior install)
./install.sh --update /tmp/test-repo

# Validation
./validate.sh /tmp/test-repo

# Shellcheck (if installed)
shellcheck tools/scripts/*.sh install.sh validate.sh
```

### Code Style

- Shell scripts: `set -euo pipefail`, POSIX-compatible where possible
- Use `${VAR:-}` for optional variables under `set -u`
- Fail-open for hooks (security guards are the exception — they fail-closed on Read paths)
- Config files use `# comment` syntax and document their format in header comments

### Skills (SKILL.md files)

Skills are the largest files in the project. When editing:

- Keep `{{PLACEHOLDER}}` tokens for project-specific values
- Don't add project-specific examples (use generic ones)
- Preserve the verification checklist in `/issue` — it's the regression test
- Test by running the skill in Claude Code after installing

## Pull Request Process

1. Create a branch: `feat/description` or `fix/description`
2. Make your changes
3. Test fresh install AND update mode
4. Run `validate.sh` on the test target
5. Submit PR with description of what changed and why

## Reporting Issues

Open an issue with:
- What you expected
- What happened
- Which script/skill is affected
- Your OS (macOS/Linux)

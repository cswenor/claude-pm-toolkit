# Changelog

All notable changes to this project will be documented in this file.

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

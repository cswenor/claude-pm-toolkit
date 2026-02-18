# Changelog

All notable changes to this project will be documented in this file.

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

# ---------------------------------------------------------------------------
# claude-pm-toolkit targets
# ---------------------------------------------------------------------------
# These targets were added by claude-pm-toolkit install.
# Remove this block to uninstall the Makefile integration.

claude: ## Start Claude Code with tmux portfolio management
	@if command -v tmux >/dev/null 2>&1; then \
		./tools/scripts/tmux-session.sh init-and-run; \
	else \
		echo "tmux not installed. Starting Claude directly..."; \
		claude; \
	fi

pm-status: ## Show PM toolkit dashboard (health, worktrees, board)
	@./tools/scripts/pm-dashboard.sh

pm-validate: ## Validate PM toolkit installation
	@./tools/scripts/pm-dashboard.sh

pm-archive: ## Archive completed issues (Done > 7 days)
	@./tools/scripts/project-archive-done.sh

# ---------------------------------------------------------------------------
# End claude-pm-toolkit targets
# ---------------------------------------------------------------------------

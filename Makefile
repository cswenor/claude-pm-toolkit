# Makefile — claude-pm-toolkit development
#
# Primary entry points for building, testing, and installing the toolkit.

MCP_DIR := tools/mcp/pm-intelligence

.PHONY: install build dev clean test help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

install: ## Install dependencies (npm install in MCP server)
	cd $(MCP_DIR) && npm install

build: ## Build TypeScript MCP server
	cd $(MCP_DIR) && npm run build

dev: ## Watch mode for TypeScript
	cd $(MCP_DIR) && npm run dev

clean: ## Remove build artifacts
	rm -rf $(MCP_DIR)/build $(MCP_DIR)/node_modules

test: ## Run unit tests
	cd $(MCP_DIR) && npm test

rebuild: clean install build ## Clean rebuild

validate: ## Run validate.sh on a target repo (usage: make validate TARGET=/path/to/repo)
	./validate.sh $(TARGET)

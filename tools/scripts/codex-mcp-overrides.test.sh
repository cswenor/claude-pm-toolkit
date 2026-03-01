#!/usr/bin/env bash
# Tests for codex-mcp-overrides.sh
# Usage: ./tools/scripts/codex-mcp-overrides.test.sh
#
# Uses a temporary .mcp.json fixture so tests work in any environment.
# Tests that require a real codex binary are skipped when unavailable.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/codex-mcp-overrides.sh"

passed=0
failed=0
skipped=0

pass() {
  echo "  PASS: $1"
  passed=$((passed + 1))
}

fail() {
  echo "  FAIL: $1 — $2"
  failed=$((failed + 1))
}

skip() {
  echo "  SKIP: $1"
  skipped=$((skipped + 1))
}

# ─── Setup: Create a temp directory with a mock .mcp.json ───
TMPDIR_FIX=$(mktemp -d)
trap 'rm -rf "$TMPDIR_FIX"' EXIT

cat > "$TMPDIR_FIX/.mcp.json" <<'FIXTURE'
{
  "mcpServers": {
    "simple-http": {
      "type": "http",
      "url": "https://example.com/mcp"
    },
    "simple-stdio": {
      "command": "npx",
      "args": ["-y", "@example/mcp-server"]
    },
    "needs-auth": {
      "command": "npx",
      "args": ["-y", "@example/auth-server"],
      "env": {
        "AUTH_TOKEN": "${AUTH_TOKEN}"
      }
    },
    "mapped-env": {
      "command": "npx",
      "args": ["-y", "@example/mapped-server"],
      "env": {
        "MAPPED_KEY": "${MAPPED_SOURCE_VAR}"
      }
    },
    "no-args": {
      "command": "my-server"
    }
  }
}
FIXTURE

# Helper: run the script inside the temp dir so it finds .mcp.json
run_script() {
  (cd "$TMPDIR_FIX" && "$SCRIPT" "$@")
}

# ─── Test 1: Script exits 0 when codex is available ───
echo "Test 1: Script exits 0 when codex is available"
if command -v codex &>/dev/null; then
  if run_script >/dev/null 2>/dev/null; then
    pass "exits 0"
  else
    fail "exits 0" "got non-zero exit"
  fi
else
  skip "codex not installed"
fi

# ─── Test 2: Script exits 0 with empty stdout when codex unavailable ───
echo "Test 2: Script exits 0 with empty stdout when codex unavailable"
NO_CODEX_PATH="/usr/bin:/bin"
stdout=$(cd "$TMPDIR_FIX" && PATH="$NO_CODEX_PATH" "$SCRIPT" 2>/dev/null) || true
if [ -z "$stdout" ]; then
  pass "empty stdout when codex unavailable"
else
  fail "empty stdout when codex unavailable" "got: $stdout"
fi

# ─── Test 3: Stderr explains why when codex unavailable ───
echo "Test 3: Stderr explains why when codex unavailable"
stderr=$(cd "$TMPDIR_FIX" && PATH="$NO_CODEX_PATH" "$SCRIPT" 2>&1 >/dev/null) || true
if echo "$stderr" | grep -q "codex not found"; then
  pass "stderr contains 'codex not found'"
else
  fail "stderr contains 'codex not found'" "got: $stderr"
fi

# ─── Test 4: Output contains -c flags for no-auth servers ───
echo "Test 4: Output contains -c flags for simple-http and simple-stdio"
if command -v codex &>/dev/null; then
  stdout=$(run_script 2>/dev/null)
  all_present=true
  for server in simple-http simple-stdio no-args; do
    if ! echo "$stdout" | grep -q "mcp_servers\.$server="; then
      fail "$server present" "not found in output"
      all_present=false
    fi
  done
  if $all_present; then
    pass "simple-http, simple-stdio, no-args all present"
  fi
else
  skip "codex not installed"
fi

# ─── Test 5: Auth-gated server skipped when env var unset ───
echo "Test 5: needs-auth skipped when AUTH_TOKEN unset"
if command -v codex &>/dev/null; then
  stderr=$(AUTH_TOKEN="" run_script 2>&1 >/dev/null)
  if echo "$stderr" | grep -q "skipping needs-auth.*AUTH_TOKEN"; then
    pass "skip message for AUTH_TOKEN"
  else
    fail "skip message for AUTH_TOKEN" "got: $stderr"
  fi
else
  skip "codex not installed"
fi

# ─── Test 6: Auth-gated server included when env var set ───
echo "Test 6: needs-auth included when AUTH_TOKEN set"
if command -v codex &>/dev/null; then
  stdout=$(AUTH_TOKEN="test-token" run_script 2>/dev/null)
  if echo "$stdout" | grep -q "mcp_servers\.needs-auth="; then
    pass "needs-auth present when AUTH_TOKEN set"
  else
    fail "needs-auth present when AUTH_TOKEN set" "not found in output"
  fi
else
  skip "codex not installed"
fi

# ─── Test 7: Mapped env var resolved and included ───
echo "Test 7: mapped-env resolves MAPPED_SOURCE_VAR → MAPPED_KEY"
if command -v codex &>/dev/null; then
  stdout=$(MAPPED_SOURCE_VAR="resolved-value" run_script 2>/dev/null)
  if echo "$stdout" | grep -q 'mcp_servers\.mapped-env='; then
    # Verify the output contains the resolved value in an env={} block
    if echo "$stdout" | grep -q 'MAPPED_KEY="resolved-value"'; then
      pass "mapped env var resolved correctly"
    else
      fail "mapped env var resolved" "MAPPED_KEY not found with resolved value"
    fi
  else
    fail "mapped-env present" "not found in output"
  fi
else
  skip "codex not installed"
fi

# ─── Test 8: Output uses TOML inline table syntax ───
echo "Test 8: Output uses TOML syntax (key=value, not key:value)"
if command -v codex &>/dev/null; then
  stdout=$(AUTH_TOKEN="x" MAPPED_SOURCE_VAR="x" run_script 2>/dev/null)
  # TOML uses key="value", JSON uses "key":"value"
  if echo "$stdout" | grep -q 'type="http"' && ! echo "$stdout" | grep -q '"type"'; then
    pass "TOML inline table syntax used"
  else
    fail "TOML inline table syntax" "output may contain JSON instead of TOML"
  fi
else
  skip "codex not installed"
fi

# ─── Test 9: HTTP server emits type and url fields ───
echo "Test 9: HTTP server has type and url in TOML output"
if command -v codex &>/dev/null; then
  stdout=$(run_script 2>/dev/null)
  line=$(echo "$stdout" | grep "mcp_servers\.simple-http=" || true)
  if echo "$line" | grep -q 'type="http"' && echo "$line" | grep -q 'url="https://example.com/mcp"'; then
    pass "HTTP server has type and url"
  else
    fail "HTTP server fields" "got: $line"
  fi
else
  skip "codex not installed"
fi

# ─── Test 10: Stdio server emits command and args fields ───
echo "Test 10: Stdio server has command and args in TOML output"
if command -v codex &>/dev/null; then
  stdout=$(run_script 2>/dev/null)
  line=$(echo "$stdout" | grep "mcp_servers\.simple-stdio=" || true)
  if echo "$line" | grep -q 'command="npx"' && echo "$line" | grep -q 'args=\['; then
    pass "stdio server has command and args"
  else
    fail "stdio server fields" "got: $line"
  fi
else
  skip "codex not installed"
fi

# ─── Test 11: Server with no args emits command only ───
echo "Test 11: Server with command but no args"
if command -v codex &>/dev/null; then
  stdout=$(run_script 2>/dev/null)
  line=$(echo "$stdout" | grep "mcp_servers\.no-args=" || true)
  if echo "$line" | grep -q 'command="my-server"' && ! echo "$line" | grep -q 'args=\['; then
    pass "command-only server correct"
  else
    fail "command-only server" "got: $line"
  fi
else
  skip "codex not installed"
fi

# ─── Test 12: Stderr summary with server count ───
echo "Test 12: Stderr shows injecting N server(s)"
if command -v codex &>/dev/null; then
  stderr=$(AUTH_TOKEN="" MAPPED_SOURCE_VAR="" run_script 2>&1 >/dev/null)
  if echo "$stderr" | grep -q "injecting [0-9]* MCP server"; then
    pass "summary count in stderr"
  else
    fail "summary count" "got: $stderr"
  fi
else
  skip "codex not installed"
fi

# ─── Test 13: Missing .mcp.json exits 0 with diagnostic ───
echo "Test 13: Missing .mcp.json exits 0 with diagnostic"
if command -v codex &>/dev/null; then
  empty_dir=$(mktemp -d)
  stderr=$(cd "$empty_dir" && "$SCRIPT" 2>&1 >/dev/null) || true
  rmdir "$empty_dir"
  if echo "$stderr" | grep -q ".mcp.json not found"; then
    pass ".mcp.json not found diagnostic"
  else
    fail ".mcp.json not found diagnostic" "got: $stderr"
  fi
else
  skip "codex not installed"
fi

# ─── Test 14: Env var passthrough uses env_vars array ───
echo "Test 14: Same-name env var uses env_vars passthrough"
if command -v codex &>/dev/null; then
  stdout=$(AUTH_TOKEN="test" run_script 2>/dev/null)
  line=$(echo "$stdout" | grep "mcp_servers\.needs-auth=" || true)
  if echo "$line" | grep -q 'env_vars=\["AUTH_TOKEN"\]'; then
    pass "env_vars passthrough for same-name var"
  else
    fail "env_vars passthrough" "got: $line"
  fi
else
  skip "codex not installed"
fi

# ─── Summary ───
echo ""
echo "Results: $passed passed, $failed failed, $skipped skipped"
if [ "$failed" -gt 0 ]; then
  exit 1
fi

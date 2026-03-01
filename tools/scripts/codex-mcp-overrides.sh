#!/usr/bin/env bash
# codex-mcp-overrides.sh - Emit -c flags to inject MCP servers into codex exec
#
# Usage (command substitution in codex exec):
#   codex exec $(./tools/scripts/codex-mcp-overrides.sh) -s read-only ...
#
# Stdout: -c flags only (consumed by codex exec)
# Stderr: skip messages and summary (visible to Claude/user)
#
# Values use TOML inline table syntax (codex -c expects TOML, not JSON).
#
# Reads .mcp.json from the repository root and emits -c flags for each
# MCP server whose required environment variables are available.
#
# Outputs nothing if:
#   - codex is not installed
#   - .mcp.json doesn't exist or is invalid
#   - No servers have their required auth configured

set -euo pipefail

diag() { echo "codex-mcp-overrides: $*" >&2; }

# Check codex is available
if ! command -v codex &>/dev/null; then
  diag "codex not found, no MCP overrides emitted"
  exit 0
fi

# Find .mcp.json (walk up from cwd to find repo root)
MCP_JSON=""
dir="$(pwd)"
while [[ "$dir" != "/" ]]; do
  if [[ -f "$dir/.mcp.json" ]]; then
    MCP_JSON="$dir/.mcp.json"
    break
  fi
  dir="$(dirname "$dir")"
done

if [[ -z "$MCP_JSON" ]]; then
  diag ".mcp.json not found"
  exit 0
fi

if ! command -v jq &>/dev/null; then
  diag "jq not found, cannot parse .mcp.json"
  exit 0
fi

# Get list of server names
server_names=$(jq -r '.mcpServers // {} | keys[]' "$MCP_JSON" 2>/dev/null) || {
  diag "failed to parse .mcp.json"
  exit 0
}

server_count=0

while IFS= read -r name; do
  [[ -z "$name" ]] && continue

  srv_json=$(jq --arg n "$name" '.mcpServers[$n]' "$MCP_JSON" 2>/dev/null) || continue

  # Check env var requirements — extract ${VAR} references from env values
  env_refs=$(echo "$srv_json" | jq -r \
    '.env // {} | to_entries[] | .value |
     capture("^\\$\\{(?<v>[A-Za-z_][A-Za-z0-9_]*)\\}$") // empty | .v' \
    2>/dev/null) || true

  all_set=true
  missing=""
  while IFS= read -r ref; do
    [[ -z "$ref" ]] && continue
    if [[ -z "${!ref:-}" ]]; then
      all_set=false
      missing="$ref"
      break
    fi
  done <<< "$env_refs"

  if ! $all_set; then
    diag "skipping $name ($missing not set)"
    continue
  fi

  # Build TOML inline table from server definition
  toml_parts=()

  # type field (http servers)
  srv_type=$(echo "$srv_json" | jq -r '.type // empty' 2>/dev/null)
  [[ -n "$srv_type" ]] && toml_parts+=("type=\"$srv_type\"")

  # url field (http servers)
  srv_url=$(echo "$srv_json" | jq -r '.url // empty' 2>/dev/null)
  [[ -n "$srv_url" ]] && toml_parts+=("url=\"$srv_url\"")

  # command field (stdio servers)
  srv_cmd=$(echo "$srv_json" | jq -r '.command // empty' 2>/dev/null)
  [[ -n "$srv_cmd" ]] && toml_parts+=("command=\"$srv_cmd\"")

  # args array → TOML array of strings
  args_toml=$(echo "$srv_json" | jq -r \
    '.args // empty | map("\"" + . + "\"") | join(",")' 2>/dev/null)
  [[ -n "$args_toml" ]] && toml_parts+=("args=[$args_toml]")

  # env handling: separate into env_vars (passthrough) and env (mapped/resolved)
  env_entries=$(echo "$srv_json" | jq -r \
    '.env // {} | to_entries[] | "\(.key)\t\(.value)"' 2>/dev/null) || true
  env_vars_list=()
  env_map_parts=()
  while IFS=$'\t' read -r ekey eval; do
    [[ -z "$ekey" ]] && continue
    if [[ "$eval" =~ ^\$\{([A-Za-z_][A-Za-z0-9_]*)\}$ ]]; then
      ref="${BASH_REMATCH[1]}"
      if [[ "$ekey" == "$ref" ]]; then
        # Same name: passthrough via env_vars
        env_vars_list+=("\"$ekey\"")
      else
        # Different name: resolve and map
        resolved="${!ref:-}"
        env_map_parts+=("$ekey=\"$resolved\"")
      fi
    else
      # Literal value
      env_map_parts+=("$ekey=\"$eval\"")
    fi
  done <<< "$env_entries"

  if [[ ${#env_vars_list[@]} -gt 0 ]]; then
    toml_parts+=("env_vars=[$(IFS=,; echo "${env_vars_list[*]}")]")
  fi
  if [[ ${#env_map_parts[@]} -gt 0 ]]; then
    toml_parts+=("env={$(IFS=,; echo "${env_map_parts[*]}")}")
  fi

  # Skip if no meaningful config
  [[ ${#toml_parts[@]} -eq 0 ]] && continue

  printf '%s\n' '-c' "mcp_servers.${name}={$(IFS=,; echo "${toml_parts[*]}")}"
  server_count=$((server_count + 1))
done <<< "$server_names"

diag "injecting $server_count MCP server(s)"

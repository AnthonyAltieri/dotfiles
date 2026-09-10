#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d -t claude-mcp-servers-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

CONFIG="$WORK/.claude.json"
printf '%s\n' '{"oauthAccount":{"email":"kept@example.com"},"mcpServers":{"codex-threads":{"type":"http","url":"https://old.invalid","env":{"KEEP":"1"}},"local":{"type":"stdio","command":"local"}}}' > "$CONFIG"

python3 "$ROOT/scripts/merge-claude-mcp-servers.py" "$CONFIG" \
  '{"codex-threads":{"type":"stdio","command":"/nix/store/thread-manager","args":[]},"linear":"https://mcp.linear.app/mcp"}'

python3 - "$CONFIG" <<'PY'
import json
import sys

with open(sys.argv[1]) as config_file:
    config = json.load(config_file)

assert config["oauthAccount"]["email"] == "kept@example.com"
assert config["mcpServers"]["local"]["command"] == "local"
assert config["mcpServers"]["codex-threads"] == {
    "type": "stdio",
    "command": "/nix/store/thread-manager",
    "args": [],
    "env": {"KEEP": "1"},
}
assert config["mcpServers"]["linear"] == {
    "type": "http",
    "url": "https://mcp.linear.app/mcp",
}
PY

cp "$CONFIG" "$WORK/original.json"
if python3 "$ROOT/scripts/merge-claude-mcp-servers.py" "$CONFIG" \
  '{"broken":{"type":"stdio","command":"/bin/false","args":[1]}}' \
  > "$WORK/stdout" 2> "$WORK/stderr"
then
  echo "Expected an invalid stdio MCP spec to fail" >&2
  exit 1
fi
cmp "$WORK/original.json" "$CONFIG"

echo "Claude MCP server merge smoke test passed."

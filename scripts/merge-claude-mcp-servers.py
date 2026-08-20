"""Merge declared remote MCP servers into the Claude Code user config JSON.

Usage: merge-claude-mcp-servers.py <.claude.json> '<{"name": "url", ...}>'

The target is `$CLAUDE_CONFIG_DIR/.claude.json` (what `claude mcp add -s user`
writes). Targeted merge only: sets `mcpServers.<name>` to an http server with
the declared url and leaves every other key of the state file — and any extra
keys on the server entry — untouched.
"""

import json
import os
import sys
from pathlib import Path

CONFIG_PATH = Path(sys.argv[1])
SERVERS = json.loads(sys.argv[2])

CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)

if CONFIG_PATH.exists():
    try:
        config = json.loads(CONFIG_PATH.read_text())
    except json.JSONDecodeError as error:
        raise SystemExit(
            f"Refusing to update invalid Claude config JSON at {CONFIG_PATH}: {error}"
        ) from error
    if not isinstance(config, dict):
        raise SystemExit(f"Refusing to update {CONFIG_PATH}: top level is not a JSON object")
    original_mode = CONFIG_PATH.stat().st_mode & 0o777
else:
    config = {}
    original_mode = 0o600

mcp_servers = config.setdefault("mcpServers", {})
if not isinstance(mcp_servers, dict):
    raise SystemExit(f"Refusing to update {CONFIG_PATH}: mcpServers is not a JSON object")

for name, url in sorted(SERVERS.items()):
    server = mcp_servers.setdefault(name, {})
    if not isinstance(server, dict):
        raise SystemExit(
            f"Refusing to update {CONFIG_PATH}: mcpServers.{name} is not a JSON object"
        )
    server["type"] = "http"
    server["url"] = url

tmp_path = CONFIG_PATH.with_name(f".{CONFIG_PATH.name}.tmp")
tmp_fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(tmp_fd, "w") as config_file:
    json.dump(config, config_file, indent=2)
    config_file.write("\n")
os.chmod(tmp_path, original_mode)
tmp_path.replace(CONFIG_PATH)

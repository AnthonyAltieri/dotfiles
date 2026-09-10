"""Merge declared HTTP and stdio MCP servers into Claude Code's user config.

Usage: merge-claude-mcp-servers.py <.claude.json> '<{"name": <spec>, ...}>'

The target is `$CLAUDE_CONFIG_DIR/.claude.json` (what `claude mcp add -s user`
writes). A spec is either an HTTP URL string or a stdio object containing
`type`, `command`, and `args`. The merge changes only declared server entries
and leaves other config, servers, and server-specific environment intact.
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

for name, spec in sorted(SERVERS.items()):
    server = mcp_servers.setdefault(name, {})
    if not isinstance(server, dict):
        raise SystemExit(
            f"Refusing to update {CONFIG_PATH}: mcpServers.{name} is not a JSON object"
        )
    if isinstance(spec, str):
        server["type"] = "http"
        server["url"] = spec
        server.pop("command", None)
        server.pop("args", None)
        continue

    if not isinstance(spec, dict) or spec.get("type") != "stdio":
        raise SystemExit(
            f"Refusing to update {CONFIG_PATH}: MCP server {name} has an invalid spec"
        )
    command = spec.get("command")
    args = spec.get("args", [])
    if not isinstance(command, str) or not command:
        raise SystemExit(
            f"Refusing to update {CONFIG_PATH}: MCP server {name} needs a command"
        )
    if not isinstance(args, list) or not all(isinstance(arg, str) for arg in args):
        raise SystemExit(
            f"Refusing to update {CONFIG_PATH}: MCP server {name} args must be strings"
        )

    server["type"] = "stdio"
    server["command"] = command
    server["args"] = args
    server.pop("url", None)

tmp_path = CONFIG_PATH.with_name(f".{CONFIG_PATH.name}.tmp")
tmp_fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(tmp_fd, "w") as config_file:
    json.dump(config, config_file, indent=2)
    config_file.write("\n")
os.chmod(tmp_path, original_mode)
tmp_path.replace(CONFIG_PATH)

"""Merge declared remote MCP servers into the Codex config TOML.

Usage: merge-codex-mcp-servers.py <config.toml> '<{"name": "url", ...}>'

Targeted merge only: sets `features.rmcp_client` plus `mcp_servers.<name>.url`
for each declared server, and leaves every other key (other servers, OAuth
state, desktop settings) untouched.
"""

import json
import os
import sys
import tomllib
from pathlib import Path

import tomli_w

CONFIG_PATH = Path(sys.argv[1])
SERVERS = json.loads(sys.argv[2])


def require_table(config: dict, key: str, path: Path) -> dict:
    value = config.setdefault(key, {})
    if not isinstance(value, dict):
        raise SystemExit(f"Refusing to update {path}: [{key}] is not a TOML table")
    return value


CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)

if CONFIG_PATH.exists():
    try:
        with CONFIG_PATH.open("rb") as config_file:
            config = tomllib.load(config_file)
    except tomllib.TOMLDecodeError as error:
        raise SystemExit(
            f"Refusing to update invalid Codex config TOML at {CONFIG_PATH}: {error}"
        ) from error
    original_mode = CONFIG_PATH.stat().st_mode & 0o777
else:
    config = {}
    original_mode = 0o600

features = require_table(config, "features", CONFIG_PATH)
features["rmcp_client"] = True

mcp_servers = require_table(config, "mcp_servers", CONFIG_PATH)
for name, url in sorted(SERVERS.items()):
    server = mcp_servers.setdefault(name, {})
    if not isinstance(server, dict):
        raise SystemExit(
            f"Refusing to update {CONFIG_PATH}: [mcp_servers.{name}] is not a TOML table"
        )
    server["url"] = url

tmp_path = CONFIG_PATH.with_name(f".{CONFIG_PATH.name}.tmp")
tmp_fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(tmp_fd, "wb") as config_file:
    tomli_w.dump(config, config_file)
os.chmod(tmp_path, original_mode)
tmp_path.replace(CONFIG_PATH)

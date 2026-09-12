"""Merge declared workspace-write sandbox settings into the Codex config TOML.

Usage: merge-codex-workspace-write-sandbox.py <config.toml> '<json>'

The JSON object may carry `network_access` (bool) and `writable_roots`
(list of absolute paths). Targeted merge only: it sets
`sandbox_workspace_write.network_access` when declared and appends declared
`writable_roots` that are not already present, keeping any roots the user
added locally. Every other key stays untouched.
"""

import json
import os
import sys
import tomllib
from pathlib import Path

import tomli_w

CONFIG_PATH = Path(sys.argv[1])
DECLARED = json.loads(sys.argv[2])


def require_table(config: dict, key: str, path: Path) -> dict:
    value = config.setdefault(key, {})
    if not isinstance(value, dict):
        raise SystemExit(f"Refusing to update {path}: [{key}] is not a TOML table")
    return value


network_access = DECLARED.get("network_access")
if network_access is not None and not isinstance(network_access, bool):
    raise SystemExit("network_access must be a boolean when declared")

writable_roots = DECLARED.get("writable_roots", [])
if not isinstance(writable_roots, list) or not all(
    isinstance(root, str) and root.startswith("/") for root in writable_roots
):
    raise SystemExit("writable_roots must be a list of absolute paths")

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

sandbox = require_table(config, "sandbox_workspace_write", CONFIG_PATH)

if network_access is not None:
    sandbox["network_access"] = network_access

existing_roots = sandbox.get("writable_roots", [])
if not isinstance(existing_roots, list) or not all(
    isinstance(root, str) for root in existing_roots
):
    raise SystemExit(
        f"Refusing to update {CONFIG_PATH}: sandbox_workspace_write.writable_roots is not a list of strings"
    )
merged_roots = list(existing_roots)
for root in writable_roots:
    if root not in merged_roots:
        merged_roots.append(root)
if merged_roots:
    sandbox["writable_roots"] = merged_roots

tmp_path = CONFIG_PATH.with_name(f".{CONFIG_PATH.name}.tmp")
tmp_fd = os.open(tmp_path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
with os.fdopen(tmp_fd, "wb") as config_file:
    tomli_w.dump(config, config_file)
os.chmod(tmp_path, original_mode)
tmp_path.replace(CONFIG_PATH)

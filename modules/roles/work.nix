{ config, lib, overwriteHomeManagerBackups ? false, pkgs, ... }:
let
  codexTomlPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages."tomli-w"
  ]);
in
{
  home.file."go/bin/observe" = {
    source = "${pkgs.observe}/bin/observe";
    force = overwriteHomeManagerBackups;
  };

  home.packages = with pkgs; [
    kubectl
    observe
  ];

  home.sessionVariables = {
    DOTFILES_PROFILE = "work";
  };

  home.activation.workCodexNotionMcp =
    lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
      codex_config_file="${config.home.homeDirectory}/.codex/config.toml"
      codex_config_dir="$(dirname "$codex_config_file")"

      $DRY_RUN_CMD mkdir -p "$codex_config_dir"

      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would merge Notion MCP server settings into $codex_config_file"
      else
        "${codexTomlPython}/bin/python" - "$codex_config_file" <<'PY'
from pathlib import Path
import os
import sys
import tomllib

import tomli_w


CONFIG_PATH = Path(sys.argv[1])
NOTION_MCP_URL = "https://mcp.notion.com/mcp"


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
notion = mcp_servers.setdefault("notion", {})
if not isinstance(notion, dict):
    raise SystemExit(
        f"Refusing to update {CONFIG_PATH}: [mcp_servers.notion] is not a TOML table"
    )
notion["url"] = NOTION_MCP_URL

tmp_path = CONFIG_PATH.with_name(f".{CONFIG_PATH.name}.tmp")
with tmp_path.open("wb") as config_file:
    tomli_w.dump(config, config_file)
os.chmod(tmp_path, original_mode)
tmp_path.replace(CONFIG_PATH)
PY
      fi
    '';
}

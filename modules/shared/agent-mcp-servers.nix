{ config, lib, pkgs, ... }:
let
  cfg = config.dotfiles.agentMcpServers;

  codexTomlPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages."tomli-w"
  ]);

  serversJson = builtins.toJSON cfg;
in
{
  options.dotfiles.agentMcpServers = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    default = { };
    description = ''
      Remote (HTTP) MCP servers, name to URL, merged into both agents'
      otherwise-unmanaged configs at activation: `~/.codex/config.toml`
      (`[mcp_servers.<name>]` plus `features.rmcp_client`) and
      `~/.claude/.claude.json` (`mcpServers.<name>`, what
      `claude mcp add -s user` writes). The merge is targeted — declared
      servers only; other keys, servers, and OAuth state stay untouched.
    '';
  };

  config = lib.mkIf (cfg != { }) {
    home.activation.dotfilesAgentMcpServers =
      lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
        codex_config_file="${config.home.homeDirectory}/.codex/config.toml"
        claude_config_file="${config.home.homeDirectory}/.claude/.claude.json"
        servers_json=${lib.escapeShellArg serversJson}

        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          echo "Would merge MCP servers ($servers_json) into $codex_config_file and $claude_config_file"
        else
          "${codexTomlPython}/bin/python" ${../../scripts/merge-codex-mcp-servers.py} \
            "$codex_config_file" "$servers_json"
          "${pkgs.python3}/bin/python" ${../../scripts/merge-claude-mcp-servers.py} \
            "$claude_config_file" "$servers_json"
        fi
      '';
  };
}

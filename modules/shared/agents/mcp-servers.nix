{ config, lib, pkgs, platform, ... }:
let
  cfg = config.dotfiles.agentMcpServers;
  claudeStdioCfg = config.dotfiles.claudeStdioMcpServers;

  codexTomlPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages."tomli-w"
  ]);

  serversJson = builtins.toJSON cfg;
  claudeServersJson = builtins.toJSON (
    cfg
    // lib.mapAttrs (_name: server: {
      type = "stdio";
      inherit (server) command args;
    }) claudeStdioCfg
  );
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

  options.dotfiles.claudeStdioMcpServers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        command = lib.mkOption {
          type = lib.types.str;
          description = "Absolute command path for the Claude-only stdio MCP server.";
        };
        args = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Arguments passed to the Claude-only stdio MCP server.";
        };
      };
    });
    default = { };
    description = ''
      Local stdio MCP servers merged only into Claude Code's otherwise-unmanaged
      user config. Codex does not receive these entries.
    '';
  };

  config = lib.mkMerge [
    (lib.mkIf (platform == "darwin") {
      dotfiles.claudeStdioMcpServers.codex-threads = {
        command = "${pkgs.codex-thread-manager}/bin/codex-thread-manager";
        args = [ ];
      };
    })

    (lib.mkIf (cfg != { } || claudeStdioCfg != { }) {
      home.activation.dotfilesAgentMcpServers =
        lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
          codex_config_file="${config.home.homeDirectory}/.codex/config.toml"
          claude_config_file="${config.home.homeDirectory}/.claude/.claude.json"
          servers_json=${lib.escapeShellArg serversJson}
          claude_servers_json=${lib.escapeShellArg claudeServersJson}

          if [ -n "''${DRY_RUN_CMD:-}" ]; then
            echo "Would merge MCP servers ($claude_servers_json) into $claude_config_file"
            ${lib.optionalString (cfg != { }) ''
              echo "Would merge remote MCP servers ($servers_json) into $codex_config_file"
            ''}
          else
            ${lib.optionalString (cfg != { }) ''
          "${codexTomlPython}/bin/python" ${../../../scripts/merge-codex-mcp-servers.py} \
            "$codex_config_file" "$servers_json"
            ''}
          "${pkgs.python3}/bin/python" ${../../../scripts/merge-claude-mcp-servers.py} \
            "$claude_config_file" "$claude_servers_json"
          fi
        '';
    })
  ];
}

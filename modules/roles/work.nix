{ overwriteHomeManagerBackups ? false, pkgs, ... }:
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

  dotfiles.agentMcpServers.notion = "https://mcp.notion.com/mcp";

  # Work Slack lives in Claude Code via Anthropic's official Slack plugin.
  dotfiles.claudeEnabledPlugins."slack@claude-plugins-official" = true;
}

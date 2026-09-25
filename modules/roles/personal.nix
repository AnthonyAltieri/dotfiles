{
  home.sessionVariables = {
    DOTFILES_PROFILE = "personal";
  };

  # The second Claude account (anthonyraltieri+anthropic2) runs with
  # CLAUDE_CONFIG_DIR=~/.claude-anthropic2 and needs the same skills.
  dotfiles.claudeConfigDirs = [ ".claude" ".claude-anthropic2" ];
}

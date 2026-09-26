{
  home.sessionVariables = {
    DOTFILES_PROFILE = "personal";
  };

  # The second Claude account runs with CLAUDE_CONFIG_DIR=~/.claude-anthropic2.
  # This is a profile label, independent of its login email or provider.
  dotfiles.claudeConfigDirs = [ ".claude" ".claude-anthropic2" ];
}

{ pkgs, ... }:
{
  # PostgreSQL 18 client tools match the personal trading stack's PostgreSQL 18 servers;
  # pg_dump refuses to back up a newer server major.
  home.packages = [ pkgs.postgresql_18 ];

  home.sessionVariables = {
    DOTFILES_PROFILE = "personal";
  };

  # The second Claude account runs with CLAUDE_CONFIG_DIR=~/.claude-anthropic2.
  # This is a profile label, independent of its login email or provider.
  dotfiles.claudeConfigDirs = [ ".claude" ".claude-anthropic2" ];
}

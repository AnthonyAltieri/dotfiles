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

  # Without these, auto mode blocks routine operations on the user's own hub
  # (restarts, stuck processes, scratch caches) and sessions hand the command
  # back for the user to run.
  dotfiles.claudeAutoMode = {
    environment = [
      "This is the user's personal single-user Linux hub. The user owns every repository under ~/code, the GitHub repositories under github.com/AnthonyAltieri, and the services running on this machine."
      "The trading and spans stacks on this machine (systemd user units, local services, deploy scripts) are the user's own development and personal-production services, not shared infrastructure."
    ];
    allow = [
      "Starting, stopping, restarting, or redeploying the user's own services on this machine when the task calls for it, including the trading and spans stack scripts, `systemctl --user` units, and deploy scripts under ~/.cache/spawn-orchestrator."
      "Killing a stuck or orphaned process that the user's own stacks or agent workers started."
      "Deleting rebuildable caches and scratch output (package stores, build output, diagnostics) under /tmp or ~/.cache that agent sessions created, as long as no running worker still uses it."
    ];
  };
}

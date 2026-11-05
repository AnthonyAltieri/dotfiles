{ config, lib, ... }:
{
  # `rex skill setup` installs Rex's skill stub (~/.claude/skills/rex and
  # ~/.agents/skills/rex) and its SessionStart hook. The stub reads its guide
  # from the installed rex, so Rex keeps owning the text. Claude's hook is also
  # declared in home/.claude/settings.json, because that file is a managed copy
  # rewritten on every switch; setup then finds it current and leaves the file
  # alone. On macOS the Rex app installs rex in ~/.local/bin; on Linux it comes
  # from the Rex Home Manager module.
  home.activation.dotfilesRexAgentSkill =
    lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
      rex_bin=""
      for candidate in \
        "${config.home.homeDirectory}/.local/bin/rex" \
        "${config.home.profileDirectory}/bin/rex"; do
        if [ -x "$candidate" ]; then
          rex_bin="$candidate"
          break
        fi
      done

      if [ -n "$rex_bin" ]; then
        dry_run_flag=""
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          dry_run_flag="--dry-run"
        fi
        "$rex_bin" skill setup --autostart=false $dry_run_flag >/dev/null \
          || echo "warning: rex skill setup failed; run it by hand" >&2
      fi
      unset rex_bin candidate dry_run_flag
    '';
}

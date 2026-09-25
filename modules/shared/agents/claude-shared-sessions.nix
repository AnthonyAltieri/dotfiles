{ config, lib, pkgs, ... }:
let
  configDirs = map (dir: "${config.home.homeDirectory}/${dir}") config.dotfiles.claudeConfigDirs;
in
{
  # Extra Claude accounts share the first config dir's conversation history, so
  # `claude --resume` shows every session whichever account is signed in.
  config = lib.mkIf (lib.length configDirs > 1) {
    home.activation.dotfilesClaudeSharedSessions = lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
      if [ -n "''${DRY_RUN_CMD:-}" ]; then
        echo "Would share Claude session history across: ${lib.concatStringsSep ", " configDirs}"
      else
        ${pkgs.bash}/bin/bash ${../../../scripts/share-claude-sessions.sh} ${lib.escapeShellArgs configDirs}
      fi
    '';
  };
}

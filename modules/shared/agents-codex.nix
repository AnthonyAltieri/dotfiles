{ config, lib, ... }:
let
  rulesDir = "${config.home.homeDirectory}/.codex/rules";
  defaultRules = "${rulesDir}/default.rules";
  backupRules = "${defaultRules}.hm-backup";
in {
  home.sessionVariables = {
    CODEX_HOME = "$HOME/.codex";
  };

  home.activation.codexLocalDefaultRules =
    lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      rules_dir="${rulesDir}"
      default_rules="${defaultRules}"
      backup_rules="${backupRules}"

      $DRY_RUN_CMD mkdir -p "$rules_dir"

      if [ -L "$default_rules" ]; then
        $DRY_RUN_CMD rm -f "$default_rules"
      fi

      if [ ! -e "$default_rules" ]; then
        if [ -f "$backup_rules" ]; then
          $DRY_RUN_CMD cp "$backup_rules" "$default_rules"
        else
          $DRY_RUN_CMD touch "$default_rules"
        fi
      fi

      $DRY_RUN_CMD chmod u+rw "$default_rules"
    '';
}

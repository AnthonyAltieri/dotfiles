{ config, lib, pkgs, ... }:
let
  cfg = config.dotfiles.codexWorkspaceWriteSandbox;
  homeDir = config.home.homeDirectory;

  rulesDir = "${homeDir}/.codex/rules";
  defaultRules = "${rulesDir}/default.rules";
  backupRules = "${defaultRules}.hm-backup";

  codexTomlPython = pkgs.python3.withPackages (pythonPackages: [
    pythonPackages."tomli-w"
  ]);

  # Roots are declared relative to the home directory so the same role works
  # for any login user; absolute entries (sockets under /var, for example)
  # pass through unchanged.
  resolveRoot = root:
    if lib.hasPrefix "/" root then root else "${homeDir}/${root}";

  declaredSandbox =
    lib.optionalAttrs (cfg.networkAccess != null) { network_access = cfg.networkAccess; }
    // { writable_roots = map resolveRoot cfg.writableRoots; };

  sandboxJson = builtins.toJSON declaredSandbox;
  sandboxDeclared = cfg.networkAccess != null || cfg.writableRoots != [ ];
in {
  options.dotfiles.codexWorkspaceWriteSandbox = {
    networkAccess = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = ''
        Value written to `sandbox_workspace_write.network_access` in
        `~/.codex/config.toml`. Null leaves the key untouched.
      '';
    };

    writableRoots = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [ ".cache/bazel" "/var/run/docker.sock" ];
      description = ''
        Paths appended to `sandbox_workspace_write.writable_roots` in
        `~/.codex/config.toml`. Relative entries resolve against the home
        directory; absolute entries are kept as written. Roots the user added
        locally are preserved.
      '';
    };
  };

  config = lib.mkMerge [
    {
      home.activation.codexLocalDefaultRules =
        lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
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

    (lib.mkIf sandboxDeclared {
      home.activation.dotfilesCodexWorkspaceWriteSandbox =
        lib.hm.dag.entryAfter [ "dotfilesAgentManagedCopies" ] ''
          codex_config_file="${homeDir}/.codex/config.toml"
          sandbox_json=${lib.escapeShellArg sandboxJson}

          if [ -n "''${DRY_RUN_CMD:-}" ]; then
            echo "Would merge workspace-write sandbox settings ($sandbox_json) into $codex_config_file"
          else
            "${codexTomlPython}/bin/python" ${../../../scripts/merge-codex-workspace-write-sandbox.py} \
              "$codex_config_file" "$sandbox_json"
          fi
        '';
    })
  ];
}

{ config, lib, pkgs, platform, role, ... }:
let
  managedCopy = {
    target,
    source,
    kind,
    executable ? false,
  }: {
    inherit target source kind executable;
  };

  managedFile = target: source:
    managedCopy {
      inherit target source;
      kind = "file";
    };

  managedExecutableFile = target: source:
    managedCopy {
      inherit target source;
      kind = "file";
      executable = true;
    };

  managedDirectory = target: source:
    managedCopy {
      inherit target source;
      kind = "directory";
    };

  sharedSkillNames = [
    "agent-code-review-loop"
    "frontend-design"
    "handoff"
    "improve-codebase-architecture"
    "notion-knowledge-capture"
    "notion-read"
    "programming"
    "sql-read"
  ];

  codexOnlySkillNames = [
    "adversarial-review"
    "generate-sprite-sheets"
    "gh-ci"
    "gh-pr-body"
    "gh-comments"
    "linear-claim-work"
    "ultragoal"
  ];

  claudeOnlySkillNames = [
    "gh-address-comments"
    "gh-fix-ci"
    "gh-manage-pr"
  ];

  workOnlySkillNames = [
    "observe"
  ];

  darwinOnlySkillNames = [
    "atlas"
  ];

  agentSkillCopies = agentName: sourceRoot: skillNames:
    map (
      skillName:
      managedDirectory ".${agentName}/skills/${skillName}" (sourceRoot + "/${skillName}")
    ) skillNames;

  codexSkillCopies = agentSkillCopies "codex" ../../home/.codex/skills;
  claudeSkillCopies = agentSkillCopies "claude" ../../home/.claude/skills;

  sharedAgentManagedCopies =
    [
      (managedFile ".codex/AGENTS.md" ../../home/.codex/AGENTS.md)
      (managedDirectory ".codex/prompts" ../../home/.codex/prompts)
      (managedFile ".codex/rules/base.rules" ../../home/.codex/rules/base.rules)
    ]
    ++ codexSkillCopies sharedSkillNames
    ++ codexSkillCopies codexOnlySkillNames
    ++ lib.optionals (platform == "darwin") (
      codexSkillCopies darwinOnlySkillNames
    )
    ++ [
      (managedFile ".claude/CLAUDE.md" ../../home/.claude/CLAUDE.md)
      (managedFile ".claude/README.md" ../../home/.claude/README.md)
      (managedFile ".claude/settings.json" ../../home/.claude/settings.json)
      (managedDirectory ".claude/commands" ../../home/.claude/commands)
    ]
    ++ claudeSkillCopies sharedSkillNames
    ++ claudeSkillCopies claudeOnlySkillNames
    ++ lib.optionals (platform == "darwin") (
      claudeSkillCopies darwinOnlySkillNames
    )
    ++ [
      (managedExecutableFile ".claude/statusline-command.sh" ../../home/.claude/statusline-command.sh)
      (managedExecutableFile ".claude/tmux-notify.sh" ../../home/.claude/tmux-notify.sh)
    ];

  workOnlyAgentManagedCopies = lib.optionals (role == "work") (
    codexSkillCopies workOnlySkillNames
    ++ claudeSkillCopies workOnlySkillNames
  );

  targetIsSafe = target:
    let
      segments = lib.splitString "/" target;
    in
      target != ""
      && !(lib.hasPrefix "/" target)
      && !(lib.hasInfix "\n" target)
      && !(lib.hasInfix "\t" target)
      && !(lib.elem "" segments)
      && !(lib.elem "." segments)
      && !(lib.elem ".." segments);

  rawAgentManagedCopies = sharedAgentManagedCopies ++ workOnlyAgentManagedCopies;

  unsafeTargets = lib.filter (entry: !(targetIsSafe entry.target)) rawAgentManagedCopies;

  agentManagedCopies =
    assert lib.assertMsg (unsafeTargets == [])
      "Unsafe dotfiles.agentManagedCopies targets: ${lib.concatStringsSep ", " (map (entry: entry.target) unsafeTargets)}";
    rawAgentManagedCopies;

  manifestType = lib.types.listOf (
    lib.types.submodule {
      options = {
        target = lib.mkOption {
          type = lib.types.str;
          description = "Path relative to the user's home directory.";
        };
        source = lib.mkOption {
          type = lib.types.path;
          description = "Source path in the Nix store.";
        };
        kind = lib.mkOption {
          type = lib.types.enum [
            "directory"
            "file"
          ];
          description = "Whether the copied payload is a file or directory.";
        };
        executable = lib.mkOption {
          type = lib.types.bool;
          description = "Whether the copied file should be executable.";
        };
      };
    }
  );

  currentManifestFile = builtins.toFile "dotfiles-agent-managed-copies.tsv" (
    lib.concatStringsSep "\n" (
      map (
        entry:
        lib.concatStringsSep "\t" [
          entry.target
          entry.kind
          (if entry.executable then "1" else "0")
          (toString entry.source)
        ]
      ) agentManagedCopies
    )
    + "\n"
  );

  currentPathsFile = builtins.toFile "dotfiles-agent-managed-copy-paths.txt" (
    lib.concatStringsSep "\n" (map (entry: entry.target) agentManagedCopies)
    + "\n"
  );
in
{
  options.dotfiles.agentManagedCopies = lib.mkOption {
    type = manifestType;
    readOnly = true;
    description = "Managed Codex and Claude files copied into place as regular files.";
  };

  config = {
    dotfiles.agentManagedCopies = agentManagedCopies;

    home.activation.migrateSqlReadState = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      legacy_codex="$HOME/.codex/skills/sql-read/state/targets.json"
      legacy_claude="$HOME/.claude/skills/sql-read/state/targets.json"

      if [ -f "$legacy_codex" ] || [ -f "$legacy_claude" ]; then
        if [ -n "''${DRY_RUN_CMD:-}" ]; then
          echo "Would migrate legacy SQL Read target state into ${config.xdg.stateHome}/sql-read/targets.json"
        else
          ${pkgs.bash}/bin/bash ${../../scripts/migrate-sql-read-state.sh} \
            ${pkgs.jq}/bin/jq \
            "${config.xdg.stateHome}/sql-read/targets.json" \
            "$legacy_codex" \
            "$legacy_claude"
        fi
      fi
    '';

    home.activation.dotfilesAgentManagedCopies = lib.hm.dag.entryAfter [
      "linkGeneration"
      "migrateSqlReadState"
    ] ''
      state_dir="${config.xdg.stateHome}/dotfiles"
      previous_paths_file="$state_dir/agent-managed-copy-paths.txt"
      tmp_previous_paths_file="$state_dir/agent-managed-copy-paths.txt.tmp"
      current_manifest_file="${currentManifestFile}"
      current_paths_file="${currentPathsFile}"

      dotfiles_safe_managed_target() {
        local target="$1"
        local part=""
        local -a parts=()

        case "$target" in
          ""|/*|*'//'*)
            return 1
            ;;
        esac
        if [[ "$target" == *$'\t'* || "$target" == *$'\n'* ]]; then
          return 1
        fi

        IFS='/' read -r -a parts <<< "$target"
        for part in "''${parts[@]}"; do
          case "$part" in
            ""|"."|"..")
              return 1
              ;;
          esac
        done

        return 0
      }

      dotfiles_managed_target_path() {
        local target="$1"

        if ! dotfiles_safe_managed_target "$target"; then
          echo "Refusing unsafe managed copy target: $target" >&2
          return 1
        fi

        printf '%s/%s\n' "$HOME" "$target"
      }

      $DRY_RUN_CMD mkdir -p "$state_dir"

      if [ -f "$previous_paths_file" ]; then
        while IFS= read -r old_target; do
          [ -n "$old_target" ] || continue

          if ! grep -Fqx "$old_target" "$current_paths_file"; then
            target_path="$(dotfiles_managed_target_path "$old_target")" || exit 1

            if [ -e "$target_path" ] || [ -L "$target_path" ]; then
              $DRY_RUN_CMD rm -rf "$target_path"
            fi
          fi
        done < "$previous_paths_file"
      fi

      while IFS=$'\t' read -r target kind executable source; do
        [ -n "$target" ] || continue

        target_path="$(dotfiles_managed_target_path "$target")" || exit 1
        parent_dir="$(dirname "$target_path")"

        $DRY_RUN_CMD mkdir -p "$parent_dir"

        if [ -e "$target_path" ] || [ -L "$target_path" ]; then
          $DRY_RUN_CMD rm -rf "$target_path"
        fi

        case "$kind" in
          directory)
            $DRY_RUN_CMD cp -RL "$source" "$target_path"
            $DRY_RUN_CMD chmod -R u+w "$target_path"
            ;;
          file)
            $DRY_RUN_CMD cp -L "$source" "$target_path"
            $DRY_RUN_CMD chmod u+w "$target_path"
            if [ "$executable" = "1" ]; then
              $DRY_RUN_CMD chmod u+x "$target_path"
            fi
            ;;
          *)
            echo "Unknown managed copy kind: $kind" >&2
            exit 1
            ;;
        esac
      done < "$current_manifest_file"

      # Copy via a temp file so the persisted state does not inherit the
      # Nix store's read-only mode and break the next activation.
      $DRY_RUN_CMD rm -f "$tmp_previous_paths_file"
      $DRY_RUN_CMD cp "$current_paths_file" "$tmp_previous_paths_file"
      $DRY_RUN_CMD chmod 600 "$tmp_previous_paths_file"
      $DRY_RUN_CMD mv -f "$tmp_previous_paths_file" "$previous_paths_file"
    '';
  };
}

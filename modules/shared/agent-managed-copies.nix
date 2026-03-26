{ config, lib, ... }:
let
  agentManagedCopies = [
    {
      target = ".codex/AGENTS.md";
      source = ../../home/.codex/AGENTS.md;
      kind = "file";
      executable = false;
    }
    {
      target = ".codex/prompts";
      source = ../../home/.codex/prompts;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/rules/base.rules";
      source = ../../home/.codex/rules/base.rules;
      kind = "file";
      executable = false;
    }
    {
      target = ".codex/skills/atlas";
      source = ../../home/.codex/skills/atlas;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/frontend-design";
      source = ../../home/.codex/skills/frontend-design;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/gh-address-comments";
      source = ../../home/.codex/skills/gh-address-comments;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/gh-fix-ci";
      source = ../../home/.codex/skills/gh-fix-ci;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/gh-manage-pr";
      source = ../../home/.codex/skills/gh-manage-pr;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/notion-knowledge-capture";
      source = ../../home/.codex/skills/notion-knowledge-capture;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/programming";
      source = ../../home/.codex/skills/programming;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/spaces";
      source = ../../home/.codex/skills/spaces;
      kind = "directory";
      executable = false;
    }
    {
      target = ".codex/skills/sql-read";
      source = ../../home/.codex/skills/sql-read;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/README.md";
      source = ../../home/.claude/README.md;
      kind = "file";
      executable = false;
    }
    {
      target = ".claude/settings.json";
      source = ../../home/.claude/settings.json;
      kind = "file";
      executable = false;
    }
    {
      target = ".claude/commands";
      source = ../../home/.claude/commands;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/atlas";
      source = ../../home/.claude/skills/atlas;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/frontend-design";
      source = ../../home/.claude/skills/frontend-design;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/gh-address-comments";
      source = ../../home/.claude/skills/gh-address-comments;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/gh-fix-ci";
      source = ../../home/.claude/skills/gh-fix-ci;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/gh-manage-pr";
      source = ../../home/.claude/skills/gh-manage-pr;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/notion-knowledge-capture";
      source = ../../home/.claude/skills/notion-knowledge-capture;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/programming";
      source = ../../home/.claude/skills/programming;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/spaces";
      source = ../../home/.claude/skills/spaces;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/skills/sql-read";
      source = ../../home/.claude/skills/sql-read;
      kind = "directory";
      executable = false;
    }
    {
      target = ".claude/statusline-command.sh";
      source = ../../home/.claude/statusline-command.sh;
      kind = "file";
      executable = true;
    }
    {
      target = ".claude/tmux-notify.sh";
      source = ../../home/.claude/tmux-notify.sh;
      kind = "file";
      executable = true;
    }
  ];

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

    home.activation.dotfilesAgentManagedCopies = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      state_dir="${config.xdg.stateHome}/dotfiles"
      previous_paths_file="$state_dir/agent-managed-copy-paths.txt"
      tmp_previous_paths_file="$state_dir/agent-managed-copy-paths.txt.tmp"
      current_manifest_file="${currentManifestFile}"
      current_paths_file="${currentPathsFile}"

      $DRY_RUN_CMD mkdir -p "$state_dir"

      if [ -f "$previous_paths_file" ]; then
        while IFS= read -r old_target; do
          [ -n "$old_target" ] || continue

          if ! grep -Fqx "$old_target" "$current_paths_file"; then
            target_path="$HOME/$old_target"

            if [ -e "$target_path" ] || [ -L "$target_path" ]; then
              $DRY_RUN_CMD rm -rf "$target_path"
            fi
          fi
        done < "$previous_paths_file"
      fi

      while IFS=$'\t' read -r target kind executable source; do
        [ -n "$target" ] || continue

        target_path="$HOME/$target"
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

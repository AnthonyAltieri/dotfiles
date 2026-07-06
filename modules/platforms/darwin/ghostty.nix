{ config, lib, overwriteHomeManagerBackups ? false, pkgs, ... }:
let
  ghosttySource = ../../../home/.config/ghostty;
  detectBerkeleyMonoFont = ../../../scripts/detect-berkeley-mono-font.sh;
  overwriteExisting = if overwriteHomeManagerBackups then "1" else "0";
in
{
  home.activation.dotfilesGhosttyConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
    ghostty_source="${ghosttySource}"
    ghostty_font="$(${pkgs.bash}/bin/bash ${detectBerkeleyMonoFont} 2>/dev/null || true)"
    overwrite_existing="${overwriteExisting}"

    dotfiles_patch_ghostty_font() {
      local config_file="$1"
      local font_name="$2"
      local tmp_config="$config_file.tmp"

      [ -n "$font_name" ] || return 0

      if [ ! -f "$config_file" ]; then
        echo "Ghostty config file does not exist: $config_file" >&2
        exit 1
      fi

      ${pkgs.gawk}/bin/awk -v font="$font_name" '
        /^font-family[[:space:]]*=/ {
          print "font-family = \"" font "\""
          next
        }
        /^window-title-font-family[[:space:]]*=/ {
          print "window-title-font-family = \"" font "\""
          next
        }
        { print }
      ' "$config_file" > "$tmp_config"
      ${pkgs.coreutils}/bin/mv "$tmp_config" "$config_file"
    }

    dotfiles_prepare_ghostty_target() {
      local target="$1"
      local marker="$target/.dotfiles-managed"
      local backup="$target.hm-backup"

      if [ ! -e "$target" ] && [ ! -L "$target" ]; then
        return 0
      fi

      if [ -L "$target" ] || [ -f "$marker" ] || [ "$overwrite_existing" = "1" ]; then
        $DRY_RUN_CMD ${pkgs.coreutils}/bin/rm -rf "$target"
        return 0
      fi

      if [ -e "$backup" ] || [ -L "$backup" ]; then
        echo "Refusing to replace unmanaged Ghostty config because backup already exists: $backup" >&2
        exit 1
      fi

      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mv "$target" "$backup"
    }

    dotfiles_install_ghostty_config() {
      local target="$1"
      local parent

      parent="$(${pkgs.coreutils}/bin/dirname "$target")"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "$parent"
      dotfiles_prepare_ghostty_target "$target"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp -RL "$ghostty_source" "$target"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/chmod -R u+w "$target"

      if [ -n "$DRY_RUN_CMD" ]; then
        if [ -n "$ghostty_font" ]; then
          echo "Would set Ghostty Berkeley Mono font to: $ghostty_font"
        else
          echo "Would leave Ghostty font at committed default; no Berkeley Mono font detected."
        fi
        return 0
      fi

      printf 'managed by dotfiles Home Manager activation\n' > "$target/.dotfiles-managed"
      dotfiles_patch_ghostty_font "$target/config" "$ghostty_font"
    }

    if [ -n "$ghostty_font" ]; then
      echo "Using Ghostty Berkeley Mono font: $ghostty_font"
    else
      echo "No Berkeley Mono font detected; leaving Ghostty font at committed default." >&2
    fi

    dotfiles_install_ghostty_config "${config.xdg.configHome}/ghostty"
    dotfiles_install_ghostty_config "$HOME/Library/Application Support/com.mitchellh.ghostty"
  '';
}

{ lib, pkgs, ... }:
{
  # nix-darwin runs Homebrew before Home Manager. Keep Node in the same nvm
  # home used by zsh, and provision it during activation rather than startup.
  home.activation.dotfilesNvmDefault = lib.hm.dag.entryAfter [ "installPackages" ] ''
    NVM_DIR="$HOME/.nvm" \
      DRY_RUN_CMD="''${DRY_RUN_CMD:-}" \
      PATH="$PATH:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin" \
      ${pkgs.bash}/bin/bash ${../../../../scripts/ensure-nvm-default.sh}
  '';
}

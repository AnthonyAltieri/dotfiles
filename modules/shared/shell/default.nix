{ lib, pkgs, platform, role, ... }:
let
  # On non-sandbox Darwin starship comes from Homebrew;
  # everywhere else it comes from nixpkgs.
  useNixPackages = platform == "linux" || role == "sandbox";
in
{
  imports = [
    ./zsh.nix
    ./tmux.nix
  ];

  home.packages = lib.optionals useNixPackages [
    pkgs.starship
  ];
}

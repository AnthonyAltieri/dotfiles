{ lib, pkgs, platform, role, ... }:
let
  # On non-sandbox Darwin the editor binaries come from Homebrew;
  # everywhere else they come from nixpkgs.
  useNixPackages = platform == "linux" || role == "sandbox";
in
{
  imports = [ ./neovim.nix ];

  home.packages = lib.optionals useNixPackages [
    pkgs.neovim
    pkgs.vim
  ];
}

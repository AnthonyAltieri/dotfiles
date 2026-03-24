{ lib, pkgs, platform, role, ... }:
{
  home.packages =
    lib.optionals (platform == "linux" || role == "sandbox") [
      pkgs.neovim
    ];
}

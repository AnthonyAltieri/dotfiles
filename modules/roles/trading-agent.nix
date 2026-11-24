{ inputs, pkgs, username, homeDirectory, ... }:
let
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  systemd.user.enable = false;

  home = {
    inherit username homeDirectory;
    stateVersion = "25.05";

    packages = (with pkgs; [
      dbmate
      git
      jq
      nodejs # Also provides Corepack for `cli.py deps`.
      pnpm
      python3
      sccache
      uv
    ]) ++ [
      unstable.cargo
      unstable.clippy
      unstable.rustc
    ];
  };
}

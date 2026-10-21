{ inputs, pkgs, ... }:
let
  # nixpkgs 25.05 stops at Rust 1.86; Cargo's split build-dir (shared intermediates, private
  # final artifacts) is stable from 1.91. Install the newer toolchain directly instead of
  # overlaying rustc/cargo, which would rebuild every Rust package in nixpkgs from source.
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
in
{
  home.packages = with pkgs; [
    _1password-cli
    bat
    bun
    fd
    fzf
    gh
    git
    jq
    nodejs
    pnpm
    tree-sitter
    uv
  ] ++ [
    unstable.cargo
    unstable.rustc
  ];
}

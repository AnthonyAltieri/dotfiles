{ pkgs, ... }:
{
  home.packages = with pkgs; [
    _1password-cli
    bat
    bun
    cargo
    fd
    fzf
    gh
    git
    jq
    nodejs
    pnpm
    rustc
    tree-sitter
    uv
  ];
}

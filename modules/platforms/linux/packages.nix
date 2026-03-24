{ pkgs, ... }:
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
    ripgrep
    uv
  ];
}

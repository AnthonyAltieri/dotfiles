{ pkgs, ... }:
{
  home.packages = with pkgs; [
    _1password-cli
    bat
    bun
    fd
    fzf
    git
    jq
    mcfly
    nodejs
    pnpm
    ripgrep
  ];
}

{ pkgs, ... }:
{
  home.packages = with pkgs; [
    bat
    bun
    fd
    fzf
    git
    jq
    nodejs
    pnpm
    ripgrep
  ];

  home.sessionVariables = {
    CODEX_SANDBOX = "1";
    DOTFILES_PROFILE = "sandbox";
  };
}

{ pkgs, ... }:
{
  home.packages = with pkgs; [
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

  home.sessionVariables = {
    CODEX_SANDBOX = "1";
    DOTFILES_PROFILE = "sandbox";
  };
}

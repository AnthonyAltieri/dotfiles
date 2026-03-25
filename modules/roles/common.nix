{ pkgs, ... }:
{
  home.packages = with pkgs; [
    ripgrep
  ];

  home.sessionVariables = {
    DOTFILES_COMMON = "1";
  };

  programs.zsh.oh-my-zsh = {
    enable = true;
    plugins = [
      "git"
      "npm"
      "z"
    ];
    theme = "robbyrussell";
  };
}

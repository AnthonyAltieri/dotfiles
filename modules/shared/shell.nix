{ lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "npm"
        "z"
      ];
      theme = "robbyrussell";
    };
    initExtra = lib.mkOrder 1000 (builtins.readFile ../../home/.zshrc);
  };
}

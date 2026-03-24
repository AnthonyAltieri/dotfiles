{ lib, ... }:
{
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    enableAutosuggestions = true;
    enableSyntaxHighlighting = true;
    initExtra = lib.mkOrder 1000 (builtins.readFile ../../home/.zshrc);
  };
}

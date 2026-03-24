{ lib, platform, ... }:
let
  brewShellInit = lib.optionalString (platform == "darwin") ''
    if [[ -x /opt/homebrew/bin/brew ]]; then
      eval "$(/opt/homebrew/bin/brew shellenv zsh)"
    elif [[ -x /usr/local/bin/brew ]]; then
      eval "$(/usr/local/bin/brew shellenv zsh)"
    fi
  '';
in {
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    initContent = lib.mkOrder 1000 (brewShellInit + builtins.readFile ../../home/.zshrc);
  };
}

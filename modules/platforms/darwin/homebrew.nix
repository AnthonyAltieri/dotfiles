{ lib, role, ... }:
let
  privateWorkHomebrewItems = envName:
    lib.optionals (role == "work")
      (lib.filter (tap: tap != "")
        (lib.splitString ":" (builtins.getEnv envName)));
  privateWorkHomebrewTaps = privateWorkHomebrewItems "DOTFILES_WORK_HOMEBREW_TAPS";
  privateWorkHomebrewCasks = privateWorkHomebrewItems "DOTFILES_WORK_HOMEBREW_CASKS";
in
{
  homebrew = {
    enable = true;

    taps = [
      "oven-sh/bun"
    ] ++ privateWorkHomebrewTaps;

    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = false;
    };

    global = {
      autoUpdate = false;
      brewfile = true;
    };

    brews = [
      "bat"
      "oven-sh/bun/bun"
      "fd"
      "fzf"
      "gh"
      "git"
      "jq"
      "neovim"
      "nvm"
      "ripgrep"
      "rust"
      "starship"
      "tree-sitter"
      "tmux"
      "uv"
      "vim"
    ];

    casks = [
      "1password-cli"
      "ghostty"
      "raycast"
    ] ++ privateWorkHomebrewCasks;
  };
}

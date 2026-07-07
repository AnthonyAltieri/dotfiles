{ lib, role, ... }:
let
  splitNonEmpty = separator: value:
    lib.filter (item: item != "") (lib.splitString separator value);

  privateWorkHomebrewItems = envName:
    lib.optionals (role == "work")
      (splitNonEmpty ":" (builtins.getEnv envName));

  parseTapCloneTargetSpec = spec:
    let
      parts = lib.splitString "=" spec;
      name = builtins.head parts;
      clone_target = lib.concatStringsSep "=" (builtins.tail parts);
    in
      if builtins.length parts < 2 || name == "" || clone_target == "" then
        throw "Invalid DOTFILES_WORK_HOMEBREW_TAP_CLONE_TARGETS entry '${spec}'. Expected name=clone_target."
      else
        {
          inherit name clone_target;
        };

  privateWorkHomebrewTapCloneTargets =
    lib.optionals (role == "work")
      (map parseTapCloneTargetSpec
        (splitNonEmpty ";" (builtins.getEnv "DOTFILES_WORK_HOMEBREW_TAP_CLONE_TARGETS")));

  privateWorkHomebrewTapCloneTargetNames =
    map (tap: tap.name) privateWorkHomebrewTapCloneTargets;

  privateWorkHomebrewTaps =
    (lib.filter
      (tap: !(builtins.elem tap privateWorkHomebrewTapCloneTargetNames))
      (privateWorkHomebrewItems "DOTFILES_WORK_HOMEBREW_TAPS"))
    ++ privateWorkHomebrewTapCloneTargets;

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

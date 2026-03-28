{ lib, username, homeDirectory, role, platform, ... }:
let
  homebrewSessionPath = lib.optionals (platform == "darwin") [
    "/opt/homebrew/bin"
    "/opt/homebrew/sbin"
    "/usr/local/bin"
    "/usr/local/sbin"
  ];
in
{
  programs.home-manager.enable = true;

  xdg.enable = true;

  home = {
    username = lib.mkDefault username;
    homeDirectory = lib.mkDefault homeDirectory;
    stateVersion = "25.05";
    sessionPath = homebrewSessionPath ++ [
      "$HOME/.cargo/bin"
      "$HOME/.local/bin"
      "$HOME/.poetry/bin"
      "$HOME/.warpstream"
    ];
    sessionVariables = {
      CODEX_HOME = "$HOME/.codex";
      DOTFILES_PLATFORM = platform;
      DOTFILES_ROLE = role;
      EDITOR = "nvim";
      VISUAL = "nvim";
    };
  };

  targets.genericLinux.enable = platform == "linux";
}

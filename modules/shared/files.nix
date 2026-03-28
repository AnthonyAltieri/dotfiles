{ overwriteHomeManagerBackups ? false, ... }:
let
  managedFile = source: {
    inherit source;
    force = overwriteHomeManagerBackups;
  };

  managedTree = source: {
    inherit source;
    recursive = true;
    force = overwriteHomeManagerBackups;
  };
in
{
  home.file = {
    ".vimrc" = managedFile ../../home/.vimrc;
  };

  xdg.configFile = {
    "nvim" = managedTree ../../home/.config/nvim;
    "starship.toml" = managedFile ../../home/.config/starship.toml;
    "zsh" = managedTree ../../home/.config/zsh;
  };
}

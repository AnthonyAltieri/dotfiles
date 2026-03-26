{
  home.file = {
    ".vimrc".source = ../../home/.vimrc;
  };

  xdg.configFile = {
    "nvim" = {
      source = ../../home/.config/nvim;
      recursive = true;
    };
    "starship.toml".source = ../../home/.config/starship.toml;
    "zsh" = {
      source = ../../home/.config/zsh;
      recursive = true;
    };
  };
}

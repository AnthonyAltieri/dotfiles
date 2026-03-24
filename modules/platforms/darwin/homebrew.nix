{
  homebrew = {
    enable = true;

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
      "bun"
      "fd"
      "fzf"
      "gh"
      "git"
      "jq"
      "neovim"
      "nvm"
      "pnpm"
      "ripgrep"
      "starship"
      "tmux"
      "uv"
      "vim"
    ];

    casks = [
      "1password-cli"
      "ghostty"
      "raycast"
    ];
  };
}

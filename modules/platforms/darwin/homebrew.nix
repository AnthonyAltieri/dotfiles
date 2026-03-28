{
  homebrew = {
    enable = true;

    taps = [
      "oven-sh/bun"
    ];

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

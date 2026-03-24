{
  homebrew = {
    enable = true;
    enableZshIntegration = true;

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
      "git"
      "jq"
      "mcfly"
      "neovim"
      "nvm"
      "pnpm"
      "ripgrep"
      "starship"
      "tmux"
      "vim"
    ];

    casks = [
      "1password-cli"
      "ghostty"
    ];
  };
}

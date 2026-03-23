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
      "1password-cli"
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
      "ghostty"
    ];
  };
}

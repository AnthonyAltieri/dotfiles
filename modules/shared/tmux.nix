{ pkgs, platform, role, ... }:
let
  tmuxPackage =
    if platform == "darwin" && role != "sandbox"
    then pkgs.writeShellScriptBin "tmux" ''
      if [ ! -x /opt/homebrew/bin/tmux ]; then
        echo "Expected Homebrew tmux at /opt/homebrew/bin/tmux" >&2
        exit 1
      fi

      exec /opt/homebrew/bin/tmux "$@"
    ''
    else pkgs.tmux;
in {
  programs.tmux = {
    enable = true;
    package = tmuxPackage;
    plugins = with pkgs.tmuxPlugins; [
      sensible
      vim-tmux-navigator
    ];
    extraConfig = builtins.readFile ../../home/.config/tmux/tmux.conf;
  };
}

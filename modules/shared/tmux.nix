{ overwriteHomeManagerBackups ? false, pkgs, platform, role, ... }:
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
  xdg.configFile."tmux/tmux.conf" = {
    force = overwriteHomeManagerBackups;
    # Repair a running server without starting one during activation.
    onChange = ''
      ${tmuxPackage}/bin/tmux -N set-environment -gu NO_COLOR 2>/dev/null || true
    '';
  };

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

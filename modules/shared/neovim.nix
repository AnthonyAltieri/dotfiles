{ config, lib, pkgs, platform, role, ... }:
let
  nvimCandidates =
    if platform == "darwin" && role != "sandbox" then [
      "/opt/homebrew/bin/nvim"
      "/usr/local/bin/nvim"
    ] else [
      "${pkgs.neovim}/bin/nvim"
    ];

  nvimCandidateArgs = lib.concatMapStringsSep " " lib.escapeShellArg nvimCandidates;

  bootstrapPath = lib.concatStringsSep ":" (
    lib.optionals (platform == "darwin") [
      "/opt/homebrew/bin"
      "/opt/homebrew/sbin"
      "/usr/local/bin"
      "/usr/local/sbin"
      "/usr/bin"
      "/bin"
      "/usr/sbin"
      "/sbin"
    ]
    ++ lib.optionals (platform != "darwin") [
      "${pkgs.git}/bin"
      "${pkgs.gnumake}/bin"
      "${pkgs.gcc}/bin"
      "${pkgs.unzip}/bin"
      "/usr/bin"
      "/bin"
    ]
  );
in
{
  home.packages =
    lib.optionals (platform == "linux" || role == "sandbox") [
      pkgs.neovim
    ];

  home.activation.dotfilesPrewarmNeovim = lib.hm.dag.entryAfter [
    "linkGeneration"
    "installPackages"
  ] ''
    nvim_data_dir="${config.xdg.dataHome}/nvim"
    nvim_state_dir="${config.xdg.stateHome}/nvim"
    nvim_lock_dir="$nvim_state_dir/lazy"
    config_lockfile="${config.xdg.configHome}/nvim/lazy-lock.json"
    state_lockfile="$nvim_lock_dir/lazy-lock.json"
    needs_prewarm=0

    $DRY_RUN_CMD mkdir -p "$nvim_data_dir" "$nvim_lock_dir"

    if [ -f "$config_lockfile" ]; then
      if [ ! -f "$state_lockfile" ] || ! cmp -s "$config_lockfile" "$state_lockfile"; then
        $DRY_RUN_CMD cp "$config_lockfile" "$state_lockfile"
        $DRY_RUN_CMD chmod u+w "$state_lockfile"
        needs_prewarm=1
      fi
    fi

    if [ ! -d "$nvim_data_dir/lazy/lazy.nvim" ]; then
      needs_prewarm=1
    fi

    if [ "$needs_prewarm" = "1" ]; then
      nvim_bin=""
      for candidate in ${nvimCandidateArgs}; do
        if [ -x "$candidate" ]; then
          nvim_bin="$candidate"
          break
        fi
      done

      if [ -z "$nvim_bin" ]; then
        echo "Failed to find nvim for Neovim plugin bootstrap." >&2
        exit 1
      fi

      if [ -n "$DRY_RUN_CMD" ]; then
        echo "Would prewarm Neovim plugins with $nvim_bin"
      else
        cd "$HOME"
        PATH="${bootstrapPath}:$PATH" \
          NVIM_LOG_FILE="$nvim_state_dir/bootstrap.log" \
          "$nvim_bin" --headless "+Lazy! sync" "+qa"
      fi
    fi

  '';
}

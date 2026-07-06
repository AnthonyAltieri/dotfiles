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
    ++ [
      "${pkgs.nodejs}/bin"
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
    needs_lazy_sync=0

    $DRY_RUN_CMD mkdir -p "$nvim_data_dir" "$nvim_lock_dir"

    if [ -f "$config_lockfile" ]; then
      if [ ! -f "$state_lockfile" ] || ! cmp -s "$config_lockfile" "$state_lockfile"; then
        $DRY_RUN_CMD cp "$config_lockfile" "$state_lockfile"
        $DRY_RUN_CMD chmod u+w "$state_lockfile"
        needs_lazy_sync=1
      fi
    fi

    if [ ! -d "$nvim_data_dir/lazy/lazy.nvim" ]; then
      needs_lazy_sync=1
    fi

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
      if [ "$needs_lazy_sync" = "1" ]; then
        echo "Would sync Neovim plugins with $nvim_bin"
      else
        echo "Would skip Neovim plugin sync; lazy.nvim and lazy-lock.json are current."
      fi
      echo "Would verify Neovim Mason tools with $nvim_bin"
    else
      cd "$HOME"
      if [ "$needs_lazy_sync" = "1" ]; then
        PATH="${bootstrapPath}:$PATH" \
          NVIM_LOG_FILE="$nvim_state_dir/bootstrap.log" \
          "$nvim_bin" --headless \
            "+Lazy! sync" \
            "+MasonToolsInstallSync" \
            "+lua require('aalt.mason_packages').cquit_if_missing()" \
            "+qa"
      else
        PATH="${bootstrapPath}:$PATH" \
          NVIM_LOG_FILE="$nvim_state_dir/bootstrap.log" \
          "$nvim_bin" --headless \
            "+MasonToolsInstallSync" \
            "+lua require('aalt.mason_packages').cquit_if_missing()" \
            "+qa"
      fi
    fi
  '';
}

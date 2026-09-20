#!/usr/bin/env bash
# Sourced by bootstrap.sh after argument parsing; shares its Nix and CLI helpers.

ensure_linux_nix() {
  # Let the shared helper report missing Nix in preview mode without installing.
  if load_nix || (( DRY_RUN || SHOW_DIFF )); then
    ensure_nix
    return
  fi

  if ! command -v apt-get >/dev/null 2>&1 || ! command -v sudo >/dev/null 2>&1; then
    echo "Installing Nix on Debian requires apt-get and sudo. Install sudo as root, then rerun as your normal user, or install Nix manually." >&2
    exit 1
  fi

  log "Installing Debian prerequisites for Nix..."
  sudo -- apt-get update
  sudo -- apt-get install -y --no-install-recommends ca-certificates curl git xz-utils

  if [[ -d /run/systemd/system ]]; then
    ensure_nix --daemon
  else
    log "No running systemd detected; installing single-user Nix."
    ensure_nix --no-daemon
  fi
}

show_home_closure_diff() {
  local home_path="$1"
  local state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local current_home=""
  local candidate

  for candidate in \
    "$state_home/home-manager/gcroots/current-home" \
    "$state_home/nix/profiles/home-manager" \
    "${NIX_STATE_DIR:-/nix/var/nix}/profiles/per-user/$(id -un)/home-manager" \
    "$state_home/home-manager/profiles/home-manager"
  do
    if [[ -e "$candidate" ]]; then
      current_home="$candidate"
      break
    fi
  done

  if [[ -z "$current_home" ]]; then
    log "No active Home Manager generation to compare against (first apply)."
    return
  fi

  log "Diffing $current_home -> $home_path"
  nix --extra-experimental-features "$EXPERIMENTAL_FEATURES" \
    store diff-closures "$current_home" "$home_path"
}

bootstrap_linux() {
  local config_name=""
  local home_path=""
  local architecture
  architecture="$(uname -m)"

  case "$architecture" in
    x86_64|amd64) config_name="${ROLE}-linux" ;;
    aarch64|arm64) config_name="${ROLE}-aarch64-linux" ;;
    *)
      echo "Unsupported Linux architecture: $architecture (expected x86_64 or aarch64)." >&2
      exit 1
      ;;
  esac

  if [[ "$(id -u)" -eq 0 ]]; then
    echo "Run bootstrap as your normal user, without sudo. Home Manager manages that user's home." >&2
    exit 1
  fi

  ensure_linux_nix
  if [[ "$COMMAND" == "install-dependencies" ]]; then
    log "Dependencies installed."
    return
  fi

  if (( OVERWRITE )); then
    config_name+="-overwrite"
  fi

  home_path="$(nix --extra-experimental-features "$EXPERIMENTAL_FEATURES" \
    build "${FLAKE_REF}#homeConfigurations.${config_name}.activationPackage" \
    "${FLAKE_EVAL_FLAGS[@]}" --no-link --print-out-paths | tail -n 1)"
  if [[ -z "$home_path" ]]; then
    echo "Failed to build the Home Manager closure." >&2
    exit 1
  fi
  log "Built Home Manager closure for $ROLE: $home_path"

  if (( SHOW_DIFF )); then
    show_home_closure_diff "$home_path"
  fi
  if (( DRY_RUN )); then
    log "Dry-run complete. No changes were applied."
    return
  fi

  log "Applying Linux role: $ROLE"
  if (( OVERWRITE )); then
    log "Overwrite mode enabled. Managed files will be replaced without .hm-backup copies."
    env -u HOME_MANAGER_BACKUP_EXT "$home_path/activate"
  else
    HOME_MANAGER_BACKUP_EXT=hm-backup "$home_path/activate"
  fi
  log "Done."
}

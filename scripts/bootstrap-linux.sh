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

# Home Manager installs zsh but cannot change the login shell, so SSH sessions
# would keep starting Debian's bash and skip the managed prompt.
ensure_linux_login_shell() {
  local zsh_path="$HOME/.nix-profile/bin/zsh"
  local user=""
  local current_shell=""

  if [[ ! -x "$zsh_path" ]]; then
    return
  fi
  user="$(id -un)"
  current_shell="$(getent passwd "$user" | cut -d: -f7)"
  if [[ "$current_shell" == "$zsh_path" ]]; then
    return
  fi

  log "Setting the login shell for $user to $zsh_path (was ${current_shell:-unset})..."
  if ! grep -qxF "$zsh_path" /etc/shells \
    && ! sudo -- sh -c 'printf "%s\n" "$1" >> /etc/shells' sh "$zsh_path"; then
    echo "Failed to add $zsh_path to /etc/shells. Rerun bootstrap with sudo access." >&2
    exit 1
  fi
  if ! sudo -- chsh -s "$zsh_path" "$user"; then
    echo "Failed to change the login shell for $user. Rerun bootstrap with sudo access." >&2
    exit 1
  fi
}

bootstrap_linux() {
  local config_name=""
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

  apply_home_manager "homeConfigurations.${config_name}.activationPackage" "Linux role"
  if (( ! DRY_RUN )); then
    ensure_linux_login_shell
  fi
}

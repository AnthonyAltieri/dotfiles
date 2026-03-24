#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPERIMENTAL_FEATURES="nix-command flakes"

usage() {
  cat >&2 <<'EOF'
Usage: ./bootstrap.sh <personal|work>

Bootstrap is the supported macOS apply path for this repo.
It is safe to rerun after pulling changes or editing the flake.
EOF
  exit 1
}

ROLE="${1:-}"

if [[ "$ROLE" != "personal" && "$ROLE" != "work" ]]; then
  usage
fi

require_darwin() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "bootstrap.sh currently supports macOS only." >&2
    exit 1
  fi
}

log() {
  printf '[bootstrap] %s\n' "$*"
}

load_nix() {
  if command -v nix >/dev/null 2>&1; then
    return 0
  fi

  local nix_daemon_profile="/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
  local nix_user_profile="$HOME/.nix-profile/etc/profile.d/nix.sh"

  if [[ -r "$nix_daemon_profile" ]]; then
    # shellcheck disable=SC1091
    source "$nix_daemon_profile"
  elif [[ -r "$nix_user_profile" ]]; then
    # shellcheck disable=SC1091
    source "$nix_user_profile"
  fi

  command -v nix >/dev/null 2>&1
}

install_nix() {
  if load_nix; then
    log "Nix is already available."
    return
  fi

  log "Installing Nix..."
  bash <(curl -fsSL https://nixos.org/nix/install) --daemon
  load_nix
}

load_homebrew() {
  if command -v brew >/dev/null 2>&1; then
    return 0
  fi

  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$brew_bin" ]]; then
      eval "$("$brew_bin" shellenv)"
      break
    fi
  done

  command -v brew >/dev/null 2>&1
}

install_homebrew() {
  if load_homebrew; then
    log "Homebrew is already available."
    return
  fi

  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  load_homebrew
}

build_system_closure() {
  nix --extra-experimental-features "$EXPERIMENTAL_FEATURES" \
    build "$SCRIPT_DIR#darwinConfigurations.${ROLE}.system" \
    --no-link \
    --print-out-paths | tail -n 1
}

switch_darwin_role() {
  local system_path
  system_path="$(build_system_closure)"

  if [[ -z "$system_path" ]]; then
    echo "Failed to build the Darwin system closure." >&2
    exit 1
  fi

  log "Applying Darwin role: $ROLE"
  "$system_path/sw/bin/darwin-rebuild" switch --flake "$SCRIPT_DIR#$ROLE"
}

require_darwin
install_nix
install_homebrew
switch_darwin_role
log "Done."

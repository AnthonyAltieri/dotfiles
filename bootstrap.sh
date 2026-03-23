#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "Usage: $0 <personal|work>" >&2
  exit 1
}

ROLE="${1:-}"

if [[ "$ROLE" != "personal" && "$ROLE" != "work" ]]; then
  usage
fi

load_nix() {
  if command -v nix >/dev/null 2>&1; then
    return
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
}

install_nix() {
  if command -v nix >/dev/null 2>&1; then
    return
  fi

  echo "Installing Nix..."
  bash <(curl -fsSL https://nixos.org/nix/install) --daemon
  load_nix
}

install_homebrew() {
  if [[ "$(uname)" != "Darwin" ]]; then
    return
  fi

  if command -v brew >/dev/null 2>&1; then
    return
  fi

  echo "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
}

install_nix
install_homebrew

echo "Building darwin configuration for role: $ROLE"
nix --extra-experimental-features "nix-command flakes" build "$SCRIPT_DIR#darwinConfigurations.${ROLE}.system"

echo "Switching darwin configuration..."
"$SCRIPT_DIR/result/sw/bin/darwin-rebuild" switch --flake "$SCRIPT_DIR#$ROLE"

echo "Done."

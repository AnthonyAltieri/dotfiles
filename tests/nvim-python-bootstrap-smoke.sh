#!/usr/bin/env bash
# Linux e2e: exercise the actual activation PATH with real Python and pip.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
case "$(uname -sm)" in
  'Linux x86_64') profile=personal-linux ;;
  'Linux aarch64') profile=personal-aarch64-linux ;;
  *) echo 'Run this test on x86-64 or ARM64 Linux.' >&2; exit 1 ;;
esac

nix --extra-experimental-features 'nix-command flakes' eval --impure --raw \
  "$ROOT#homeConfigurations.$profile.config.home.activation.dotfilesPrewarmNeovim.data" \
  > "$WORK/activation.sh"
bootstrap_path="$(sed -n 's/.*PATH="\(.*\):\$PATH".*/\1/p' "$WORK/activation.sh" | head -n 1)"
test -n "$bootstrap_path"

# Use the production activation dependencies, without a user-installed Python.
PATH="$bootstrap_path:/usr/bin:/bin" python3 -m venv --system-site-packages "$WORK/venv"
"$WORK/venv/bin/python" -m pip --version
printf '%s\n' 'ok Neovim bootstrap Python creates a venv with pip'

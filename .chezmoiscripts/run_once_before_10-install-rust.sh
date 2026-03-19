#!/bin/bash
set -euo pipefail

if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    . "${HOME}/.cargo/env"
fi

if command -v rustc &>/dev/null && command -v cargo &>/dev/null; then
    rustc --version
    cargo --version
    exit 0
fi

echo "Installing Rust via rustup..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path

if [[ -f "${HOME}/.cargo/env" ]]; then
    # shellcheck disable=SC1090
    . "${HOME}/.cargo/env"
fi

command -v rustc >/dev/null
command -v cargo >/dev/null

rustc --version
cargo --version

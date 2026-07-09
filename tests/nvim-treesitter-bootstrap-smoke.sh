#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOMEBREW_MODULE="$ROOT_DIR/modules/platforms/darwin/homebrew.nix"
NEOVIM_MODULE="$ROOT_DIR/modules/shared/neovim.nix"

if ! rg -q '^[[:space:]]*"tree-sitter-cli"$' "$HOMEBREW_MODULE"; then
	printf 'expected Homebrew to install tree-sitter-cli\n' >&2
	exit 1
fi

if ! rg -q '^[[:space:]]*"tree-sitter"$' "$HOMEBREW_MODULE"; then
	printf 'expected Homebrew to retain tree-sitter for Neovim runtime support\n' >&2
	exit 1
fi

if ! rg -Fq '"/opt/homebrew/bin"' "$NEOVIM_MODULE"; then
	printf 'expected Neovim prewarm PATH to include Homebrew binaries\n' >&2
	exit 1
fi

echo "ok Neovim bootstrap retains the tree-sitter runtime and installs the CLI"

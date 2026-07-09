#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TELESCOPE_SPEC="$ROOT_DIR/home/.config/nvim/lua/aalt/lazy/telescope.lua"
LOCKFILE="$ROOT_DIR/home/.config/nvim/lazy-lock.json"
TELESCOPE_COMMIT="84b9ba066d1860f7a586ce9cd732fd6c4f77d1d9"

nvim --clean --headless -u NONE \
	+"lua local spec = dofile('$TELESCOPE_SPEC'); assert(spec.tag == 'v0.1.9'); assert(spec.branch == nil); local lock = vim.json.decode(table.concat(vim.fn.readfile('$LOCKFILE'), '\\n')); local telescope = assert(lock['telescope.nvim']); assert(telescope.branch == 'master'); assert(telescope.commit == '$TELESCOPE_COMMIT')" \
	+qa

echo "ok telescope uses the Tree-sitter-compatible v0.1.9 release"

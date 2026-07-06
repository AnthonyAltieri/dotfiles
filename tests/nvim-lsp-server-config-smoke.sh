#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LSP_CONFIG="${ROOT_DIR}/home/.config/nvim/lua/aalt/lazy/lsp.lua"
MASON_PACKAGES="${ROOT_DIR}/home/.config/nvim/lua/aalt/mason_packages.lua"

grep -q 'rust_analyzer = {}' "$LSP_CONFIG"
grep -q 'tsgo = {}' "$LSP_CONFIG"
grep -q 'mason_packages.ensure_installed()' "$LSP_CONFIG"
grep -q 'ensure_installed = vim.tbl_keys(servers or {})' "$LSP_CONFIG"
grep -q 'rust_analyzer = true' "$LSP_CONFIG"
grep -q 'tsgo = true' "$LSP_CONFIG"
grep -q '<F2>' "$LSP_CONFIG"
grep -q '<C-M-o>' "$LSP_CONFIG"
grep -q 'tsgo = "tsgo"' "$MASON_PACKAGES"
grep -q "cquit_if_missing()" "${ROOT_DIR}/modules/shared/neovim.nix"
grep -q "Would verify Neovim Mason tools" "${ROOT_DIR}/modules/shared/neovim.nix"

nvim --clean --headless -i NONE \
  +"set rtp+=${ROOT_DIR}/home/.config/nvim" \
  +"lua local ok, err = xpcall(function() local packages = require('aalt.mason_packages').ensure_installed(); local seen = {}; for _, package_name in ipairs(packages) do seen[package_name] = true end; for _, package_name in ipairs({ 'pyright', 'ruff', 'rust-analyzer', 'lua-language-server', 'tsgo', 'stylua', 'eslint_d', 'oxfmt', 'oxlint', 'prettierd' }) do assert(seen[package_name], package_name) end end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
  +qa

echo "ok rust lsp parity configured"

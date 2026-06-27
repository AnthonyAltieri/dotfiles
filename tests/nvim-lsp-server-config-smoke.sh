#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LSP_CONFIG="${ROOT_DIR}/home/.config/nvim/lua/aalt/lazy/lsp.lua"

grep -q 'rust_analyzer = {}' "$LSP_CONFIG"
grep -q 'ensure_installed = vim.tbl_keys(servers or {})' "$LSP_CONFIG"
grep -q 'rust_analyzer = true' "$LSP_CONFIG"
grep -q 'tsgo = true' "$LSP_CONFIG"
grep -q '<F2>' "$LSP_CONFIG"
grep -q '<C-M-o>' "$LSP_CONFIG"

echo "ok rust lsp parity configured"

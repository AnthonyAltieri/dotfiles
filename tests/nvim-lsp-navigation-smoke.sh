#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/src"

cat >"$TMP_DIR/src/main.rs" <<'EOF'
use crate::{
    render::draw_scene,
};

fn main() {
    draw_scene();
}
EOF

cat >"$TMP_DIR/src/render.rs" <<'EOF'
pub fn draw_scene() {}
EOF

REPO_LUA="${ROOT_DIR}/home/.config/nvim/lua" \
MAIN_RS="$TMP_DIR/src/main.rs" \
RENDER_RS="$TMP_DIR/src/render.rs" \
XDG_CACHE_HOME="$TMP_DIR/cache" \
XDG_DATA_HOME="$TMP_DIR/data" \
XDG_STATE_HOME="$TMP_DIR/state" \
nvim --clean --headless \
  --cmd 'lua vim.loader.enable(false)' \
  --cmd 'lua package.path = vim.fn.getenv("REPO_LUA") .. "/?.lua;" .. vim.fn.getenv("REPO_LUA") .. "/?/init.lua;" .. package.path' \
  +"edit ${TMP_DIR}/src/main.rs" \
  +"set filetype=rust" \
  +"lua local ok, err = xpcall(function() local real = function(path) return vim.uv.fs_realpath(path) or vim.fs.normalize(path) end; local nav = require('aalt.lsp_navigation'); local main = real(vim.fn.getenv('MAIN_RS')); local render = real(vim.fn.getenv('RENDER_RS')); local import_item = { filename = main, lnum = 2, col = 13 }; local requested = false; local original_get_clients = vim.lsp.get_clients; vim.lsp.get_clients = function() return { { id = 1, offset_encoding = 'utf-16', flags = {} } } end; vim.lsp.buf_request_all = function(bufnr, method, params, callback) requested = true; assert(method == 'textDocument/definition', method); assert(real(vim.api.nvim_buf_get_name(bufnr)) == main, vim.api.nvim_buf_get_name(bufnr)); assert(params.position.line == 1, vim.inspect(params)); callback({ [1] = { result = { { uri = vim.uri_from_fname(render), range = { start = { line = 0, character = 7 }, ['end'] = { line = 0, character = 17 } } } } } }); end; assert(nav.handle_definition_list({ items = { import_item } }) == true); assert(vim.wait(1000, function() return requested and real(vim.api.nvim_buf_get_name(0)) == render end, 10)); vim.lsp.get_clients = original_get_clients; local cursor = vim.api.nvim_win_get_cursor(0); assert(cursor[1] == 1, vim.inspect(cursor)); assert(cursor[2] == 7, vim.inspect(cursor)); print('ok rust import definition follow') end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
  +qa

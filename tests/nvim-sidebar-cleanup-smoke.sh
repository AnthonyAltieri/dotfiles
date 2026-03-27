#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_LUA="${ROOT_DIR}/home/.config/nvim/lua"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

run_case() {
  local case_name="$1"
  local lua_file="$2"

  nvim --clean --headless -u NONE \
    --cmd "lua package.path = '${REPO_LUA}/?.lua;${REPO_LUA}/?/init.lua;' .. package.path" \
    -S "${lua_file}"

  printf 'ok %s\n' "${case_name}"
}

cat >"${TMP_DIR}/cleanup_last_file.lua" <<EOF
local cleanup = require("aalt.ui_cleanup")
vim.opt.swapfile = false

local file_path = "${TMP_DIR}/current.lua"
local file_handle = assert(io.open(file_path, "w"))
file_handle:write("return 1\n")
file_handle:close()

vim.cmd("edit " .. vim.fn.fnameescape(file_path))
local file_win = vim.api.nvim_get_current_win()

vim.cmd("vsplit")
vim.cmd("enew")
local tree_buf = vim.api.nvim_get_current_buf()
vim.bo[tree_buf].buftype = "nofile"
vim.bo[tree_buf].bufhidden = "wipe"
vim.bo[tree_buf].filetype = "neo-tree"

vim.cmd("split")
vim.cmd("enew")
local dashboard_buf = vim.api.nvim_get_current_buf()
vim.bo[dashboard_buf].buftype = "nofile"
vim.bo[dashboard_buf].bufhidden = "wipe"
vim.bo[dashboard_buf].filetype = "dashboard"

vim.api.nvim_set_current_win(file_win)
local closed = cleanup.close_managed_ui_windows_for_current_quit()

assert(closed == 2, string.format("expected 2 windows to close, got %d", closed))
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, "expected only the file window to remain")

vim.cmd("qa!")
EOF

cat >"${TMP_DIR}/keep_other_file.lua" <<EOF
local cleanup = require("aalt.ui_cleanup")
vim.opt.swapfile = false

local first_path = "${TMP_DIR}/first.lua"
local first_handle = assert(io.open(first_path, "w"))
first_handle:write("return 'first'\n")
first_handle:close()

local second_path = "${TMP_DIR}/second.lua"
local second_handle = assert(io.open(second_path, "w"))
second_handle:write("return 'second'\n")
second_handle:close()

vim.cmd("edit " .. vim.fn.fnameescape(first_path))
local first_win = vim.api.nvim_get_current_win()

vim.cmd("vsplit")
vim.cmd("edit " .. vim.fn.fnameescape(second_path))

vim.cmd("split")
vim.cmd("enew")
local tree_buf = vim.api.nvim_get_current_buf()
vim.bo[tree_buf].buftype = "nofile"
vim.bo[tree_buf].bufhidden = "wipe"
vim.bo[tree_buf].filetype = "neo-tree"

vim.api.nvim_set_current_win(first_win)
local closed = cleanup.close_managed_ui_windows_for_current_quit()

assert(closed == 0, string.format("expected no windows to close, got %d", closed))
assert(#vim.api.nvim_tabpage_list_wins(0) == 3, "expected both file windows and the tree to remain")

vim.cmd("qa!")
EOF

cat >"${TMP_DIR}/close_startup_ui.lua" <<EOF
local cleanup = require("aalt.ui_cleanup")
vim.opt.swapfile = false

vim.bo[0].buftype = "nofile"
vim.bo[0].bufhidden = "wipe"
vim.bo[0].filetype = "dashboard"
local dashboard_win = vim.api.nvim_get_current_win()

vim.cmd("vsplit")
vim.cmd("enew")
local tree_buf = vim.api.nvim_get_current_buf()
vim.bo[tree_buf].buftype = "nofile"
vim.bo[tree_buf].bufhidden = "wipe"
vim.bo[tree_buf].filetype = "neo-tree"

vim.api.nvim_set_current_win(dashboard_win)
local closed = cleanup.close_managed_ui_windows_for_current_quit()

assert(closed == 1, string.format("expected 1 window to close, got %d", closed))
assert(#vim.api.nvim_tabpage_list_wins(0) == 1, "expected only the dashboard window to remain")

vim.cmd("qa!")
EOF

run_case "cleanup_last_file" "${TMP_DIR}/cleanup_last_file.lua"
run_case "keep_other_file" "${TMP_DIR}/keep_other_file.lua"
run_case "close_startup_ui" "${TMP_DIR}/close_startup_ui.lua"

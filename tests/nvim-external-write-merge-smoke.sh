#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_LUA="${ROOT_DIR}/home/.config/nvim/lua"

run_case() {
	local name="$1"
	local script_path="${TMP_DIR}/${name}.lua"

	cat >"$script_path"

	REPO_LUA="$REPO_LUA" \
	TMP_DIR="$TMP_DIR" \
	XDG_CACHE_HOME=/tmp \
	XDG_STATE_HOME=/tmp \
	XDG_DATA_HOME=/tmp \
	nvim --clean --headless \
		--cmd 'lua vim.loader.enable(false)' \
		--cmd 'lua package.path = vim.fn.getenv("REPO_LUA") .. "/?.lua;" .. vim.fn.getenv("REPO_LUA") .. "/?/init.lua;" .. package.path' \
		--cmd 'lua require("aalt.external_file_merge").setup()' \
		+"luafile ${script_path}" \
		+qa!
}

run_case "clean_reload" <<'EOF'
local merge = require("aalt.external_file_merge")
local path = vim.fn.getenv("TMP_DIR") .. "/clean-reload.txt"

vim.fn.writefile({ "alpha", "beta" }, path)
vim.cmd.edit(path)
merge.track_buffer(0)
vim.fn.writefile({ "alpha", "disk" }, path)

merge.handle_buffer(0)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(table.concat(lines, "\n") == "alpha\ndisk", "clean reload should read the disk contents")
assert(vim.bo.modified == false, "clean reload should leave the buffer unmodified")
EOF

run_case "clean_merge" <<'EOF'
local merge = require("aalt.external_file_merge")
local path = vim.fn.getenv("TMP_DIR") .. "/clean-merge.txt"

vim.fn.writefile({ "one", "two" }, path)
vim.cmd.edit(path)
merge.track_buffer(0)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "zero", "one", "two" })
vim.fn.writefile({ "one", "two", "three" }, path)

merge.handle_buffer(0)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
assert(table.concat(lines, "\n") == "zero\none\ntwo\nthree", "non-overlapping edits should merge cleanly")
assert(vim.bo.modified == true, "merged buffer should remain modified")
EOF

run_case "conflict_merge" <<'EOF'
local merge = require("aalt.external_file_merge")
local path = vim.fn.getenv("TMP_DIR") .. "/conflict-merge.txt"

vim.fn.writefile({ "alpha", "beta", "gamma" }, path)
vim.cmd.edit(path)
merge.track_buffer(0)
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "alpha", "local", "gamma" })
vim.fn.writefile({ "alpha", "disk", "gamma" }, path)

merge.handle_buffer(0)

local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
local text = table.concat(lines, "\n")

assert(text:find("<<<<<<< LOCAL", 1, true), "conflict markers should include the local label")
assert(text:find("||||||| BASE", 1, true), "zdiff3 conflict markers should include the base label")
assert(text:find("=======", 1, true), "conflict markers should include the separator")
assert(text:find(">>>>>>> DISK", 1, true), "conflict markers should include the disk label")
assert(vim.bo.modified == true, "conflicted buffer should remain modified")
EOF

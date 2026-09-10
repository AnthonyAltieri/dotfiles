#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

REPO_LUA="${ROOT_DIR}/home/.config/nvim/lua"

cat >"$TMP_DIR/navigator.lua" <<'LUA'
local nav = require("aalt.herdr_navigator")

local calls = {}
local function record(cmd)
	table.insert(calls, table.concat(cmd, " "))
end

-- Outside herdr: edge moves do nothing.
vim.env.HERDR_ENV = nil
vim.env.HERDR_SOCKET_PATH = nil
nav.navigate("h", { run = record })
assert(#calls == 0, "expected no herdr call outside herdr")

-- Inside herdr: a single window at the left edge delegates to herdr.
vim.env.HERDR_ENV = "1"
vim.env.HERDR_SOCKET_PATH = "/tmp/herdr.sock"
nav.navigate("h", { run = record })
assert(calls[1] == "herdr pane focus --direction left --current", "unexpected herdr call: " .. tostring(calls[1]))

-- Inside herdr with two windows: moving between them stays in Neovim.
vim.cmd("vsplit")
vim.cmd("wincmd l")
local right = vim.api.nvim_get_current_win()
nav.navigate("h", { run = record })
assert(#calls == 1, "expected the in-Neovim move not to call herdr")
assert(vim.api.nvim_get_current_win() ~= right, "expected focus to move to the left window")

-- Now at the left edge again, the next move delegates.
nav.navigate("h", { run = record })
assert(calls[2] == "herdr pane focus --direction left --current", "expected an edge move to delegate to herdr")

nav.setup()
local map = vim.fn.maparg("<C-l>", "n", false, true)
assert(map.callback ~= nil, "expected <C-l> to be mapped by the navigator")
LUA

REPO_LUA="$REPO_LUA" \
NVIM_LOG_FILE="$TMP_DIR/nvim.log" \
XDG_CACHE_HOME="$TMP_DIR/cache" \
XDG_DATA_HOME="$TMP_DIR/data" \
XDG_STATE_HOME="$TMP_DIR/state" \
nvim --clean --headless -i NONE \
	--cmd 'lua vim.loader.enable(false)' \
	--cmd 'lua package.path = vim.fn.getenv("REPO_LUA") .. "/?.lua;" .. vim.fn.getenv("REPO_LUA") .. "/?/init.lua;" .. package.path' \
	+"lua local ok, err = xpcall(function() dofile('$TMP_DIR/navigator.lua') end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
	+qa!

echo "ok Neovim Ctrl+h/j/k/l navigates windows and delegates edge moves to herdr"

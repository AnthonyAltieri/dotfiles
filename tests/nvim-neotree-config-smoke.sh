#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
TMP_DIR="$(cd "$TMP_DIR" && pwd -P)"
trap 'rm -rf "$TMP_DIR"' EXIT

PLUGIN_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
for plugin in neo-tree.nvim plenary.nvim nui.nvim; do
	test -d "$PLUGIN_ROOT/$plugin" || { echo "Missing Neovim plugin: $plugin" >&2; exit 1; }
done
mkdir -p "$TMP_DIR/project/pkg/__pycache__" "$TMP_DIR/project/__pycache__" "$TMP_DIR/project/__pycache__keep"
mkdir -p "$TMP_DIR/data with spaces/nvim"
touch "$TMP_DIR/project/main.py" "$TMP_DIR/project/main.rs" "$TMP_DIR/project/.env" "$TMP_DIR/project/ignored.py"
touch "$TMP_DIR/project/__pycache__/main.pyc" "$TMP_DIR/project/pkg/__pycache__/nested.pyc"
git -C "$TMP_DIR/project" init -q
printf '%s\n' ignored.py >"$TMP_DIR/project/.gitignore"

cat >"$TMP_DIR/sidebar.lua" <<'LUA'
local function checked(callback)
	return function(...)
		local ok, err = xpcall(callback, debug.traceback, ...)
		if not ok then
			io.stderr:write(err .. "\n")
			vim.cmd("cquit")
		end
	end
end

checked(function()
	vim.opt.rtp:prepend(vim.env.REPO_NVIM)
	for _, plugin in ipairs({ "neo-tree.nvim", "plenary.nvim", "nui.nvim" }) do
		vim.opt.rtp:append(vim.env.PLUGIN_ROOT .. "/" .. plugin)
	end
	require("aalt.lazy.neotree").config()
	local config = require("neo-tree").ensure_config()
	assert(config.window.mappings["<2-LeftMouse>"] == "open", "double click must open")
	assert(config.window.mappings["<LeftMouse>"] ~= "open", "single click must not open")
	local manager = require("neo-tree.sources.manager")
	local events = require("neo-tree.events")
	local root = vim.uv.fs_realpath(vim.env.TEST_PROJECT)
	local state = manager.get_state("filesystem")
	for _, pattern in ipairs(state.filtered_items.never_show_by_pattern) do
		assert(not pattern:find(".*.*", 1, true), "adjacent wildcards cause excessive path backtracking")
	end
	state.force_open_folders = { root, root .. "/pkg" }
	local function after_render(action, callback)
		events.subscribe({ event = "after_render", once = true, handler = function()
			vim.schedule(checked(callback))
		end })
		action()
	end
	local function visible(relative, expected)
		assert((state.tree:get_node(root .. "/" .. relative) ~= nil) == expected, "visibility: " .. relative)
	end
	after_render(function() manager.navigate(state, root) end, function()
		if vim.env.RESTART == "1" then
			visible("main.rs", false)
			visible("__pycache__", true)
			vim.cmd("qa!")
			return
		end
		visible("__pycache__", false)
		visible("pkg/__pycache__", false)
		visible("__pycache__keep", true)
		visible("main.py", true)
		visible(".env", true)
		visible("ignored.py", true)
		vim.api.nvim_set_current_win(state.winid)
		vim.cmd("Hidden")
		assert(vim.bo.filetype == "json" and vim.bo.buftype == "", "Hidden must open editable JSON")
		assert(vim.api.nvim_buf_get_name(0) == vim.fn.stdpath("data") .. "/hidden.json")
		local initial = vim.json.decode(table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n"))
		assert(initial.python[1] == "**/__pycache__/**", "Python default must be editable")
		local win = vim.api.nvim_get_current_win()
		vim.cmd("Hidden")
		assert(vim.api.nvim_get_current_win() == win, "Hidden should reuse its window")
		after_render(function()
			vim.api.nvim_buf_set_lines(0, 0, -1, false, { '{"python": [], "rust": ["*.rs"]}' })
			vim.cmd("write")
		end, function()
			visible("__pycache__", true)
			visible("pkg/__pycache__", true)
			visible("main.rs", false)
			vim.cmd("tabnew")
			state = manager.get_state("filesystem")
			after_render(function() manager.navigate(state, root) end, function()
				visible("__pycache__", true)
				visible("main.rs", false)
				vim.cmd("qa!")
			end)
		end)
	end)
end)()
LUA

for restart in 0 1; do
	REPO_NVIM="$ROOT_DIR/home/.config/nvim" PLUGIN_ROOT="$PLUGIN_ROOT" \
	TEST_PROJECT="$TMP_DIR/project" RESTART="$restart" NVIM_LOG_FILE="$TMP_DIR/nvim.log" \
	XDG_DATA_HOME="$TMP_DIR/data with spaces" XDG_STATE_HOME="$TMP_DIR/state" XDG_CACHE_HOME="$TMP_DIR/cache" \
	nvim --clean --headless -i NONE -c "luafile $TMP_DIR/sidebar.lua" "$TMP_DIR/project/main.py"
done

echo "ok Neo-tree mouse mappings and Hidden edit/save, sidebar refresh, new tabs, and restart"

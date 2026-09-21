#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
PLUGIN_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
mkdir -p "$TMP_DIR/data/nvim"

cat >"$TMP_DIR/cache.lua" <<'LUA'
local ok, err = xpcall(function()
	vim.opt.rtp:prepend(vim.env.REPO_NVIM)
	for _, plugin in ipairs({ "neo-tree.nvim", "plenary.nvim", "nui.nvim" }) do
		vim.opt.rtp:append(vim.env.PLUGIN_ROOT .. "/" .. plugin)
	end
	local utils = require("neo-tree.utils")
	local upstream_match = utils.is_filtered_by_pattern
	require("aalt.lazy.neotree").config()
	local manager = require("neo-tree.sources.manager")
	local state = manager.get_state("filesystem")
	local function match(path, name)
		return utils.is_filtered_by_pattern(state.filtered_items.never_show_by_pattern, path, name)
	end
	-- Observe actual calls without replacing the matcher or relying on timings.
	local function calls_to(fn, action)
		local count = 0
		debug.sethook(function()
			if debug.getinfo(2, "f").func == fn then
				count = count + 1
			end
		end, "c")
		local success, message = pcall(action)
		debug.sethook()
		assert(success, message)
		return count
	end
	for _, case in ipairs({ { "/project/__pycache__/main.pyc", true }, { "/project/main.rs", false } }) do
		assert(calls_to(upstream_match, function() assert(match(case[1]) == case[2]) end) == 1)
		assert(calls_to(upstream_match, function() assert(match(case[1]) == case[2]) end) == 0,
			"both hidden and visible results must be cached")
	end
	assert(calls_to(upstream_match, function()
		assert(utils.is_filtered_by_pattern({ "%.py$" }, "/project/main.py"))
	end) == 1, "unrelated Neo-tree filters must bypass the cache")

	vim.cmd("Hidden")
	local function save(text)
		vim.api.nvim_buf_set_lines(0, 0, -1, false, { text })
		vim.cmd("silent write")
	end
	save('{"rust":["*.rs"]}')
	assert(match("/project/main.rs"), "changed rules must invalidate cached visible results")
	assert(not match("/project/__pycache__/main.pyc"), "changed rules must invalidate cached hidden results")
	assert(match("/project/file", "main.rs"))
	assert(not match("/project/file", "main.py"), "cache keys must distinguish supplied basenames")
	assert(calls_to(manager.refresh, function() save('{"rust": ["*.rs"]}') end) == 0,
		"saving unchanged patterns must not refresh the sidebar")
	assert(calls_to(upstream_match, function() assert(match("/project/main.rs")) end) == 0,
		"saving unchanged patterns must retain cached matches")
	local saved, message = pcall(save, '{"rust":42}')
	assert(not saved and message:find("Could not apply", 1, true))
	assert(calls_to(upstream_match, function() assert(match("/project/main.rs")) end) == 0,
		"invalid saves must retain the last working cache")

	assert(not match("/project/old.py"))
	for i = 1, 20000 do
		assert(not match("/project/file" .. i .. ".py"))
	end
	assert(calls_to(upstream_match, function() assert(not match("/project/old.py")) end) == 1,
		"the cache must evict old paths at its capacity")
	assert(calls_to(upstream_match, function() assert(not match("/project/file20000.py")) end) == 0,
		"eviction must retain recent entries")
	save("{}")
	assert(not match("/project/main.rs"), "clearing patterns must clear hidden results")
	local wrapper = utils.is_filtered_by_pattern
	require("aalt.hidden").setup()
	assert(utils.is_filtered_by_pattern == wrapper, "setup must not install another wrapper")
end, debug.traceback)
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit") end
vim.cmd("qa!")
LUA

REPO_NVIM="$ROOT_DIR/home/.config/nvim" PLUGIN_ROOT="$PLUGIN_ROOT" \
NVIM_LOG_FILE="$TMP_DIR/nvim.log" XDG_DATA_HOME="$TMP_DIR/data" \
XDG_STATE_HOME="$TMP_DIR/state" XDG_CACHE_HOME="$TMP_DIR/cache" \
nvim --clean --headless -i NONE -c "luafile $TMP_DIR/cache.lua"

echo "ok Hidden cache reuse, isolation, invalidation, unchanged saves, and bounded eviction"

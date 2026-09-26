#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
PLUGIN_ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/nvim/lazy"
test -d "$PLUGIN_ROOT/lazy.nvim"
test -d "$PLUGIN_ROOT/plenary.nvim"

cat > "$WORK/check.lua" <<'LUA'
local ok, err = xpcall(function()
	vim.opt.rtp:prepend(vim.env.PLUGIN_ROOT .. "/lazy.nvim")
	require("lazy").setup({
		spec = { dofile(vim.env.PLENARY_SPEC), "nvim-lua/plenary.nvim" },
		root = vim.env.PLUGIN_ROOT,
		lockfile = vim.env.TEST_LOCKFILE,
		install = { missing = false },
		pkg = { enabled = false },
		change_detection = { enabled = false },
	})
	local plugins = require("lazy.core.config").plugins
	assert(not plugins.plenary, "Plenary must not have a second identity")
	local plenary = assert(plugins["plenary.nvim"], "Plenary must retain its canonical name")
	local package = assert(require("lazy.pkg.rockspec").get(plenary))
	assert(package.source == "lazy" and package.spec.build ~= "rockspec", "Plenary must use Lazy's native spec")
	assert(require("plenary.path").new("."):exists(), "Plenary must load from its Git checkout")
end, debug.traceback)
if not ok then
	io.stderr:write(err .. "\n")
	vim.cmd("cquit")
end
LUA

PLUGIN_ROOT="$PLUGIN_ROOT" PLENARY_SPEC="$ROOT/home/.config/nvim/lua/aalt/lazy/init.lua" \
  TEST_LOCKFILE="$WORK/lazy-lock.json" NVIM_LOG_FILE="$WORK/nvim.log" \
  XDG_STATE_HOME="$WORK/state" XDG_CACHE_HOME="$WORK/cache" \
  nvim --clean --headless -i NONE -c "luafile $WORK/check.lua" +qa

printf '%s\n' 'ok Plenary loads once without a LuaRocks build'

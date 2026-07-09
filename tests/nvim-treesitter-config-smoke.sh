#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

CURRENT_LUA="$TMP_DIR/current/lua"
LEGACY_LUA="$TMP_DIR/legacy/lua"
mkdir -p "$CURRENT_LUA/nvim-treesitter" "$LEGACY_LUA/nvim-treesitter"

cat >"$CURRENT_LUA/nvim-treesitter/init.lua" <<'EOF'
local M = {}

function M.setup(opts)
	_G.current_treesitter_setup_called = true
	_G.current_treesitter_setup_opts = opts
end

function M.install(languages)
	_G.current_treesitter_install_languages = languages
end

function M.indentexpr()
	return 0
end

return M
EOF

cat >"$CURRENT_LUA/nvim-treesitter/parsers.lua" <<'EOF'
return {}
EOF

cat >"$LEGACY_LUA/nvim-treesitter/configs.lua" <<'EOF'
local M = {}

function M.setup(opts)
	_G.legacy_treesitter_opts = opts
end

return M
EOF

cat >"$LEGACY_LUA/nvim-treesitter/parsers.lua" <<'EOF'
local parser_configs = {}

return {
	get_parser_configs = function()
		return parser_configs
	end,
}
EOF

TREESITTER_SPEC="$ROOT_DIR/home/.config/nvim/lua/aalt/lazy/treesitter.lua"

NVIM_LOG_FILE="$TMP_DIR/current-nvim.log" nvim --clean --headless -i NONE \
	+"lua package.path = '$CURRENT_LUA/?.lua;$CURRENT_LUA/?/init.lua;' .. package.path" \
	+"lua local ok, err = xpcall(function() local registered = {}; vim.treesitter.start = function() _G.current_treesitter_started = true end; vim.treesitter.language.register = function(parser, filetype) registered[filetype] = parser end; local spec = dofile('$TREESITTER_SPEC'); spec.config(); assert(_G.current_treesitter_setup_called == true); assert(_G.current_treesitter_setup_opts.install_dir == vim.fn.stdpath('data') .. '/site'); assert(vim.tbl_contains(_G.current_treesitter_install_languages, 'typescript')); assert(vim.tbl_contains(_G.current_treesitter_install_languages, 'tsx')); assert(require('nvim-treesitter.parsers').templ.install_info.branch == 'master'); assert(registered.templ == 'templ'); assert(registered.typescriptreact == 'tsx'); vim.bo.filetype = 'typescriptreact'; vim.api.nvim_exec_autocmds('FileType', { pattern = 'typescriptreact' }); assert(_G.current_treesitter_started == true); assert(vim.bo.indentexpr == [[v:lua.require'nvim-treesitter'.indentexpr()]]) end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
	+qa

NVIM_LOG_FILE="$TMP_DIR/legacy-nvim.log" nvim --clean --headless -i NONE \
	+"lua package.path = '$LEGACY_LUA/?.lua;$LEGACY_LUA/?/init.lua;' .. package.path" \
	+"lua local ok, err = xpcall(function() vim.treesitter.language.register = function() end; local spec = dofile('$TREESITTER_SPEC'); spec.config(); assert(_G.legacy_treesitter_opts.ensure_installed[1] == 'bash'); assert(_G.legacy_treesitter_opts.highlight.enable == true); assert(_G.legacy_treesitter_opts.highlight.additional_vim_regex_highlighting[1] == 'markdown'); assert(require('nvim-treesitter.parsers').get_parser_configs().templ.install_info.branch == 'master') end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
	+qa

echo "ok nvim treesitter config supports current and legacy APIs"

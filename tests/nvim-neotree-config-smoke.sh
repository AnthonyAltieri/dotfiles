#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/lua/neo-tree"

cat >"$TMP_DIR/lua/neo-tree/init.lua" <<'EOF'
return {
	setup = function(options)
		_G.neotree_options = options
	end,
}
EOF

NEOTREE_SPEC="$ROOT_DIR/home/.config/nvim/lua/aalt/lazy/neotree.lua"

NVIM_LOG_FILE="$TMP_DIR/nvim.log" nvim --clean --headless -i NONE \
	+"lua package.path = '$TMP_DIR/lua/?.lua;$TMP_DIR/lua/?/init.lua;' .. package.path" \
	+"lua local ok, err = xpcall(function() local spec = dofile('$NEOTREE_SPEC'); spec.config(); assert(_G.neotree_options.window.mappings['<2-LeftMouse>'] == 'open', 'double left click must use Neo-tree open'); assert(_G.neotree_options.window.mappings['<LeftMouse>'] == nil, 'single left click must not use Neo-tree open') end, debug.traceback); if not ok then io.stderr:write(err .. '\n'); vim.cmd('cquit') end" \
	+qa

echo "ok Neo-tree opens files and toggles folders on double left click"

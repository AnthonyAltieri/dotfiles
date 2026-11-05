-- Rex configuration: https://www.superlogical.com/rex/docs/customize/config

-- Ctrl+h/j/k/l moves to the pane on that side. When the focused pane runs
-- Neovim the key passes through instead, so Neovim moves between its own
-- windows first and calls `rex focus` at an edge
-- (home/.config/nvim/lua/aalt/herdr_navigator.lua).
local terminal = "com.superlogical.terminal"
local editors = { vi = true, vim = true, nvim = true }

local function runs_editor(block_id)
	local info = rex.block.call(terminal, "process", { block_id = block_id })
	local fg = info and info.foreground
	if not fg then
		return false
	end
	local argv0 = (fg.argv0 or ""):match("[^/]*$")
	return editors[fg.name] or editors[argv0] or false
end

for key, direction in pairs({ h = "left", j = "down", k = "up", l = "right" }) do
	rex.bind("ctrl+" .. key, function(ctx)
		if runs_editor(ctx.block_id) then
			return false
		end
		rex.session.focus_direction({ direction = direction })
		return true
	end)
end

-- Ctrl+1..9 jumps straight to a tab, as in herdr. Cmd+1..9 no longer does.
for i = 1, 9 do
	rex.unbind("cmd+[Digit" .. i .. "]", "client.tab.goto")
	rex.bind("ctrl+" .. i, "client.tab.goto", { index = i })
end

-- Shift+Ctrl+h/j/k/l splits toward that side, matching Neovim's directions.
-- Cmd+D and Shift+Cmd+D no longer split; Shift+Cmd+arrows still do.
rex.unbind("cmd+d", "pane.split.right")
rex.unbind("shift+cmd+d", "pane.split.down")
rex.bind("shift+ctrl+h", "pane.split.left")
rex.bind("shift+ctrl+j", "pane.split.down")
rex.bind("shift+ctrl+k", "pane.split.up")
rex.bind("shift+ctrl+l", "pane.split.right")

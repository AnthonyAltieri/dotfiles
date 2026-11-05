-- Rex configuration: https://www.superlogical.com/rex/docs/customize/config
--
-- Pane focus needs nothing here. Rex leaves Ctrl+h/j/k/l to the terminal, so
-- Neovim owns them and calls `rex focus` at a window edge
-- (home/.config/nvim/lua/aalt/herdr_navigator.lua).

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

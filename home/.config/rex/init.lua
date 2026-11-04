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

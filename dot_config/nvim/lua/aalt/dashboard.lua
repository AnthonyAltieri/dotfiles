local left_categories = { "Search", "File Tree", "Go To", "Hover/Docs" }
local right_categories = { "Harpoon", "LSP Actions", "Diagnostics" }
local KEY_COL_WIDTH = 9
local COL_GAP = 6

local ns = vim.api.nvim_create_namespace("dashboard")
local dashboard_buf = nil
local dashboard_win = nil

local function format_key(key)
	return key:gsub("<leader>", "SPC "):gsub("<([CM])%-(.-)>", "%1-%2"):gsub("<(.-)>", "%1")
end

local function group_by_category(commands)
	local groups = {}
	for _, cmd in ipairs(commands) do
		if not groups[cmd.cat] then
			groups[cmd.cat] = {}
		end
		table.insert(groups[cmd.cat], cmd)
	end
	return groups
end

local function build_column(categories, groups)
	local lines = {}
	for i, cat in ipairs(categories) do
		if i > 1 then
			table.insert(lines, { text = "", highlights = {} })
		end
		table.insert(lines, { text = cat, highlights = { { "DashboardHeader", 0, #cat } } })
		for _, cmd in ipairs(groups[cat] or {}) do
			local key = format_key(cmd.key)
			local pad = string.rep(" ", math.max(1, KEY_COL_WIDTH - #key))
			local text = key .. pad .. cmd.desc
			table.insert(lines, {
				text = text,
				highlights = {
					{ "DashboardKey", 0, #key },
					{ "DashboardDesc", #key + #pad, #text },
				},
			})
		end
	end
	return lines
end

local function setup_highlights()
	local ok, palettes = pcall(require, "catppuccin.palettes")
	if not ok then
		return
	end
	local colors = palettes.get_palette("mocha")
	if not colors then
		return
	end
	vim.api.nvim_set_hl(0, "DashboardHeader", { fg = colors.mauve, bold = true })
	vim.api.nvim_set_hl(0, "DashboardKey", { fg = colors.peach })
	vim.api.nvim_set_hl(0, "DashboardDesc", { fg = colors.subtext1 })
	vim.api.nvim_set_hl(0, "DashboardMuted", { fg = colors.surface1 })
end

local function render(buf, win)
	if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_win_is_valid(win) then
		return
	end

	local commands = require("aalt.cheatsheet")
	local groups = group_by_category(commands)
	local left_lines = build_column(left_categories, groups)
	local right_lines = build_column(right_categories, groups)

	-- Measure column widths
	local left_width = 0
	for _, line in ipairs(left_lines) do
		left_width = math.max(left_width, #line.text)
	end
	local right_width = 0
	for _, line in ipairs(right_lines) do
		right_width = math.max(right_width, #line.text)
	end

	-- Pad columns to same height
	local max_height = math.max(#left_lines, #right_lines)
	while #left_lines < max_height do
		table.insert(left_lines, { text = "", highlights = {} })
	end
	while #right_lines < max_height do
		table.insert(right_lines, { text = "", highlights = {} })
	end

	-- Centering
	local total_width = left_width + COL_GAP + right_width
	local win_width = vim.api.nvim_win_get_width(win)
	local win_height = vim.api.nvim_win_get_height(win)
	local left_pad = math.max(0, math.floor((win_width - total_width) / 2))
	local top_pad = math.max(0, math.floor((win_height - max_height) / 2))

	local text_lines = {}
	local all_highlights = {} -- { row, hl_group, col_start, col_end }

	-- Top padding
	for _ = 1, top_pad do
		table.insert(text_lines, "")
	end

	-- Content
	local prefix = string.rep(" ", left_pad)
	for i = 1, max_height do
		local left = left_lines[i]
		local right = right_lines[i]
		local left_padded = left.text .. string.rep(" ", left_width - #left.text)
		local line = prefix .. left_padded .. string.rep(" ", COL_GAP) .. right.text
		table.insert(text_lines, line)

		local row = top_pad + i - 1
		for _, hl in ipairs(left.highlights) do
			table.insert(all_highlights, { row, hl[1], left_pad + hl[2], left_pad + hl[3] })
		end
		local right_offset = left_pad + left_width + COL_GAP
		for _, hl in ipairs(right.highlights) do
			table.insert(all_highlights, { row, hl[1], right_offset + hl[2], right_offset + hl[3] })
		end
	end

	-- Bottom padding
	while #text_lines < win_height do
		table.insert(text_lines, "")
	end

	-- Write lines
	vim.bo[buf].modifiable = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, text_lines)
	vim.bo[buf].modifiable = false

	-- Apply highlights
	vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
	for _, hl in ipairs(all_highlights) do
		vim.api.nvim_buf_set_extmark(buf, ns, hl[1], hl[3], {
			end_col = hl[4],
			hl_group = hl[2],
		})
	end
end

-- Highlight groups (re-applied on ColorScheme change)
setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", { callback = setup_highlights })

-- Render dashboard into the empty buffer after neo-tree opens
vim.api.nvim_create_autocmd("VimEnter", {
	callback = function()
		local arg = vim.fn.argv(0)
		-- Only show when opening with no args or a directory
		if vim.fn.argc() > 0 and (arg == "" or vim.fn.isdirectory(arg) ~= 1) then
			return
		end

		local buf = vim.api.nvim_get_current_buf()
		local name = vim.api.nvim_buf_get_name(buf)
		-- Buffer must be unnamed or a directory path
		if name ~= "" and vim.fn.isdirectory(name) ~= 1 then
			return
		end

		local win = vim.api.nvim_get_current_win()

		-- Scratch buffer
		vim.bo[buf].buftype = "nofile"
		vim.bo[buf].bufhidden = "wipe"
		vim.bo[buf].swapfile = false
		vim.bo[buf].filetype = "dashboard"

		-- Clean window appearance (save originals for restore)
		local saved = {
			number = vim.wo[win].number,
			relativenumber = vim.wo[win].relativenumber,
			signcolumn = vim.wo[win].signcolumn,
		}
		vim.wo[win].number = false
		vim.wo[win].relativenumber = false
		vim.wo[win].signcolumn = "no"

		dashboard_buf = buf
		dashboard_win = win

		-- Restore window options and clear refs when dashboard is wiped
		vim.api.nvim_create_autocmd("BufWipeout", {
			buffer = buf,
			callback = function()
				if vim.api.nvim_win_is_valid(win) then
					vim.wo[win].number = saved.number
					vim.wo[win].relativenumber = saved.relativenumber
					vim.wo[win].signcolumn = saved.signcolumn
				end
				dashboard_buf = nil
				dashboard_win = nil
			end,
		})

		render(buf, win)
	end,
})

-- Re-center on resize
vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
	callback = function()
		if dashboard_buf and vim.api.nvim_buf_is_valid(dashboard_buf) then
			render(dashboard_buf, dashboard_win)
		end
	end,
})

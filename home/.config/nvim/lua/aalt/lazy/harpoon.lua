local SLOTS = {
	{ key = "<M-j>", label = "j" },
	{ key = "<M-k>", label = "k" },
	{ key = "<M-l>", label = "l" },
	{ key = "<M-;>", label = ";" },
	{ key = "<M-'>", label = "'" },
}

--- Build the keybinding table for lazy.nvim `keys`.
local function build_keys()
	local keys = {
		{ "<leader>ha", function() require("harpoon"):list():add() end, desc = "[H]arpoon [A]dd" },
		{ "<leader>hr", function() require("harpoon"):list():remove() end, desc = "[H]arpoon [R]emove" },
		{ "<M-e>", function() require("harpoon").ui:toggle_quick_menu(require("harpoon"):list()) end, desc = "Harpoon menu" },
	}
	for i, slot in ipairs(SLOTS) do
		keys[#keys + 1] = {
			slot.key,
			function() require("harpoon"):list():select(i) end,
			desc = "Harpoon slot " .. i,
		}
	end
	return keys
end

-- ── Highlight helpers ──────────────────────────────────────────────
local function setup_highlights()
	local ok, palettes = pcall(require, "catppuccin.palettes")
	if not ok then return end
	local p = palettes.get_palette("mocha")

	vim.api.nvim_set_hl(0, "HarpoonActive", { fg = p.blue, bg = p.surface1, bold = true })
	vim.api.nvim_set_hl(0, "HarpoonInactive", { fg = p.subtext0, bg = p.mantle })
	vim.api.nvim_set_hl(0, "HarpoonKeyActive", { fg = p.peach, bg = p.surface1, bold = true })
	vim.api.nvim_set_hl(0, "HarpoonKeyInactive", { fg = p.peach, bg = p.mantle })
	vim.api.nvim_set_hl(0, "HarpoonFill", { bg = p.mantle })
end

-- ── Tabline renderer ───────────────────────────────────────────────
function _G._harpoon_tabline()
	local harpoon_ok, harpoon = pcall(require, "harpoon")
	if not harpoon_ok then return "" end

	local list = harpoon:list()
	local items = list.items
	local count = math.min(#items, #SLOTS)

	if count == 0 then
		vim.o.showtabline = 0
		return ""
	end

	local cur_buf = vim.api.nvim_buf_get_name(0)
	local parts = {}

	for i = 1, count do
		local item = items[i]
		local path = item and item.value or ""

		-- Resolve to absolute for comparison with current buffer
		local abs_path = path
		if path ~= "" and not vim.startswith(path, "/") then
			abs_path = vim.fn.fnamemodify(path, ":p")
		end

		local fname = vim.fn.fnamemodify(path, ":t")
		if #fname > 20 then
			fname = fname:sub(1, 17) .. "..."
		end

		local is_active = cur_buf ~= "" and abs_path ~= "" and vim.fn.resolve(cur_buf) == vim.fn.resolve(abs_path)

		local key_hl = is_active and "HarpoonKeyActive" or "HarpoonKeyInactive"
		local file_hl = is_active and "HarpoonActive" or "HarpoonInactive"

		local prefix = is_active and " [" or "  "
		local suffix = is_active and "] " or "  "

		parts[#parts + 1] = string.format(
			"%%#%s#%s%s %%#%s#%s%s",
			key_hl, prefix, SLOTS[i].label,
			file_hl, fname, suffix
		)
	end

	return table.concat(parts) .. "%#HarpoonFill#"
end

-- ── Reactive update helper ─────────────────────────────────────────
local function redraw_tabline()
	-- Defer to avoid issues during navigation transitions
	vim.schedule(function()
		local harpoon_ok, harpoon = pcall(require, "harpoon")
		if not harpoon_ok then return end
		local count = #harpoon:list().items
		vim.o.showtabline = count > 0 and 2 or 0
		if count > 0 then
			vim.cmd.redrawtabline()
		end
	end)
end

-- ── Plugin spec ────────────────────────────────────────────────────
return {
	"ThePrimeagen/harpoon",
	branch = "harpoon2",
	as = "harpoon",
	dependencies = { "nvim-lua/plenary.nvim" },
	keys = build_keys(),
	config = function()
		local harpoon = require("harpoon")
		harpoon:setup()

		-- Highlights
		setup_highlights()
		vim.api.nvim_create_autocmd("ColorScheme", {
			callback = setup_highlights,
			desc = "Re-apply Harpoon tabline highlights",
		})

		-- Tabline
		vim.o.tabline = "%!v:lua._harpoon_tabline()"
		vim.o.showtabline = #harpoon:list().items > 0 and 2 or 0

		-- Reactive updates from harpoon events
		local events = { "ADD", "REMOVE", "LIST_CHANGE", "SELECT", "NAVIGATE" }
		for _, event in ipairs(events) do
			harpoon:extend({ [event] = function() redraw_tabline() end })
		end

		-- Update active highlight when entering a buffer via other means
		vim.api.nvim_create_autocmd("BufEnter", {
			callback = redraw_tabline,
			desc = "Update Harpoon tabline active highlight",
		})
	end,
}

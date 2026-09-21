local M = {}

local config_path = vim.fn.resolve(vim.fn.stdpath("data") .. "/hidden.json")
local default_lines = {
	"{",
	'  "python": [',
	'    "**/__pycache__/**"',
	"  ]",
	"}",
}
local active_patterns = {}
local cache_limit = 20000
local match_cache = {}
local cached_paths = {}
local next_slot = 1
local original_match

local function set_patterns(patterns)
	active_patterns = patterns
	match_cache = {}
	cached_paths = {}
	next_slot = 1
end

local function install_match_cache()
	if original_match then
		return
	end
	local utils = require("neo-tree.utils")
	original_match = utils.is_filtered_by_pattern
	-- Neo-tree has no per-source matcher hook. Only intercept our owned pattern list.
	utils.is_filtered_by_pattern = function(patterns, path, name)
		if patterns ~= active_patterns then
			return original_match(patterns, path, name)
		end
		if #patterns == 0 then
			return false
		end
		local cached = match_cache[path]
		if cached and cached.name == name then
			return cached.hidden
		end
		local hidden = original_match(patterns, path, name)
		if not cached then
			local evicted = cached_paths[next_slot]
			if evicted then
				match_cache[evicted] = nil
			end
			cached_paths[next_slot] = path
			next_slot = next_slot % cache_limit + 1
		end
		match_cache[path] = { name = name, hidden = hidden }
		return hidden
	end
end

local function compile_glob(entry)
	local pattern = require("neo-tree.sources.filesystem.lib.globtopattern").globtopattern(entry)
	-- Neo-tree emits one .* per star, so ** needlessly backtracks over the same path twice.
	-- Its compiler escapes literal dots/stars (including inside classes), leaving only wildcards here.
	while pattern:find(".*.*", 1, true) do
		pattern = pattern:gsub("%.%*%.%*", ".*")
	end
	assert(pcall(string.find, "", pattern), "Invalid glob: " .. entry)
	return pattern
end

local function compile_patterns(lines)
	local config = vim.json.decode(table.concat(lines, "\n"))
	assert(type(config) == "table" and not vim.islist(config), "Expected an object of language names and pattern lists")
	local patterns = {}

	for language, entries in pairs(config) do
		assert(type(language) == "string" and language ~= "", "Language names must be non-empty strings")
		assert(type(entries) == "table" and vim.islist(entries), language .. " must contain a list of glob patterns")
		for _, entry in ipairs(entries) do
			assert(type(entry) == "string" and vim.trim(entry) ~= "", language .. " patterns must be non-empty strings")
			table.insert(patterns, compile_glob(entry))
			-- A subtree glob should also hide the directory itself, not leave an empty folder.
			if vim.endswith(entry, "/**") then
				table.insert(patterns, compile_glob(entry:sub(1, -4)))
			end
		end
	end

	return patterns
end

local function report_error(err)
	vim.notify("Could not apply " .. config_path .. ": " .. tostring(err), vim.log.levels.ERROR, { title = "Hidden" })
end

function M.apply(state)
	if state.name == "filesystem" then
		state.filtered_items.never_show_by_pattern = active_patterns
	end
end

function M.setup()
	set_patterns(compile_patterns(default_lines))
	if vim.uv.fs_stat(config_path) then
		local ok, patterns = pcall(function()
			return compile_patterns(vim.fn.readfile(config_path))
		end)
		if ok then
			set_patterns(patterns)
		else
			report_error(patterns)
		end
	end
	install_match_cache()

	vim.api.nvim_create_user_command("Hidden", function()
		local win = vim.fn.bufwinid(config_path)
		if win ~= -1 then
			vim.api.nvim_set_current_win(win)
			return
		end
		vim.fn.mkdir(vim.fn.fnamemodify(config_path, ":h"), "p")
		vim.cmd("botright vsplit " .. vim.fn.fnameescape(config_path))
		if not vim.uv.fs_stat(config_path) and not vim.bo.modified then
			vim.api.nvim_buf_set_lines(0, 0, -1, false, default_lines)
		end
		vim.bo.filetype = "json"
	end, { desc = "Edit sidebar hidden-file patterns by language; save to apply" })

	local group = vim.api.nvim_create_augroup("aalt-hidden", { clear = true })
	vim.api.nvim_create_autocmd("BufWritePost", {
		group = group,
		pattern = "*",
		callback = function(args)
			if vim.api.nvim_buf_get_name(args.buf) ~= config_path then
				return
			end
			local ok, patterns = pcall(compile_patterns, vim.api.nvim_buf_get_lines(args.buf, 0, -1, false))
			if not ok then
				report_error(patterns)
				return
			end
			if vim.deep_equal(active_patterns, patterns) then
				return
			end
			set_patterns(patterns)
			local manager = require("neo-tree.sources.manager")
			for _, tab in ipairs(vim.api.nvim_list_tabpages()) do
				M.apply(manager.get_state("filesystem", tab))
			end
			manager.refresh("filesystem")
		end,
	})
end

return M

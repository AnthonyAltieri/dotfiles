local monorepo = require("aalt.monorepo")
local js_filetypes = {
	javascript = true,
	javascriptreact = true,
	["javascript.jsx"] = true,
	typescript = true,
	typescriptreact = true,
	["typescript.tsx"] = true,
}

local function split_text(text)
	local lines = vim.split(text or "", "\r?\n")
	if lines[#lines] == "" then
		table.remove(lines)
	end
	if #lines == 0 then
		return { "" }
	end
	return lines
end

local function eslint_error_message(result, completed)
	local stderr = vim.trim(completed.stderr or "")
	if stderr ~= "" then
		return stderr
	end

	if type(result) == "table" and type(result.messages) == "table" then
		local first = result.messages[1]
		if type(first) == "table" and type(first.message) == "string" and first.message ~= "" then
			return first.message
		end
	end

	local stdout = vim.trim(completed.stdout or "")
	if stdout ~= "" then
		return stdout
	end

	return "ESLint formatting failed."
end

local function eslint_fix_with_fallback(ctx, lines, callback)
	local filename = ctx.filename
	local cwd = monorepo.find_eslint_root(filename)
	local command = monorepo.eslint_format_cmd(filename)
	if not cwd or not command then
		callback("Could not resolve an ESLint formatter command.")
		return
	end

	local input = table.concat(lines, "\n")
	if vim.fs.basename(command) == "eslint_d" then
		local completed = vim.system({ command, "--fix-to-stdout", "--stdin", "--stdin-filename", filename }, {
			cwd = cwd,
			text = true,
			stdin = input,
		}):wait()
		if completed.code ~= 0 then
			callback(eslint_error_message(nil, completed))
			return
		end
		callback(nil, split_text(completed.stdout))
		return
	end

	local completed = vim.system({
		command,
		"--fix-dry-run",
		"--format",
		"json",
		"--stdin",
		"--stdin-filename",
		filename,
	}, {
		cwd = cwd,
		text = true,
		stdin = input,
	}):wait()

	local stdout = vim.trim(completed.stdout or "")
	local ok, decoded = pcall(vim.json.decode, stdout, { luanil = { object = true, array = true } })
	local result = ok and type(decoded) == "table" and decoded[1] or nil
	if type(result) == "table" and type(result.output) == "string" then
		callback(nil, split_text(result.output))
		return
	end

	if completed.code == 0 then
		callback(nil, lines)
		return
	end

	callback(eslint_error_message(result, completed))
end

local function format_opts_for_buf(bufnr)
	if js_filetypes[vim.bo[bufnr].filetype] then
		return {
			timeout_ms = 500,
			lsp_format = "never",
		}
	end

	return {
		timeout_ms = 500,
		lsp_format = "fallback",
	}
end

return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	format_opts_for_buf = format_opts_for_buf,
	opts = {
		notify_on_error = false,
		format_on_save = format_opts_for_buf,
		formatters = {
			biome = {
				command = function(_, ctx)
					return monorepo.biome_cmd(ctx.filename)
				end,
				args = { "format", "--stdin-file-path", "$FILENAME" },
				stdin = true,
				cwd = function(_, ctx)
					return monorepo.find_biome_root(ctx.filename)
				end,
				require_cwd = true,
			},
			oxfmt = {
				command = function(_, ctx)
					return monorepo.oxfmt_cmd(ctx.filename)
				end,
				args = { "--stdin-filepath", "$FILENAME" },
				stdin = true,
				cwd = function(_, ctx)
					return monorepo.find_oxc_root(ctx.filename)
				end,
				require_cwd = true,
			},
			eslint_d_monorepo = {
				condition = function(_, ctx)
					return monorepo.find_eslint_root(ctx.filename) ~= nil
						and monorepo.eslint_format_cmd(ctx.filename) ~= nil
				end,
				format = function(_, ctx, lines, callback)
					eslint_fix_with_fallback(ctx, lines, callback)
				end,
			},
		},
		formatters_by_ft = {
			lua = { "stylua" },
			javascript = monorepo.javascript_formatters,
			javascriptreact = monorepo.javascript_formatters,
			typescript = monorepo.javascript_formatters,
			typescriptreact = monorepo.javascript_formatters,
		},
	},
}

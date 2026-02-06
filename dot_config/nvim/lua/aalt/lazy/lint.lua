local monorepo = require("aalt.monorepo")
local lint_filetypes = {
	javascript = true,
	javascriptreact = true,
	["javascript.jsx"] = true,
	typescript = true,
	typescriptreact = true,
	["typescript.tsx"] = true,
}

return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPost", "BufNewFile" },
	config = function()
		local lint = require("lint")

		lint.linters.eslint_d_monorepo = vim.tbl_deep_extend("force", require("lint.linters.eslint_d"), {
			cmd = function()
				return monorepo.eslint_d_cmd(monorepo.buf_path(0))
			end,
		})

		local function parse_oxlint_json(output, bufnr)
			if vim.trim(output) == "" then
				return {}
			end

			local decode_opts = { luanil = { object = true, array = true } }
			local ok, data = pcall(vim.json.decode, output, decode_opts)
			if not ok then
				return {
					{
						bufnr = bufnr,
						lnum = 0,
						col = 0,
						message = "Could not parse oxlint output: " .. data,
						source = "oxlint",
					},
				}
			end

			local diagnostics = {}
			for _, item in ipairs(data.diagnostics or {}) do
				local span = item.labels and item.labels[1] and item.labels[1].span or {}
				local line = tonumber(span.line) or 1
				local col = tonumber(span.column) or 1
				local length = tonumber(span.length) or 1
				local severity = (item.severity == "error") and vim.diagnostic.severity.ERROR
					or vim.diagnostic.severity.WARN

				table.insert(diagnostics, {
					source = "oxlint",
					lnum = line - 1,
					col = col - 1,
					end_col = math.max(col - 1 + length, col),
					severity = severity,
					message = item.message or "oxlint issue",
					code = item.code,
				})
			end

			return diagnostics
		end

		lint.linters.oxlint_monorepo = {
			cmd = function()
				return monorepo.oxlint_cmd(monorepo.buf_path(0))
			end,
			args = { "--format", "json" },
			stdin = false,
			stream = "stdout",
			ignore_exitcode = true,
			parser = parse_oxlint_json,
		}

		local function parse_biome_stderr(output)
			local diagnostics = {}
			local fetch_message = false
			local lnum, col, code

			for _, line in ipairs(vim.fn.split(output, "\n")) do
				if fetch_message then
					local symbol, message = line:match("^%s*([!×])%s+(.+)$")
					if symbol and message then
						table.insert(diagnostics, {
							source = "biomejs",
							lnum = tonumber(lnum) - 1,
							col = tonumber(col),
							code = code,
							severity = symbol == "×" and vim.diagnostic.severity.ERROR or vim.diagnostic.severity.WARN,
							message = message,
						})
						fetch_message = false
					end
				else
					_, _, lnum, col, code = line:find("[^:]+:(%d+):(%d+)%s+([%w_/%-]+)")
					if lnum then
						fetch_message = true
					end
				end
			end

			return diagnostics
		end

		lint.linters.biome_monorepo = vim.tbl_deep_extend("force", require("lint.linters.biomejs"), {
			cmd = function()
				return monorepo.biome_cmd(monorepo.buf_path(0))
			end,
			stream = "stderr",
			parser = parse_biome_stderr,
		})

		local group = vim.api.nvim_create_augroup("aalt-lint-on-save", { clear = true })
		vim.api.nvim_create_autocmd("BufWritePost", {
			group = group,
			desc = "Run project-aware lint checks on save",
			callback = function(args)
				if vim.bo[args.buf].buftype ~= "" then
					return
				end

				if monorepo.is_toolchain_marker_file(vim.api.nvim_buf_get_name(args.buf)) then
					monorepo.clear_caches()
				end

				if not lint_filetypes[vim.bo[args.buf].filetype] then
					return
				end

				local linters, cwd = monorepo.linters_for_buf(args.buf)
				if #linters == 0 then
					return
				end

				vim.api.nvim_buf_call(args.buf, function()
					lint.try_lint(linters, { cwd = cwd, ignore_errors = true })
				end)
			end,
		})
	end,
}

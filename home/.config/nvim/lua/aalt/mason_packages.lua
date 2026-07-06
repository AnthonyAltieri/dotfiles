local M = {}

M.lsp_server_packages = {
	pyright = "pyright",
	ruff = "ruff",
	rust_analyzer = "rust-analyzer",
	lua_ls = "lua-language-server",
	tsgo = "tsgo",
}

M.lsp_server_names = {
	"pyright",
	"ruff",
	"rust_analyzer",
	"lua_ls",
	"tsgo",
}

M.tool_packages = {
	"stylua",
	"eslint_d",
	"oxfmt",
	"oxlint",
	"prettierd",
}

function M.ensure_installed()
	local packages = {}

	for _, server_name in ipairs(M.lsp_server_names) do
		table.insert(packages, M.lsp_server_packages[server_name])
	end

	for _, package_name in ipairs(M.tool_packages) do
		table.insert(packages, package_name)
	end

	return packages
end

function M.missing_installed()
	local registry = require("mason-registry")
	local missing = {}

	for _, package_name in ipairs(M.ensure_installed()) do
		local ok, package = pcall(registry.get_package, package_name)
		if not ok or not package:is_installed() then
			table.insert(missing, package_name)
		end
	end

	return missing
end

function M.assert_installed()
	local missing = M.missing_installed()

	if #missing > 0 then
		error("Mason packages are not installed: " .. table.concat(missing, ", "))
	end
end

function M.cquit_if_missing()
	local missing = M.missing_installed()

	if #missing > 0 then
		io.stderr:write("Mason packages are not installed: " .. table.concat(missing, ", ") .. "\n")
		vim.cmd("cquit")
	end
end

return M

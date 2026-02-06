local M = {}

local BIOME_CONFIG_FILES = { "biome.json", "biome.jsonc" }
local OXC_CONFIG_FILES = { ".oxlintrc.json", ".oxfmtrc.json" }
local ESLINT_CONFIG_FILES = {
	"eslint.config.js",
	"eslint.config.cjs",
	"eslint.config.mjs",
	".eslintrc",
	".eslintrc.js",
	".eslintrc.cjs",
	".eslintrc.json",
	".eslintrc.yaml",
	".eslintrc.yml",
}

local function normalize(path)
	if not path or path == "" then
		return nil
	end
	return vim.fs.normalize(path)
end

local function dirname(path)
	local normalized = normalize(path)
	if not normalized then
		return nil
	end
	if vim.fn.isdirectory(normalized) == 1 then
		return normalized
	end
	return vim.fs.dirname(normalized)
end

local function find_upward(path, markers)
	local start_dir = dirname(path)
	if not start_dir then
		return nil
	end
	local found = vim.fs.find(markers, { path = start_dir, upward = true })[1]
	if not found then
		return nil
	end
	return vim.fs.dirname(found)
end

function M.buf_path(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr or 0)
	if name == "" then
		return nil
	end
	return normalize(name)
end

function M.find_biome_root(path)
	return find_upward(path, BIOME_CONFIG_FILES)
end

function M.find_eslint_root(path)
	if M.find_biome_root(path) or M.find_oxc_root(path) then
		return nil
	end
	return find_upward(path, ESLINT_CONFIG_FILES)
end

function M.find_oxc_root(path)
	return find_upward(path, OXC_CONFIG_FILES)
end

function M.is_biome_buffer(bufnr)
	return M.find_biome_root(M.buf_path(bufnr)) ~= nil
end

function M.is_oxc_buffer(bufnr)
	return M.find_oxc_root(M.buf_path(bufnr)) ~= nil
end

function M.javascript_formatters(bufnr)
	if M.is_biome_buffer(bufnr) then
		return { { "biome", "prettierd", "prettier" } }
	end
	if M.is_oxc_buffer(bufnr) then
		return { { "oxfmt", "prettierd", "prettier" } }
	end
	return { { "prettierd", "prettier" } }
end

function M.find_local_bin(path, binary_name)
	local start_dir = dirname(path)
	if not start_dir then
		return nil
	end
	local found = vim.fs.find("node_modules/.bin/" .. binary_name, { path = start_dir, upward = true })[1]
	return normalize(found)
end

function M.biome_cmd(path)
	return M.find_local_bin(path, "biome") or "biome"
end

function M.oxfmt_cmd(path)
	local local_oxfmt = M.find_local_bin(path, "oxfmt")
	if local_oxfmt then
		return local_oxfmt
	end

	local mason_oxfmt = normalize(vim.fn.stdpath("data") .. "/mason/bin/oxfmt")
	if mason_oxfmt and vim.fn.executable(mason_oxfmt) == 1 then
		return mason_oxfmt
	end

	return "oxfmt"
end

function M.oxlint_cmd(path)
	local local_oxlint = M.find_local_bin(path, "oxlint")
	if local_oxlint then
		return local_oxlint
	end

	local mason_oxlint = normalize(vim.fn.stdpath("data") .. "/mason/bin/oxlint")
	if mason_oxlint and vim.fn.executable(mason_oxlint) == 1 then
		return mason_oxlint
	end

	return "oxlint"
end

function M.eslint_d_cmd(path)
	local local_eslint_d = M.find_local_bin(path, "eslint_d")
	if local_eslint_d then
		return local_eslint_d
	end

	local mason_eslint_d = normalize(vim.fn.stdpath("data") .. "/mason/bin/eslint_d")
	if mason_eslint_d and vim.fn.executable(mason_eslint_d) == 1 then
		return mason_eslint_d
	end

	local local_eslint = M.find_local_bin(path, "eslint")
	if local_eslint then
		return local_eslint
	end

	return "eslint_d"
end

function M.linters_for_buf(bufnr)
	local path = M.buf_path(bufnr)
	if not path then
		return {}, nil
	end

	local biome_root = M.find_biome_root(path)
	if biome_root then
		return { "biome_monorepo" }, biome_root
	end

	local oxc_root = M.find_oxc_root(path)
	if oxc_root then
		return { "oxlint_monorepo" }, oxc_root
	end

	local eslint_root = M.find_eslint_root(path)
	if eslint_root then
		return { "eslint_d_monorepo" }, eslint_root
	end

	return {}, nil
end

return M

local M = {}
local uv = vim.loop
local PATH_SEP = package.config:sub(1, 1)

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
local TOOLCHAIN_MARKER_LOOKUP = {}
for _, marker in ipairs(BIOME_CONFIG_FILES) do
	TOOLCHAIN_MARKER_LOOKUP[marker] = true
end
for _, marker in ipairs(OXC_CONFIG_FILES) do
	TOOLCHAIN_MARKER_LOOKUP[marker] = true
end
for _, marker in ipairs(ESLINT_CONFIG_FILES) do
	TOOLCHAIN_MARKER_LOOKUP[marker] = true
end
local TOOLCHAIN_MARKERS_BY_KIND = {
	biome = BIOME_CONFIG_FILES,
	oxc = OXC_CONFIG_FILES,
	eslint = ESLINT_CONFIG_FILES,
}
local toolchain_cache = {}
local bin_cache = {}

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

local function join_path(dir, entry)
	if dir:sub(-1) == PATH_SEP then
		return dir .. entry
	end
	return dir .. PATH_SEP .. entry
end

local function root_has_marker(root, markers)
	for _, marker in ipairs(markers) do
		if uv.fs_stat(join_path(root, marker)) then
			return true
		end
	end
	return false
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

local function toolchain_for_path(path)
	local normalized = normalize(path)
	if not normalized then
		return nil, nil
	end

	local cached = toolchain_cache[normalized]
	if cached and cached.kind and cached.root then
		local markers = TOOLCHAIN_MARKERS_BY_KIND[cached.kind]
		if markers and root_has_marker(cached.root, markers) then
			return cached.kind, cached.root
		end
	end

	local biome_root = find_upward(path, BIOME_CONFIG_FILES)
	if biome_root then
		toolchain_cache[normalized] = { kind = "biome", root = biome_root }
		return "biome", biome_root
	end

	local oxc_root = find_upward(path, OXC_CONFIG_FILES)
	if oxc_root then
		toolchain_cache[normalized] = { kind = "oxc", root = oxc_root }
		return "oxc", oxc_root
	end

	local eslint_root = find_upward(path, ESLINT_CONFIG_FILES)
	if eslint_root then
		toolchain_cache[normalized] = { kind = "eslint", root = eslint_root }
		return "eslint", eslint_root
	end

	toolchain_cache[normalized] = nil
	return nil, nil
end

function M.find_biome_root(path)
	local kind, root = toolchain_for_path(path)
	return kind == "biome" and root or nil
end

function M.find_eslint_root(path)
	local kind, root = toolchain_for_path(path)
	return kind == "eslint" and root or nil
end

function M.find_oxc_root(path)
	local kind, root = toolchain_for_path(path)
	return kind == "oxc" and root or nil
end

function M.is_biome_buffer(bufnr)
	local kind = toolchain_for_path(M.buf_path(bufnr))
	return kind == "biome"
end

function M.is_oxc_buffer(bufnr)
	local kind = toolchain_for_path(M.buf_path(bufnr))
	return kind == "oxc"
end

function M.javascript_formatters(bufnr)
	local kind = toolchain_for_path(M.buf_path(bufnr))
	if kind == "biome" then
		return { { "biome", "prettierd", "prettier" } }
	end
	if kind == "oxc" then
		return { { "oxfmt", "prettierd", "prettier" } }
	end
	return { { "prettierd", "prettier" } }
end

function M.find_local_bin(path, binary_name)
	local start_dir = dirname(path)
	if not start_dir then
		return nil
	end
	local cache_key = start_dir .. "::" .. binary_name
	local cached = bin_cache[cache_key]
	if cached and vim.fn.executable(cached) == 1 then
		return cached
	end

	local found = vim.fs.find("node_modules/.bin/" .. binary_name, { path = start_dir, upward = true })[1]
	local normalized = normalize(found)
	if normalized then
		bin_cache[cache_key] = normalized
	end
	return normalized
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

	local kind, root = toolchain_for_path(path)
	if kind == "biome" then
		return { "biome_monorepo" }, root
	elseif kind == "oxc" then
		return { "oxlint_monorepo" }, root
	elseif kind == "eslint" then
		return { "eslint_d_monorepo" }, root
	end

	return {}, nil
end

function M.is_toolchain_marker_file(path)
	local normalized = normalize(path)
	if not normalized then
		return false
	end
	local basename = vim.fs.basename(normalized)
	return TOOLCHAIN_MARKER_LOOKUP[basename] == true
end

function M.clear_caches()
	toolchain_cache = {}
	bin_cache = {}
end

return M

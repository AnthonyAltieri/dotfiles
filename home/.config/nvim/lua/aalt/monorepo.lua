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
local JS_FILETYPE_FAMILIES = {
	javascript = true,
	javascriptreact = true,
	["javascript.jsx"] = true,
	typescript = true,
	typescriptreact = true,
	["typescript.tsx"] = true,
}

local TOOLCHAIN_MARKER_LOOKUP = {}
local CACHE_INVALIDATOR_LOOKUP = {
	["package.json"] = true,
}

for _, marker in ipairs(BIOME_CONFIG_FILES) do
	TOOLCHAIN_MARKER_LOOKUP[marker] = true
	CACHE_INVALIDATOR_LOOKUP[marker] = true
end
for _, marker in ipairs(OXC_CONFIG_FILES) do
	TOOLCHAIN_MARKER_LOOKUP[marker] = true
	CACHE_INVALIDATOR_LOOKUP[marker] = true
end
for _, marker in ipairs(ESLINT_CONFIG_FILES) do
	TOOLCHAIN_MARKER_LOOKUP[marker] = true
	CACHE_INVALIDATOR_LOOKUP[marker] = true
end

local TOOLCHAIN_MARKERS_BY_KIND = {
	biome = BIOME_CONFIG_FILES,
	oxc = OXC_CONFIG_FILES,
	eslint = ESLINT_CONFIG_FILES,
}

local toolchain_cache = {}
local bin_cache = {}
local eslint_policy_cache = {}

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

local function find_upward_file(path, markers)
	local start_dir = dirname(path)
	if not start_dir then
		return nil
	end
	return vim.fs.find(markers, { path = start_dir, upward = true })[1]
end

local function copy_list(items)
	local copied = {}
	for _, item in ipairs(items or {}) do
		copied[#copied + 1] = item
	end
	return copied
end

local function read_file(path)
	local file = io.open(path, "r")
	if not file then
		return nil
	end

	local content = file:read("*a")
	file:close()
	return content
end

local function with_stop_after_first(items)
	local copied = copy_list(items)
	copied.stop_after_first = true
	return copied
end

local function filetype_family(bufnr)
	local filetype = vim.bo[bufnr or 0].filetype
	if JS_FILETYPE_FAMILIES[filetype] then
		return filetype
	end
	return filetype ~= "" and filetype or "unknown"
end

local function command_exists(command)
	if not command or command == "" then
		return false
	end
	return vim.fn.executable(command) == 1
end

local function relative_to(root, path)
	if not root or not path then
		return path
	end
	if path == root then
		return vim.fs.basename(path)
	end
	if path:sub(1, #root) ~= root then
		return path
	end
	local relative = path:sub(#root + 1)
	if relative:sub(1, 1) == PATH_SEP then
		relative = relative:sub(2)
	end
	return relative ~= "" and relative or vim.fs.basename(path)
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

local function eslint_rule_enabled(value)
	if value == nil then
		return false
	end
	if type(value) == "string" then
		return value ~= "off"
	end
	if type(value) == "number" then
		return value ~= 0
	end
	if type(value) == "table" then
		return eslint_rule_enabled(value[1])
	end
	return true
end

function M.buf_path(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr or 0)
	if name == "" then
		return nil
	end
	return normalize(name)
end

function M.toolchain_for_path(path)
	return toolchain_for_path(path)
end

function M.toolchain_for_buf(bufnr)
	return toolchain_for_path(M.buf_path(bufnr))
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

function M.find_local_bin(path, binary_name)
	local start_dir = dirname(path)
	if not start_dir then
		return nil
	end
	local cache_key = start_dir .. "::" .. binary_name
	local cached = bin_cache[cache_key]
	if cached and command_exists(cached) then
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
	if mason_oxfmt and command_exists(mason_oxfmt) then
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
	if mason_oxlint and command_exists(mason_oxlint) then
		return mason_oxlint
	end

	return "oxlint"
end

function M.eslint_probe_cmd(path)
	local local_eslint = M.find_local_bin(path, "eslint")
	if local_eslint then
		return local_eslint
	end
	if command_exists("eslint") then
		return "eslint"
	end
	return nil
end

function M.eslint_lint_cmd(path)
	local local_eslint_d = M.find_local_bin(path, "eslint_d")
	if local_eslint_d then
		return local_eslint_d
	end

	local mason_eslint_d = normalize(vim.fn.stdpath("data") .. "/mason/bin/eslint_d")
	if mason_eslint_d and command_exists(mason_eslint_d) then
		return mason_eslint_d
	end

	local local_eslint = M.find_local_bin(path, "eslint")
	if local_eslint then
		return local_eslint
	end

	return "eslint_d"
end

function M.eslint_format_cmd(path)
	local local_eslint_d = M.find_local_bin(path, "eslint_d")
	if local_eslint_d then
		return local_eslint_d
	end

	local mason_eslint_d = normalize(vim.fn.stdpath("data") .. "/mason/bin/eslint_d")
	if mason_eslint_d and command_exists(mason_eslint_d) then
		return mason_eslint_d
	end

	return "eslint_d"
end

function M.eslint_format_policy(path, family)
	local normalized = normalize(path)
	local kind, root = toolchain_for_path(normalized)
	if kind ~= "eslint" or not root then
		return nil
	end

	local policy_family = family or "unknown"
	local cache_key = root .. "::" .. policy_family
	local cached = eslint_policy_cache[cache_key]
	if cached then
		return cached
	end

	local eslint_cmd = M.eslint_probe_cmd(normalized)
	local eslint_config_file = find_upward_file(normalized, ESLINT_CONFIG_FILES)
	local function fallback_config_scan(primary_reason)
		if not eslint_config_file then
			return {
				cache_key = cache_key,
				command = eslint_cmd,
				cwd = root,
				enabled = false,
				probe_error = primary_reason,
				reason = primary_reason,
				status = "probe_failed",
			}
		end

		local config_contents = read_file(eslint_config_file)
		if not config_contents then
			return {
				cache_key = cache_key,
				command = eslint_cmd,
				cwd = root,
				enabled = false,
				probe_error = primary_reason,
				reason = primary_reason,
				status = "probe_failed",
			}
		end

		if config_contents:find("prettier/prettier", 1, true) then
			return {
				cache_key = cache_key,
				command = eslint_cmd,
				cwd = root,
				enabled = true,
				probe_error = primary_reason,
				reason = string.format(
					"Primary ESLint probe failed; fallback config scan found prettier/prettier in %s.",
					eslint_config_file
				),
				status = "fallback_enabled",
			}
		end

		return {
			cache_key = cache_key,
			command = eslint_cmd,
			cwd = root,
			enabled = false,
			probe_error = primary_reason,
			reason = string.format(
				"Primary ESLint probe failed; fallback config scan did not find prettier/prettier in %s.",
				eslint_config_file
			),
			status = "fallback_disabled",
		}
	end

	if not eslint_cmd then
		local result = fallback_config_scan("Could not find an eslint binary for --print-config.")
		eslint_policy_cache[cache_key] = result
		return result
	end

	local relative_path = relative_to(root, normalized)
	local completed = vim.system({ eslint_cmd, "--print-config", relative_path }, {
		cwd = root,
		text = true,
	}):wait()
	local stdout = vim.trim(completed.stdout or "")
	local stderr = vim.trim(completed.stderr or "")

	if completed.code ~= 0 then
		local result = fallback_config_scan(stderr ~= "" and stderr or stdout ~= "" and stdout or "eslint --print-config failed.")
		eslint_policy_cache[cache_key] = result
		return result
	end

	local ok, decoded = pcall(vim.json.decode, stdout, { luanil = { object = true, array = true } })
	if not ok or type(decoded) ~= "table" then
		local result = fallback_config_scan(ok and "Could not parse eslint --print-config output." or decoded)
		eslint_policy_cache[cache_key] = result
		return result
	end

	local enabled = eslint_rule_enabled((decoded.rules or {})["prettier/prettier"])
	local result = {
		cache_key = cache_key,
		command = eslint_cmd,
		cwd = root,
		enabled = enabled,
		reason = enabled and "Resolved ESLint config enables prettier/prettier."
			or "Resolved ESLint config does not enable prettier/prettier.",
		status = enabled and "enabled" or "disabled",
	}
	eslint_policy_cache[cache_key] = result
	return result
end

function M.formatter_state_for_buf(bufnr)
	local path = M.buf_path(bufnr)
	local kind, root = toolchain_for_path(path)
	local family = filetype_family(bufnr)

	if kind == "biome" then
		return {
			detected_toolchain = "biome",
			detected_root = root,
			detected_policy = "biome-only",
			formatters = { "biome" },
			reason = "Biome markers detected; Biome owns formatting in this subtree.",
		}
	end

	if kind == "oxc" then
		return {
			detected_toolchain = "oxc",
			detected_root = root,
			detected_policy = "oxc-only",
			formatters = { "oxfmt" },
			reason = "OXC markers detected; oxfmt owns formatting in this subtree.",
		}
	end

	if kind == "eslint" then
		local policy = M.eslint_format_policy(path, family)
		if policy and (policy.status == "enabled" or policy.status == "fallback_enabled") then
			return {
				detected_toolchain = "eslint",
				detected_root = root,
				detected_policy = "eslint-only",
				formatters = { "eslint_d_monorepo" },
				policy_details = policy,
				reason = "Resolved ESLint config enables prettier/prettier, so ESLint owns formatting here.",
			}
		end
		if policy and (policy.status == "disabled" or policy.status == "fallback_disabled") then
			return {
				detected_toolchain = "eslint",
				detected_root = root,
				detected_policy = "eslint+prettier",
				formatters = { "prettierd", "prettier" },
				policy_details = policy,
				reason = "Resolved ESLint config does not enable prettier/prettier, so Prettier handles formatting.",
			}
		end
		return {
			detected_toolchain = "eslint",
			detected_root = root,
			detected_policy = "probe-failed",
			formatters = {},
			policy_details = policy,
			reason = policy and policy.reason or "Could not determine ESLint formatting ownership.",
		}
	end

	return {
		detected_toolchain = kind or "none",
		detected_root = root or "-",
		detected_policy = "default-prettier",
		formatters = { "prettierd", "prettier" },
		reason = "No monorepo toolchain markers detected; using default Prettier routing.",
	}
end

function M.javascript_formatters(bufnr)
	return with_stop_after_first(M.formatter_state_for_buf(bufnr).formatters)
end

function M.linter_state_for_buf(bufnr)
	local path = M.buf_path(bufnr)
	if not path then
		return {
			detected_toolchain = "none",
			detected_root = "-",
			linters = {},
			reason = "Buffer has no file path.",
		}
	end

	local kind, root = toolchain_for_path(path)
	if kind == "biome" then
		return {
			detected_toolchain = "biome",
			detected_root = root,
			linters = { "biome_monorepo" },
			reason = "Biome markers detected; Biome owns linting in this subtree.",
		}
	end
	if kind == "oxc" then
		return {
			detected_toolchain = "oxc",
			detected_root = root,
			linters = { "oxlint_monorepo" },
			reason = "OXC markers detected; oxlint owns linting in this subtree.",
		}
	end
	if kind == "eslint" then
		return {
			detected_toolchain = "eslint",
			detected_root = root,
			linters = { "eslint_d_monorepo" },
			reason = "ESLint markers detected; ESLint owns linting in this subtree.",
		}
	end

	return {
		detected_toolchain = "none",
		detected_root = "-",
		linters = {},
		reason = "No monorepo linter configured for this buffer.",
	}
end

function M.linters_for_buf(bufnr)
	local state = M.linter_state_for_buf(bufnr)
	return copy_list(state.linters), state.detected_root ~= "-" and state.detected_root or nil
end

function M.is_toolchain_marker_file(path)
	local normalized = normalize(path)
	if not normalized then
		return false
	end
	local basename = vim.fs.basename(normalized)
	return TOOLCHAIN_MARKER_LOOKUP[basename] == true
end

function M.is_cache_invalidator_file(path)
	local normalized = normalize(path)
	if not normalized then
		return false
	end
	local basename = vim.fs.basename(normalized)
	return CACHE_INVALIDATOR_LOOKUP[basename] == true
end

function M.clear_caches()
	toolchain_cache = {}
	bin_cache = {}
	eslint_policy_cache = {}
end

return M

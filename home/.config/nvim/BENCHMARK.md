# Neovim Monorepo Routing Benchmark

Date: 2026-02-06

## Scope

Benchmarked the routing hot paths used by save-time formatting/linting:

- `monorepo.linters_for_buf(bufnr)`
- `monorepo.javascript_formatters(bufnr)`

for three representative scopes:

- Biome: `apps/signal/src/routes/api.ts`
- ESLint/Prettier: `apps/admin/next.config.ts`
- OXC (temporary synthetic scope): `/tmp/oxc-bench/src/index.ts` with `.oxlintrc.json` + `.oxfmtrc.json`

## Baseline vs Optimized

- Baseline: checkpoint commit `8306e33` (`Add monorepo-aware biome/eslint/oxc format+lint routing`)
- Optimized: current working tree with:
  - toolchain/binary positive-result caches in `monorepo.lua`
  - cache invalidation when marker files are saved
  - lint autocmd filetype gating (JS/TS only)

## Method

- Command:
  - `XDG_CONFIG_HOME=/Users/anthonyaltieri/code/dotfiles/dot_config nvim --headless -u /Users/anthonyaltieri/code/dotfiles/dot_config/nvim/init.lua -c 'lua dofile("/tmp/nvim_bench_routing.lua")'`
- Each benchmark case:
  - 200 warm-up iterations
  - 5000 measured iterations
- Metric:
  - average microseconds per call (`avg_us`)

## Results

| Case | Baseline avg_us | Optimized avg_us | Improvement |
| --- | ---: | ---: | ---: |
| `linters_for_buf.biome` | 31.6486 | 10.3688 | 67.2% |
| `linters_for_buf.eslint` | 165.7564 | 10.7102 | 93.5% |
| `linters_for_buf.oxc` | 40.8943 | 6.4839 | 84.1% |
| `javascript_formatters.biome` | 29.9428 | 11.9614 | 60.1% |
| `javascript_formatters.eslint` | 77.0899 | 11.2402 | 85.4% |
| `javascript_formatters.oxc` | 46.4385 | 6.2705 | 86.5% |

## Critical Pass Notes

Changes that produced the measured improvements:

1. Removed redundant repeated marker lookups by funneling routing through one shared `toolchain_for_path` call.
2. Added positive-result caches for:
   - toolchain root detection (per file path)
   - local binary resolution (per start directory + binary name)
3. Added cache invalidation when toolchain marker files are saved:
   - `biome.json`, `biome.jsonc`, `.oxlintrc.json`, `.oxfmtrc.json`, `eslint.config.*`, `.eslintrc*`
4. Added JS/TS filetype guard before running lint-on-save routing logic.

## Correctness Re-Validation After Optimization

Re-verified after optimization:

- Baseline scopes:
  - `apps/signal` still routes to Biome
  - `apps/admin` and `packages/utils` still route to ESLint/Prettier
- Temporary OXC switch in `packages/utils` still routes correctly to `oxfmt` + `oxlint`
- Save probes:
  - OXC formatting rewrites file content on save
  - OXC lint diagnostics are emitted on save (`source: oxlint`)

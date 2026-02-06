# Neovim monorepo formatting/linting verification

## Goal
- Ensure auto formatting and linting on save works in `~/code/webapps-clone` with path-aware tool routing.
- Use `biome` for `apps/signal` and `packages/sf`.
- Use `eslint` + `prettier` for other JS/TS projects in the monorepo.

## Success criteria
- Saving files in `apps/signal` or `packages/sf` runs Biome formatting/linting behavior.
- Saving files outside those paths runs Prettier formatting and ESLint diagnostics.
- No double-formatting or conflicting diagnostics from multiple JS/TS linters on save.
- Behavior is stable regardless of opened cwd inside `~/code/webapps-clone`.

## Assumptions / constraints
- `~/code/webapps-clone` has mixed tool configs for Biome and ESLint/Prettier.
- Neovim config changes happen only in this `dotfiles` repo.
- We will validate with targeted test files and repeatable commands.

## Plan
- [x] Capture baseline behavior from current config and test against representative monorepo files.
- [x] Build an explicit JS/TS path matrix (Biome scopes and ESLint/Prettier scopes).
- [x] Implement path-aware formatter selection in Conform for save-time formatting.
- [x] Implement path-aware linter selection for diagnostics (Biome in scoped paths, ESLint elsewhere).
- [x] Prevent formatter/linter overlap and conflicting save hooks.
- [x] Re-run the full path matrix and iterate until every case passes.
- [x] Document final results and any follow-up risks in the review section.

## Risks / edge cases
- Monorepo root detection may differ when Neovim launches from nested directories.
- Missing local configs or binaries can cause fallback behavior to look like routing bugs.
- Mixed LSP and external linter diagnostics can create duplicate messages.

## Verification plan
- [x] Validate formatter selection on save for at least one file per scope in the matrix.
- [x] Validate linter diagnostics source for at least one file per scope in the matrix.
- [x] Verify save behavior from both repo root and a nested package cwd.
- [x] Confirm no unexpected diagnostics/formatters are triggered in any matrix case.

## Review
- Baseline (before changes): JS/TS formatting always selected `oxfmt` first and linting attempted `oxlint` (missing in PATH), so monorepo routing was not working.
- Added shared path/root detection in `lua/aalt/monorepo.lua` for Biome and ESLint scopes.
- Conform now routes JS/TS formatters by nearest config:
- Biome scopes use `biome` first (with fallback only if unavailable), and non-Biome scopes use `prettierd`/`prettier`.
- Added `nvim-lint` on-save hook (`BufWritePost`) with project-aware linter selection:
- Biome scopes run `biome`; ESLint scopes run `eslint_d`.
- Verified matrix from repo root and nested cwd (`packages/ui`) with headless Neovim probes:
- `apps/signal` and `packages/sf` select Biome formatter/linter.
- `apps/admin`, `apps/webapp`, and `packages/ui` select Prettier formatter + ESLint diagnostics.
- Save-time behavior verified with temporary probe files:
- Formatting on save rewrote content in both Biome and Prettier scopes.
- Lint-on-save emitted diagnostics from `eslint_d` and `biomejs` in their respective scopes.

## OXC Extension Goal
- Ensure `oxfmt` + `oxlint` can also be selected and run on save for a monorepo subproject.

## OXC Plan
- [x] Add OXC root detection and tool selection to monorepo routing.
- [x] Add Conform formatter routing for OXC scopes (`oxfmt` first).
- [x] Add `nvim-lint` linter routing for OXC scopes (`oxlint`).
- [x] Ensure OXC binaries are available for verification (Mason + local fallback).
- [x] Temporarily switch one subproject in `~/code/webapps-clone` to OXC config.
- [x] Verify save-format and save-lint diagnostics in that OXC test scope.
- [x] Revert temporary subproject switch and confirm baseline scopes still route correctly.

## OXC Review
- Added OXC config detection markers (`.oxlintrc.json`, `.oxfmtrc.json`) to shared monorepo routing.
- Added `oxfmt` formatter definition and path-aware command/cwd resolution in Conform.
- Added `oxlint` linter definition in `nvim-lint` with JSON output parsing.
- Installed `oxfmt` and `oxlint` via Mason for deterministic test execution.
- Temporary OXC switch performed in `packages/utils` with short-lived `.oxlintrc.json` + `.oxfmtrc.json`.
- During temporary switch:
- `packages/utils` selected `["oxfmt","prettierd","prettier"]` for formatting and `["oxlint_monorepo"]` for linting.
- Save-format rewrote probe file content using `oxfmt`.
- Save-lint emitted diagnostics with source `oxlint` (plus expected parser diagnostics from `typescript` on invalid syntax probe).
- Removed temporary OXC config files from `packages/utils` after verification.
- Post-revert verification confirmed routing returned to:
- `packages/utils` -> `eslint_d` + `prettierd`/`prettier`
- `apps/signal` -> `biome`
- `apps/admin` -> `eslint_d` + `prettierd`/`prettier`

# Neovim config updates

## Goal
- Make LSP hover/signature use native handlers on `<M-v>`.
- Make `<C-p>` act like VSCode “Quick Open” (normal + insert), including hidden files, respecting `.gitignore`, but always showing `.env*`.
- Add smoother/faster-feeling scrolling with `neoscroll.nvim` + acceleration for `j/k` and `<Up>/<Down>`.
- Add JS/TS lint + format support preferring `oxlint` and `oxfmt`.

## Success criteria
- `<M-v>` shows hover docs in normal mode and signature help in insert mode.
- `<C-p>` opens a fast file picker in normal + insert and includes `.env*` even when ignored.
- Holding `j/k` or `<Up>/<Down>` speeds up movement; scrolling feels smoother.
- JS/TS shows lint diagnostics (oxlint) and formats on save with oxfmt when available.

## Assumptions / constraints
- macOS + Homebrew available for installing `fzf`.
- New plugins will be installed by Lazy on next Neovim start (or via `:Lazy sync`).
- Mason will manage `oxlint`/`oxfmt` binaries (download on demand).

## Plan
- [x] Switch hover/signature keymaps to native LSP and remove lspsaga usage.
- [x] Add `fzf-lua` quick open on `<C-p>` (n+i), and remap nvim-cmp’s `<C-p>` to avoid conflict.
- [x] Add `neoscroll.nvim` and `accelerated-jk` for smooth + accelerated movement.
- [x] Prefer `oxfmt` in Conform; add `oxlint` LSP setup and Mason installs.
- [x] Format Lua (stylua) and run a headless Neovim syntax load.

## Risks / edge cases
- Terminal may not send `<M-v>` consistently depending on settings.
- `<C-p>` in insert mode conflicts with nvim-cmp’s default mapping (will be remapped).
- `oxlint` LSP integration relies on `oxlint --lsp` being available from Mason.

## Verification
- [x] Run `~/.local/share/nvim/mason/bin/stylua` on changed Lua files.
- [x] Run a headless syntax load with `nvim -u NONE --headless` (sandbox blocks writing to `~/.cache`/`~/.local/state`).

## Review
- Installed `fzf` via Homebrew for `fzf-lua` quick open.
- Verified Lua formatting with `stylua`.
- Verified changed Lua files load without syntax/runtime errors via `nvim -u NONE --headless`.
- Fixed `accelerated-jk` startup error by removing an invalid `require()` (plugin is Vimscript-only).
- Fixed `fzf-lua` devicons API mismatch by switching file icons to `mini.icons`.

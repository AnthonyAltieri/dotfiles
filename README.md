# dotfiles

Managed with [chezmoi](https://www.chezmoi.io/).

## Setup a new machine

```bash
git clone git@github.com:AnthonyAltieri/dotfiles.git ~/code/dotfiles
~/code/dotfiles/bootstrap.sh
```

This will:
1. Install Homebrew (macOS, if missing)
2. Install chezmoi (if missing)
3. Run chezmoi bootstrap scripts (packages, Oh My Zsh, zsh plugins, TPM, NVM)
4. Deploy all dotfiles

## Day-to-day usage

Edit a config:

```bash
chezmoi edit ~/.zshrc
chezmoi apply
```

Add a new file:

```bash
chezmoi add ~/.config/some-tool/config
```

See what would change:

```bash
chezmoi diff
```

Pull and apply updates:

```bash
chezmoi update
```

## How chezmoi works

[chezmoi](https://www.chezmoi.io/) manages dotfiles by keeping a **source directory** (this repo) that maps to files in your home directory. It never symlinks — it copies files into place, so your home directory has normal files and chezmoi owns the "source of truth" in the repo.

### File naming conventions

chezmoi uses special prefixes in the source directory to control how files are deployed:

| Source (this repo)                  | Deployed to                        |
|-------------------------------------|------------------------------------|
| `dot_zshrc`                         | `~/.zshrc`                         |
| `dot_config/nvim/init.lua`          | `~/.config/nvim/init.lua`          |
| `dot_config/starship.toml`          | `~/.config/starship.toml`          |
| `executable_dev`                    | `dev` (with `chmod +x`)            |

The `dot_` prefix becomes a `.` in the target path. The `executable_` prefix sets the file as executable. Directories map 1:1 (minus the prefixes).

### Bootstrap scripts

Scripts in `.chezmoiscripts/` run automatically during `chezmoi apply`. The naming controls **when** and **how often** they run:

```
.chezmoiscripts/
├── darwin/                          # macOS-only scripts
│   ├── run_once_before_01-install-homebrew.sh.tmpl
│   ├── run_once_before_02-install-brews.sh.tmpl
│   └── run_once_before_03-configure-macos-keyboard.sh.tmpl
├── run_once_before_03-install-oh-my-zsh.sh
├── run_once_before_04-install-zsh-plugins.sh
├── run_once_before_05-install-tpm.sh
└── run_once_before_06-install-nvm.sh
```

Breaking down the name `run_once_before_01-install-homebrew.sh.tmpl`:

- **`run_once`** — chezmoi tracks a hash of the script and only re-runs it if the contents change. Without this, it would run on every `chezmoi apply`.
- **`before`** — run before any files are copied into place (use `after` for the opposite).
- **`01-`** — controls execution order. Scripts run in lexicographic order, so `01-` runs before `02-`, etc.
- **`.tmpl`** — the file is a chezmoi template. This lets you use Go template syntax like `{{ if eq .chezmoi.os "darwin" }}` to conditionally include content (e.g., skip macOS-specific scripts on Linux).

### Templates

Files ending in `.tmpl` are processed through Go's `text/template` engine before being deployed. This repo uses templates mainly for OS guards in scripts:

```bash
{{ if eq .chezmoi.os "darwin" -}}
#!/bin/bash
# This only runs on macOS
{{ end -}}
```

The trailing `-` trims whitespace so the rendered output is clean.

### Key commands

| Command             | What it does                                           |
|---------------------|--------------------------------------------------------|
| `chezmoi add FILE`  | Copy a file from `~` into the source directory         |
| `chezmoi edit FILE` | Open the source version of a file in your editor       |
| `chezmoi diff`      | Show what `apply` would change (dry-run diff)          |
| `chezmoi apply`     | Deploy everything: run scripts + copy files to `~`     |
| `chezmoi update`    | `git pull` the source repo then `apply`                |

After editing files in this repo directly (not via `chezmoi edit`), run `chezmoi apply` to push changes to your home directory.

## What's included

- **zsh** — Oh My Zsh with zsh-autosuggestions and F-Sy-H
- **neovim** — Lazy.nvim config with LSP, Telescope, Treesitter
- **tmux** — TPM with vim-tmux-navigator
- **starship** — Cross-shell prompt
- **ghostty** — Terminal config (macOS)

## Codex configuration

This repo manages a curated subset of `~/.codex` via `dot_codex/`:

- `~/.codex/AGENTS.md`
- `~/.codex/prompts/pr.md`
- `~/.codex/rules/default.rules`
- `~/.codex/skills/{atlas,gh-address-comments,gh-fix-ci,gh-manage-pr,notion-knowledge-capture}`

Machine-local Codex state is intentionally not managed, including auth/history/sessions/worktrees/sqlite/logs/cache.

`~/.codex/config.toml` is intentionally local-only so each machine can keep its own trust settings and local runtime preferences.

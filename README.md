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

## What's included

- **zsh** — Oh My Zsh with zsh-autosuggestions and F-Sy-H
- **neovim** — Lazy.nvim config with LSP, Telescope, Treesitter
- **tmux** — TPM with vim-tmux-navigator
- **starship** — Cross-shell prompt
- **ghostty** — Terminal config (macOS)

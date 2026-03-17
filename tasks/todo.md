# Bootstrap tmux fix

## Goal

Make `bootstrap.sh` reliably leave `tmux` available as a shell command on macOS.

## Success criteria

- `bootstrap.sh` can keep using Homebrew after installing it in the same run.
- New zsh shells load Homebrew on `PATH`.
- `tmux` from Homebrew is discoverable after bootstrap completes.

## Assumptions / constraints

- The repo is used on macOS with either `/opt/homebrew` or `/usr/local` Homebrew prefixes.
- Changes should stay narrow and not disturb unrelated shell setup.

## Steps

- [x] Inspect bootstrap, chezmoi scripts, and zsh startup for Homebrew and tmux setup.
- [x] Patch bootstrap and shell startup to load Homebrew consistently.
- [x] Verify edited files with targeted syntax checks and diff review.
- [x] Add a short review summary.

## Risks / edge cases

- Apple Silicon and Intel Homebrew prefixes differ.
- `brew shellenv` should only run when `brew` exists.

## Verification plan

- Run `bash -n` on edited shell scripts.
- Run `zsh -n` on edited zsh config.
- Review `git diff` for minimal, correct changes.

## Review

- Root cause: Homebrew-managed binaries were not guaranteed to be on `PATH` after bootstrap, especially on Apple Silicon where Homebrew lives under `/opt/homebrew`.
- Change: `bootstrap.sh` now loads `brew shellenv`, the macOS brew-install chezmoi script does the same before `brew bundle`, and zsh startup initializes Homebrew for new shells.
- Verification: `bash -n bootstrap.sh`, `bash -n .chezmoiscripts/darwin/run_once_before_02-install-brews.sh.tmpl`, and `zsh -n dot_config/zsh/config.zsh` all passed; `git diff` was reviewed for scope and correctness.

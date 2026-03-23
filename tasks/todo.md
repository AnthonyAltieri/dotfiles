# Nix Migration

## Goal

Replace the current chezmoi-managed dotfiles repo with a flake-based Nix layout that composes role and platform modules.

## Success criteria

- `flake.nix` exposes Darwin and Linux/Home Manager outputs for `personal`, `work`, and `sandbox`.
- Existing managed payloads are sourced from `home/` and linked into `$HOME` via Nix modules.
- Darwin uses `nix-darwin` with declarative Homebrew and macOS defaults.
- Linux uses Home Manager with Nix packages instead of distro package managers.
- chezmoi-era scripts, ignore rules, and docs are removed or replaced.

## Assumptions / constraints

- The repo remains conservative in v1: current shared behavior stays shared.
- `personal` and `work` overlays remain thin until real differences exist.
- `sandbox` is standalone and does not import the public `common` role.
- Local runtime state under `~/.codex` and similar machine-local directories remains unmanaged.
- Verification is limited by the current environment if `nix` or `home-manager` are unavailable.

## Steps

- [x] Audit the moved payloads in `home/` and finalize the exact Nix file mappings.
- [x] Create `flake.nix`, `lib/`, and role/platform/shared modules.
- [x] Wire Darwin/Homebrew, Linux/Nix packages, and file linking for shared payloads.
- [x] Replace bootstrap and README workflow from chezmoi to Nix.
- [x] Remove chezmoi-era files and clean up the repo layout.
- [x] Run available verification and record the review.

## Risks / edge cases

- `nix-darwin` and Home Manager option syntax cannot be fully validated without local Nix tooling.
- `tsgo` may still require a compatibility activation hook.
- Existing shell files contain macOS/Homebrew assumptions that must be softened for Linux.
- Homebrew integration on Darwin depends on Homebrew already being installed or bootstrapped.

## Verification plan

- Run shell syntax checks on `bootstrap.sh`.
- If `nix` is available, run `nix flake check` and targeted build commands for the exposed outputs.
- Review `git diff --stat` and `git diff` for scope and correctness.
- Call out any verification gaps caused by missing local tooling.

## Review

- Implemented a flake-based Nix layout with separate constructor helpers, shared Home Manager modules, Darwin `nix-darwin` system modules, Linux package modules, and role overlays for `common`, `personal`, `work`, and `sandbox`.
- Moved the managed payloads into `home/` using actual target names, linked the curated `~/.codex` and `~/.claude` subsets without taking over local runtime state, and replaced the old chezmoi bootstrap/docs with Nix workflows.
- Corrected two Home Manager evaluation hazards during review: `modules/shared/shell.nix` now uses the documented `programs.zsh.enableAutosuggestions`, `programs.zsh.enableSyntaxHighlighting`, and `programs.zsh.initExtra` options, and `modules/shared/tmux.nix` now uses a Homebrew-backed tmux wrapper on Darwin instead of assigning `null` to a package-typed option.
- Verification completed locally: `bash -n bootstrap.sh home/.claude/statusline-command.sh home/.claude/tmux-notify.sh`, `zsh -n home/.zshrc home/.config/zsh/config.zsh home/.config/zsh/features/00_vim-command-line-navigation.zsh home/.config/zsh/features/01_mcfly.zsh home/.config/zsh/functions/git-current-branch.zsh home/.config/zsh/os/config-osx.zsh`, a stale-reference grep across the migrated repo, and a static path existence sweep across `modules/**/*.nix` and `lib/**/*.nix` all passed.
- Verification remains blocked for `nix flake check`, `nix build`, and `flake.lock` generation because `nix`, `home-manager`, and `darwin-rebuild` are not installed in this workspace.

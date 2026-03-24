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

## Follow-up: Oh My Zsh scope

- [x] Move Oh My Zsh enablement into the `common` role so `personal` and `work` inherit it while `sandbox` does not.
- [x] Review the touched Nix modules and confirm the shared shell module still handles generic zsh behavior.

## Follow-up Review

- `modules/shared/shell.nix` now keeps only the generic zsh/Home Manager wiring, while `modules/roles/common.nix` owns the `programs.zsh.oh-my-zsh` block that composes into `personal` and `work`.
- Static review confirms `sandbox` no longer receives Oh My Zsh through the shared shell module. Full `nix` evaluation remains blocked by the missing local Nix toolchain.

## Docker smoke testing

### Goal

Add a Docker-based smoke test harness that validates the Linux Home Manager profiles in a fresh container and documents the boundary between Docker-testable Linux behavior and Darwin-only behavior.

### Success criteria

- A fresh Docker container can build and activate `personal-linux`, `work-linux`, and `sandbox-x86_64-linux`.
- A fresh Docker container can evaluate Linux profiles for the host container architecture and optionally attempt full activation when requested.
- The harness asserts key managed files and commands after activation.
- The harness proves the profile difference we care about right now, including Oh My Zsh on `personal`/`work` but not `sandbox`.
- The docs explain that `nix-darwin` and macOS bootstrap validation cannot be covered by Docker.

### Steps

- [x] Add a Linux Dockerfile and runner scripts for per-profile smoke tests.
- [x] Add assertions for managed files, package availability, and profile-specific behavior.
- [x] Document how to run the Docker smoke tests and what they do not cover.
- [x] Run the available local verification on the new scripts and record the outcome.

### Risks / edge cases

- Docker can validate Linux Home Manager activation, but not `nix-darwin` or Homebrew behavior on macOS.
- Container tests will need network access to install Nix and fetch flake inputs.
- Home Manager activation can be sensitive to the configured username and home directory inside the container.
- Full activation of the Linux profiles pulls a large closure and may exceed Docker Desktop disk limits, so the default smoke test should stay evaluation-based.

### Review

- Added an Ubuntu 24.04 Docker harness in `tests/docker/ubuntu-lts/` and a host runner in `tests/run-linux-docker-smoke.sh`. The runner now targets the three logical roles, `personal`, `work`, and `sandbox`, and resolves them to the matching Linux profile architecture automatically.
- Local verification passed for `bash -n tests/run-linux-docker-smoke.sh tests/docker/ubuntu-lts/run-profile-smoke-test.sh` and `git diff --check` on the touched files.
- End-to-end Docker runs exposed and drove two real fixes: excluding the git worktree metadata from the Docker build context with `.dockerignore`, and updating `modules/shared/shell.nix` to the current Home Manager 25.05 zsh option names.
- End-to-end Docker execution is still blocked in this environment by Docker/Nix store space exhaustion while materializing flake inputs inside the container (`No space left on device` under `/nix/store`). The harness is committed as a repo asset, but it still needs to be exercised on a machine with more Docker disk available.

## Follow-up: Bootstrap ergonomics and Nix docs

### Goal

Make the bootstrap path safe to rerun as the normal update entrypoint, and add a dedicated explainer for how the Nix flake composes roles, platforms, and shared modules in this repo.

### Success criteria

- `bootstrap.sh` is explicitly idempotent for the supported Darwin roles and can be rerun after pulling repo changes.
- Bootstrap installs missing prerequisites only, reloads the required environment when they already exist, and applies the selected flake role on every run.
- The repo has a dedicated Nix explainer document covering flake structure, module composition, managed files, and day-to-day update flows.
- The top-level README points readers to the deeper Nix explainer instead of trying to carry all of that detail inline.

### Assumptions / constraints

- The bootstrap entrypoint remains Darwin-only and continues to support only `personal` and `work`.
- Linux remains Home Manager driven; the bootstrap script is not widened into a cross-platform installer in this pass.
- Verification is still limited by the lack of local Nix tooling in this workspace.

### Steps

- [x] Update `bootstrap.sh` so rerunning it is the normal supported apply/update path.
- [x] Add a dedicated Nix explainer doc under `docs/`.
- [x] Trim and link the top-level README so the overview stays readable while the detailed explanation lives in the new doc.
- [x] Run available shell/docs verification and record the follow-up review.

### Risks / edge cases

- Freshly installed Nix or Homebrew may not be on `PATH` in the current shell unless bootstrap reloads their shell environment explicitly.
- Using a built `result` symlink is convenient but can be brittle if the script does not ensure it points at the newly built system each run.
- The explainer must match the actual constructor logic in `lib/` and not drift from the implemented merge order.

### Review

- Added `docs/nix/README.md` as the long-form flake explainer. It documents the role/platform model, constructor responsibilities, merge order, directory ownership, managed versus unmanaged state, and the intended validation flows.
- Updated the top-level `README.md` to stay focused on the repo overview and supported workflows, while linking readers to the deeper Nix architecture guide for the full explanation.
- Reworked `bootstrap.sh` so the supported macOS path is explicitly rerunnable: it now verifies Darwin up front, reloads Nix and Homebrew when they are already installed, installs them only when missing, builds the selected Darwin closure without leaving a repo-local `result` symlink behind, and reapplies the chosen role on every run.
- Verification completed locally: `bash -n bootstrap.sh`, `git diff --check -- README.md bootstrap.sh docs/nix/README.md tasks/todo.md`, and a targeted docs/link grep all passed.
- Full `nix` evaluation remains blocked in this workspace because the Nix toolchain is still unavailable here, so `nix flake check`, `nix build`, and an end-to-end bootstrap run on macOS still need to happen on a machine with Nix installed.

## Follow-up: Mainline parity after Nix migration

### Goal

Carry forward the upstream skill and helper changes that landed on `main` after the Nix migration, and express the required runtime behavior declaratively in the Nix layout so the branch can merge cleanly without reviving the old chezmoi paths.

### Success criteria

- The managed `home/` tree includes the upstream Codex and Claude skill additions that were previously added under `dot_codex/` and `dot_claude/`.
- `modules/shared/files.nix` deploys the newly added managed skill trees and helper assets.
- The Nix setup installs the Rust-backed skill helper commands on `PATH` without relying on the old chezmoi bootstrap scripts.
- Shell/session and Homebrew parity gaps identified during conflict review are carried forward into the Nix config.
- Available local verification is run and the follow-up review is recorded.

### Assumptions / constraints

- The Nix layout remains the source of truth; old chezmoi-era paths are not restored.
- Rust helper binaries should be built once from the canonical managed sources, not independently from mirrored Codex and Claude copies.
- Full Nix evaluation remains blocked here if the local toolchain is unavailable.

### Steps

- [x] Import the missing upstream managed skill files into `home/.codex` and `home/.claude`.
- [x] Update `modules/shared/files.nix` and related Nix modules for the expanded managed set and shell/Homebrew parity changes.
- [x] Add declarative Nix packaging for the Rust-backed helper commands so they are on `PATH`.
- [x] Run available verification and record the follow-up review.

### Risks / edge cases

- The upstream branch added helper source trees under old paths, so the migration needs to preserve content while remapping layout, not just accept Git's default rename guesses.
- Some helper crates are mirrored between Codex and Claude; packaging the wrong source twice could create duplicate binaries or drift.
- `atlas-cli` is macOS-only in practice and should stay Darwin-scoped even though the source is now managed by the shared tree.

### Review

- Merged the upstream skill-helper and agent-guidance changes into the Nix layout by moving the new Codex and Claude payloads from the resurrected `dot_codex/` and `dot_claude/` paths into `home/`, while keeping the old chezmoi files deleted.
- Expanded `modules/shared/files.nix` so the managed profile now deploys the new skill trees (`frontend-design`, `programming`, `sql-read`) and the newly added helper assets and script trees from the moved `home/` layout.
- Added `modules/shared/skill-helpers.nix` and wired it into `lib/profiles.nix` so the Rust-backed helper commands are built from the canonical `home/.codex/skills/**/scripts` sources and exposed on `PATH` declaratively, with `atlas-cli` gated to Darwin.
- Carried forward the remaining parity fixes from `main`: `modules/shared/base.nix` now adds `$HOME/.cargo/bin` to the session path, `modules/platforms/darwin/homebrew.nix` now treats `1password-cli` as a cask, the skill docs now describe the Nix-profile helper model instead of `~/.local/bin`, and `scripts/test-skill-helpers.sh` now targets the moved `home/` sources.
- Verification completed locally: `bash -n bootstrap.sh scripts/test-skill-helpers.sh`, `git diff --check --cached`, `git ls-files -u`, a path-existence sweep for the new managed helper sources, and a stale-reference grep for `dot_codex/`, `dot_claude/`, and `~/.local/bin` assumptions all passed.
- Full `nix flake check`, `nix build`, helper-package builds, and an end-to-end profile apply are still blocked here because the local Nix toolchain is not installed in this workspace.

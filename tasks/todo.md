# Ghostty Ctrl Split Unbind

## Goal

Stop Ghostty from consuming plain `Ctrl+h/j/k/l` in the Nix-managed config so those keys can reach tmux and Neovim.

## Success criteria

- The Nix-managed Ghostty source explicitly unbinds `Ctrl+h/j/k/l`.
- Ghostty split navigation remains available on a non-conflicting shifted binding.
- Verification and review notes are recorded here.

## Assumptions / constraints

- The live Ghostty config is sourced through `modules/platforms/darwin/ghostty.nix`.
- Scope is limited to the Ghostty config and the repo task logs.
- Interactive Ghostty behavior cannot be fully exercised from this non-GUI environment.

## Steps

- [x] Update the Nix-managed Ghostty config to unbind `Ctrl+h/j/k/l` and move split navigation to `Ctrl+Shift+h/j/k/l`.
- [x] Run focused verification on the touched files and diff.
- [x] Record the review summary here.

## Risks / edge cases

- If Ghostty has additional platform-default bindings beyond the config file, the interactive session still needs a manual smoke test.
- Users with muscle memory for Ghostty's plain `Ctrl+h/j/k/l` split navigation will need to use the shifted variant instead.

## Verification plan

- Review the final diff for the Ghostty keybinding block.
- Run `git diff --check`.
- Confirm the Nix module still sources `home/.config/ghostty`.

## Review

- The Nix-managed Ghostty source now explicitly unbinds `Ctrl+h/j/k/l`, which is the required step to stop the built-in split-navigation defaults from firing.
- Terminal-level Ghostty split navigation moved to `Ctrl+Shift+h/j/k/l`, preserving the feature without conflicting with tmux and Neovim.
- Verification:
  - `git diff --check`
  - `git diff -- home/.config/ghostty/config modules/platforms/darwin/ghostty.nix tasks/todo.md tasks/lessons.md`
  - Static review of `modules/platforms/darwin/ghostty.nix`
- Remaining manual verification is interactive only: launch Ghostty from the Nix-managed setup and confirm plain `Ctrl+h/j/k/l` no longer trigger Ghostty split movement.

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

## Follow-up: Live ~/.config audit

### Goal

Compare the current machine's `~/.config/*` tree against the Nix-managed `home/.config` layout and `modules/shared/files.nix` mappings to identify configuration that exists locally but is not yet represented in the flake.

### Success criteria

- The repo's managed `~/.config` mappings are enumerated from the Nix modules.
- The current machine's `~/.config` directories are inventoried.
- Differences are classified as real Nix coverage gaps versus intentionally unmanaged or tool-generated state.
- Review findings are recorded with concrete file references.

### Assumptions / constraints

- The audit is read-only unless a follow-up implementation is explicitly requested.
- Machine-local or ephemeral runtime state should not be treated as a required Nix gap by default.
- The current repo layout under `home/.config` is the intended source of truth for managed config payloads.

### Steps

- [x] Record the repo-managed `~/.config` mappings from the current Nix modules.
- [x] Inventory the live `~/.config` tree on this machine.
- [x] Compare the live tree to the managed tree and separate real coverage gaps from intentional exclusions.
- [x] Record the audit review.

### Risks / edge cases

- Some `~/.config` entries are created by apps at runtime and should not be managed declaratively.
- The current machine may include historical config for tools that are no longer in active use.
- Directory-name matches alone are insufficient; the audit needs to consider whether the repo already manages the relevant files under a different path or mechanism.

### Review

- The flake currently manages `~/.config/nvim`, `~/.config/starship.toml`, and `~/.config/zsh` through `modules/shared/files.nix`, and manages `~/.config/ghostty` separately on Darwin through `modules/platforms/darwin/ghostty.nix`.
- The live machine has additional top-level `~/.config` entries for `cagent`, `chezmoi`, `configstore`, `gh`, `git`, `github-copilot`, `iterm2`, `karabiner`, `mlflow`, `op`, `pgcli`, `raycast`, `tmux`, `uv`, `yarn`, and `zed` that are not represented in the flake today.
- Most of those extra entries look intentionally local or tool-generated rather than declarative config targets: auth/state (`gh/hosts.yml`, `op`, `github-copilot`, `configstore`), app-local settings and caches (`raycast`, `iterm2`, `zed`, `pgcli`, `mlflow`, `uv`, `yarn`), and legacy leftovers from the migration (`chezmoi`).
- The one clear parity gap inside an actively managed area is `~/.config/zsh/functions/load-env-file.zsh`, which is sourced by the live shell pattern but is missing from `home/.config/zsh/functions`.
- `~/.config/zsh/laurel.zsh` exists locally but is not referenced by the live or managed shell entrypoints, so it currently looks like an orphaned local helper rather than a required managed file.
- `~/.config/tmux/.tmux.plugins.conf` is also not a required gap: it is the old TPM plugin list, and the flake already replaces that behavior via `programs.tmux.plugins` in `modules/shared/tmux.nix`.
- `~/.config/git/ignore` is a judgment call rather than a hard gap. It contains a single global ignore for `**/.claude/settings.local.json`; if you want that behavior to follow the repo, it should be added declaratively, otherwise it can stay local.

## Follow-up: Common tool additions

### Goal

Add `gh`, `op`, `raycast`, `uv`, and `pnpm` to the shared `common` tool surface while preserving the repo policy of using Homebrew on macOS and Nix packages on Linux.

### Success criteria

- `personal` and `work` include the requested tools through the existing platform-specific package managers.
- Darwin installs the requested macOS-native tools through `homebrew`.
- Linux installs the requested CLI tools through `home.packages`.
- `sandbox` does not accidentally inherit Linux common-role package additions through the platform layer.
- Available static verification is run and the review is recorded.

### Assumptions / constraints

- `op` maps to the existing `1password-cli` package choice.
- `raycast` remains Darwin-only.
- `pnpm` is already present in the current package sets and should stay there.
- Full `nix` evaluation is still unavailable in this workspace.

### Steps

- [x] Inspect the current role/platform package split and update the plan if common-role semantics are leaking into sandbox.
- [x] Update the Darwin and Linux package modules for the requested tool set.
- [x] Run available static verification and record the review.

### Risks / edge cases

- Linux platform modules currently apply to all Linux roles, so package additions there can accidentally affect `sandbox`.
- `raycast` is macOS-only and must not leak into Linux evaluation.
- Package naming differs between Homebrew and nixpkgs, so the mapping needs to stay explicit.

### Review

- Updated `modules/platforms/darwin/homebrew.nix` so the Darwin common-role machines now install `gh` and `uv` as Homebrew formulae and `raycast` as a cask, while preserving the existing `1password-cli` (`op`) and `pnpm` entries.
- Updated `modules/platforms/linux/packages.nix` so Linux common-role machines now install `gh` and `uv` through nixpkgs, while preserving the existing `_1password-cli` (`op`) and `pnpm` packages.
- Tightened `lib/profiles.nix` so the Linux platform package module no longer applies to the `sandbox` role. That keeps these common-role additions scoped to `personal` and `work` instead of leaking through the platform layer to all Linux roles.
- Static verification completed locally: `git diff --check -- lib/profiles.nix modules/platforms/linux/packages.nix modules/platforms/darwin/homebrew.nix tasks/todo.md`, a targeted `git diff` review of the changed package lists, and a grep sweep confirming `raycast` only appears in the Darwin Homebrew module all passed.
- Full `nix` evaluation and package build validation remain blocked in this workspace because the local Nix toolchain is still unavailable.

## Follow-up: Remove Mcfly and zsh vim mode

### Goal

Stop managing `mcfly` entirely and remove the custom zsh vim-mode command-line behavior from the shared shell configuration.

### Success criteria

- `mcfly` is removed from all managed package lists.
- The managed zsh `mcfly` hook file is removed.
- The managed zsh vim-mode feature file is removed.
- The remaining shell config still loads cleanly without stale references to the deleted features.
- Available static verification is run and the review is recorded.

### Assumptions / constraints

- The requested removal applies across all managed roles that currently inherit these shared shell behaviors.
- The feature removal should delete the managed files rather than leave inert stubs behind.
- Full `nix` evaluation remains unavailable in this workspace.

### Steps

- [x] Inspect the current package and shell feature references for `mcfly` and vim-mode behavior.
- [x] Remove the packages and managed zsh feature files.
- [x] Run available static verification, sweep for stale references, and record the review.

### Risks / edge cases

- The managed zsh loader sources every file in `home/.config/zsh/features`, so deleted feature files must be removed cleanly without leaving references elsewhere.
- `mcfly` is installed in multiple role/platform package lists, so partial removal would leave inconsistent behavior across profiles.

### Review

- Removed `mcfly` from all managed package lists in `modules/platforms/darwin/homebrew.nix`, `modules/platforms/linux/packages.nix`, and `modules/roles/sandbox.nix`, so none of the managed profiles now install it.
- Deleted the managed zsh feature files `home/.config/zsh/features/00_vim-command-line-navigation.zsh` and `home/.config/zsh/features/01_mcfly.zsh`, which removes both the custom shell vim-mode behavior and the Mcfly initialization hook from the shared zsh config.
- Static verification completed locally: `git diff --check -- modules/platforms/darwin/homebrew.nix modules/platforms/linux/packages.nix modules/roles/sandbox.nix home/.config/zsh/features tasks/todo.md`, `zsh -n home/.zshrc home/.config/zsh/config.zsh home/.config/zsh/functions/git-current-branch.zsh home/.config/zsh/os/config-osx.zsh`, and a stale-reference grep. The only remaining `mcfly` and vim-mode strings are in this historical task log, not in the managed config.
- Full `nix` evaluation remains blocked in this workspace because the local Nix toolchain is unavailable.

## Follow-up: Bootstrap preview and diff flags

### Goal

Add `--dry-run` and `--diff` to the macOS bootstrap wrapper so previewing a role change is possible without immediately switching the live system.

### Success criteria

- `bootstrap.sh` accepts `--dry-run` and `--diff` alongside `personal` or `work`.
- `--dry-run` builds the target Darwin closure but does not switch the system or install missing prerequisites.
- `--diff` shows a closure diff against the current system when one exists.
- The bootstrap docs explain the new preview behavior and the existing Home Manager backup behavior for managed file conflicts.
- Available local verification is run and the review is recorded.

### Assumptions / constraints

- The wrapper remains Darwin-only.
- A true preview still requires Nix to already be installed, because building the target closure depends on it.
- `--diff` is closure-level diffing, not a file-by-file preview of Home Manager-managed targets.

### Steps

- [x] Record the current bootstrap/diff behavior and update the plan if the implementation needs to avoid side effects in preview mode.
- [x] Implement the new bootstrap flags and preview flow.
- [x] Update docs, run targeted verification, and record the review.

### Risks / edge cases

- A preview path that auto-installs Nix or Homebrew would no longer be meaningfully dry.
- There may be no current Darwin system symlink to diff against on first install, so `--diff` must degrade gracefully.
- Closure diffs show package/system changes, but not every possible Home Manager file replacement detail.

### Review

- Updated `bootstrap.sh` to accept `--dry-run`, `--diff`, and `--help` in addition to the existing `personal` and `work` role arguments.
- `--dry-run` now builds the target Darwin closure and logs the resulting store path, but does not call `darwin-rebuild switch`. To keep the preview path side-effect free, it also refuses to auto-install missing Nix and only warns if Homebrew is missing.
- `--diff` now runs `nix store diff-closures /run/current-system <new-system-path>` after the target closure is built. If the current system symlink is missing, bootstrap logs that the diff is being skipped and continues gracefully.
- Updated `README.md` and `docs/nix/README.md` to document the preview flags and to make the existing Home Manager managed-file backup behavior explicit: conflicting targets are backed up with the `.hm-backup` suffix during a real apply.
- Verification completed locally: `bash -n bootstrap.sh`, `./bootstrap.sh --help`, `git diff --check -- bootstrap.sh README.md docs/nix/README.md tasks/todo.md`, and a targeted `git diff` review of the changed script/docs all passed.
- Full end-to-end validation of `--dry-run`, `--diff`, and a real bootstrap apply remains blocked here because the local Nix toolchain is still unavailable in this workspace.

## Follow-up: Dry-run missing-Nix UX

### Goal

Make the `--dry-run` failure mode explicit when Nix is not installed yet, so the first-install limitation is obvious instead of looking like a broken preview path.

### Success criteria

- `bootstrap.sh --dry-run` explains that a preview requires an existing Nix installation.
- The message tells the user the two valid next steps: run a real bootstrap once or install Nix manually first.
- The docs call out that `--dry-run` is only available after Nix exists on the machine.
- The follow-up review and lesson are recorded.

### Steps

- [x] Update the dry-run error message and usage/help text.
- [x] Update the docs to call out the first-install limitation explicitly.
- [x] Run targeted verification and record the review.

### Review

- Confirmed the reported `--dry-run` output was expected in a no-Nix environment: `command -v nix` returns nothing in this workspace, and neither `/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh` nor `$HOME/.nix-profile/etc/profile.d/nix.sh` exists, so there is no evaluator available for a preview build.
- Updated `bootstrap.sh` so the `--dry-run` failure message is explicit about the limitation and gives the two valid next steps: run a normal bootstrap once or install Nix manually first.
- Updated the usage/help text plus `README.md` and `docs/nix/README.md` so the first-install limitation is documented alongside the preview examples instead of being implicit.
- Recorded the correction in `tasks/lessons.md` so future preview-mode changes call out required installed prerequisites up front.
- Verification completed locally: `bash -n bootstrap.sh`, `./bootstrap.sh personal --dry-run`, `git diff --check -- bootstrap.sh README.md docs/nix/README.md tasks/todo.md tasks/lessons.md`, and a targeted `git diff` review all passed.

## Follow-up: install-dependencies bootstrap command

### Goal

Add `./bootstrap.sh install-dependencies` as the explicit first-install path for prerequisites, and point missing-Nix preview/diff users to that command.

### Success criteria

- `bootstrap.sh install-dependencies` installs the bootstrap prerequisites without applying a role.
- `bootstrap.sh personal --dry-run` and `--diff` point to `install-dependencies` when Nix is missing.
- The usage text and docs document the new command and the first-install flow clearly.
- The correction is captured in `tasks/lessons.md`.
- Available static verification is run and the review is recorded.

### Assumptions / constraints

- `install-dependencies` remains Darwin-only, like the rest of the bootstrap wrapper.
- The subcommand installs both Nix and Homebrew, since both are bootstrap prerequisites on macOS.
- The existing direct role-apply path remains supported.

### Steps

- [x] Update the bootstrap CLI shape to support `install-dependencies`.
- [x] Route missing-Nix preview/diff flows to the new command in messaging.
- [x] Update docs, record the lesson, and run targeted verification.

### Review

- Updated `bootstrap.sh` to support two explicit entrypoints: `./bootstrap.sh install-dependencies` for prerequisite installation, and `./bootstrap.sh <personal|work> [--dry-run] [--diff]` for preview/apply.
- `install-dependencies` installs Nix and Homebrew on Darwin without applying a role. It rejects preview flags so the command surface stays unambiguous.
- Missing-Nix preview paths now point users to `./bootstrap.sh install-dependencies` instead of manual-only guidance. The rerun hint now preserves the actual requested preview flags correctly for both `--dry-run` and `--diff`.
- Updated `README.md` and `docs/nix/README.md` so the first-install flow is explicit: run `install-dependencies`, then preview or apply the chosen role.
- Recorded the correction in `tasks/lessons.md` so future bootstrap UX changes prefer a repo-supported prerequisite command over manual-only instructions when the workflow needs one.
- Verification completed locally: `bash -n bootstrap.sh`, `./bootstrap.sh --help`, `./bootstrap.sh personal --dry-run`, `./bootstrap.sh personal --diff`, `./bootstrap.sh install-dependencies --diff`, and `git diff --check -- bootstrap.sh README.md docs/nix/README.md tasks/todo.md tasks/lessons.md` all passed.

## Follow-up: Live dry-run evaluation failure

### Goal

Fix the current `./bootstrap.sh personal --dry-run` evaluation failure against the installed Nix toolchain and keep iterating until the preview path succeeds.

### Success criteria

- The current bootstrap dry-run failure is reproduced locally with the installed Nix toolchain.
- The pinned `nix-darwin` / Home Manager module interfaces are inspected directly and the repo is updated to use supported options.
- Follow-on evaluation failures, if any, are addressed in the same loop.
- `./bootstrap.sh personal --dry-run` completes successfully.
- The review is recorded with the actual runtime verification that passed.

### Assumptions / constraints

- The local machine now has enough Nix installed to evaluate the flake.
- `flake.lock` may now be generated as part of the real evaluation path and should be treated as part of the repo state.
- Fixes should stay aligned to the pinned inputs rather than guessing against older examples.

### Steps

- [x] Reproduce the current dry-run failure with trace output and inspect the pinned module sources.
- [x] Patch the repo to use supported module options and fix any additional runtime evaluation errors.
- [x] Re-run bootstrap dry-run until it succeeds, then record the review.

### Review

- Reproduced the live failure from `./bootstrap.sh personal --dry-run` and confirmed the first break was a pinned `nix-darwin` interface mismatch: `homebrew.enableZshIntegration` is not a valid option in the pinned `nix-darwin` revision from `flake.lock`.
- Removed that unsupported option from `modules/platforms/darwin/homebrew.nix` and moved the required Homebrew shell initialization into `modules/shared/shell.nix`, guarded for Darwin and sourced from the standard `/opt/homebrew` or `/usr/local` locations.
- Re-ran the dry-run and followed the next real failure to the Rust helper build graph. `atlas-cli` was resolving `time` `0.3.47`, which requires `rustc 1.88.0`, while the pinned Nix toolchain in the current build path provides `rustc 1.86.0`.
- Fixed the Atlas helper without widening the repo toolchain surface: removed the `time` dependency from `home/.codex/skills/atlas/scripts/Cargo.toml`, trimmed the lockfile, and rewrote the small date-boundary helpers in `home/.codex/skills/atlas/scripts/src/main.rs` to use macOS `/bin/date` at runtime instead of the `time` crate. Atlas is Darwin-only, so that runtime dependency matches the target platform.
- Runtime verification now passes locally with the installed Nix toolchain: `./bootstrap.sh personal --dry-run` completes successfully and builds the Darwin closure, and `./bootstrap.sh personal --dry-run --diff` also succeeds, skipping the diff cleanly when `/run/current-system` is not present yet.
- Targeted sanity checks also passed: `git diff --check -- modules/platforms/darwin/homebrew.nix modules/shared/shell.nix home/.codex/skills/atlas/scripts/Cargo.toml home/.codex/skills/atlas/scripts/Cargo.lock home/.codex/skills/atlas/scripts/src/main.rs`.

## Follow-up: First-run diff UX

### Goal

Make the `--diff` no-baseline case explicit so first-run nix-darwin machines explain why there is nothing to compare against and what the user should run next.

### Success criteria

- `bootstrap.sh --diff` explains that `/run/current-system` is missing because there is no active nix-darwin generation yet.
- The message distinguishes between dry-run preview and a real apply.
- The next command is explicit in the output.
- The correction is recorded in `tasks/lessons.md`.

### Steps

- [x] Update the bootstrap diff message for the missing-baseline case.
- [x] Record the correction in `tasks/lessons.md`.
- [x] Re-run the diff path and record the review.

### Review

- Updated `bootstrap.sh` so the missing `/run/current-system` case is no longer logged as a generic skip. The script now explains that there is no active nix-darwin generation yet, which is why `nix store diff-closures` has no baseline.
- The message is now context-sensitive: in `--dry-run` it tells the user to run `./bootstrap.sh <role>` once and then rerun `--dry-run --diff`; in a real apply with `--diff`, it explains that bootstrap will continue without a diff and that future diff runs will work after the activation completes.
- Recorded the UX correction in `tasks/lessons.md` so future preview/diff work calls out missing active generations explicitly instead of falling back to a vague skip message.
- Verification completed locally: `bash -n bootstrap.sh`, `git diff --check -- bootstrap.sh tasks/todo.md tasks/lessons.md`, and `./bootstrap.sh personal --dry-run --diff` all passed, and the runtime output now prints the first-run explanation plus the exact next command instead of a generic “Skipping diff.”

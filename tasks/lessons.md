# Lessons

## 2026-03-18

- Mistake: I initially optimized the Rust toolchain plan around Homebrew-managed `rust` instead of the user's preferred rustup installer flow.
- Why it happened: I anchored on the existing bootstrap/Brewfile pattern before locking the user's toolchain preference.
- Prevention rule: When a plan involves installing a language toolchain, confirm whether the user wants the ecosystem-default installer or the repo's package manager before finalizing the bootstrap approach.
- Mistake: I updated the Codex skill tree and initially closed the work without checking whether the mirrored Claude skills needed the same upgrades.
- Why it happened: I scoped the migration around `dot_codex/skills` and failed to check for parallel skill trees before declaring the task complete.
- Prevention rule: When a repo contains mirrored skill directories such as `dot_codex/skills` and `dot_claude/skills`, search and update both trees before closing any shared skill change.

## 2026-03-19

- Mistake: I added `gh-address-comments` review-thread reply and resolve helpers but missed the separate top-level PR `create-comment` helper the user also needed.
- Why it happened: I scoped the follow-up too narrowly around review-thread mutations and did not enumerate every comment-creation path before marking the helper package complete.
- Prevention rule: When adding comment-mutation tooling, explicitly inventory all target comment types first (top-level PR comments, thread replies, resolutions) and apply any formatting rules, such as robot prefixes, across every creation path.
- Mistake: I initially solved the installed-binary problem only for `sql-read` instead of inventorying every Rust-backed skill helper that used the same `cargo run` pattern.
- Why it happened: I optimized for the immediate failing helper and did not broaden the audit to the shared packaging pattern across mirrored skill trees.
- Prevention rule: When a bootstrap or packaging fix applies to one Rust-backed skill helper, inventory every `scripts/Cargo.toml` under `dot_codex/skills` and `dot_claude/skills` before closing the change, then install and document the whole set consistently.

## 2026-03-24

- Mistake: I added `bootstrap.sh --dry-run` without making the first-install limitation explicit, so the preview path looked broken when Nix was not installed yet.
- Why it happened: I focused on preserving dry-run purity and did not surface the prerequisite clearly enough in the script output and docs.
- Prevention rule: When adding a preview or dry-run path that depends on an already-installed toolchain, explicitly document and print the prerequisite and the valid next steps in the initial implementation.
- Mistake: I initially fixed the missing-Nix preview UX with manual guidance only instead of routing users to a repo-supported prerequisite command.
- Why it happened: I treated the problem as messaging-only and did not step back to add the explicit dependency-install path the workflow needed.
- Prevention rule: When a bootstrap flow has prerequisite tooling, prefer a first-class repo command for installing those dependencies and point failure paths to that command rather than only to manual setup.
- Mistake: I initially treated a missing `/run/current-system` during `--diff` as a generic skip instead of explaining that first-run nix-darwin machines have no active baseline generation yet.
- Why it happened: I focused on making the diff path non-fatal and did not tailor the message to the machine state or tell the user what action would create the missing baseline.
- Prevention rule: When a preview or diff path depends on an existing active generation, detect the first-run state explicitly and print the reason, the immediate consequence, and the exact next command to make future previews meaningful.
- Mistake: I started patching a separate chezmoi-style worktree before confirming which repo actually drove the live Ghostty config.
- Why it happened: I assumed the current workspace was the deployment source of truth instead of checking the Nix module wiring first.
- Prevention rule: When a user says a config is Nix-managed, locate the live Nix module and sourced file before editing or applying any parallel dotfiles repo.

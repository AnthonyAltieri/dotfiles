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

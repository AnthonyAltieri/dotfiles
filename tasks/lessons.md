# Lessons

## 2026-03-18

- Mistake: I initially optimized the Rust toolchain plan around Homebrew-managed `rust` instead of the user's preferred rustup installer flow.
- Why it happened: I anchored on the existing bootstrap/Brewfile pattern before locking the user's toolchain preference.
- Prevention rule: When a plan involves installing a language toolchain, confirm whether the user wants the ecosystem-default installer or the repo's package manager before finalizing the bootstrap approach.
- Mistake: I updated the Codex skill tree and initially closed the work without checking whether the mirrored Claude skills needed the same upgrades.
- Why it happened: I scoped the migration around `dot_codex/skills` and failed to check for parallel skill trees before declaring the task complete.
- Prevention rule: When a repo contains mirrored skill directories such as `dot_codex/skills` and `dot_claude/skills`, search and update both trees before closing any shared skill change.

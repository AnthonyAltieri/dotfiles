# Branch And PR

## Goal

Create a feature branch from `origin/main`, commit the current Rust skill-helper and Claude sync work, and open a GitHub PR with a structured description.

## Success criteria

- A new `codex/*` branch exists and is based on the latest `origin/main`.
- The relevant changes are committed with a clear message.
- The branch is pushed to `origin`.
- A GitHub PR is created with a concise, structured body.

## Assumptions / constraints

- The current dirty worktree is the intended change set for the PR.
- Branch creation must follow repo policy: fetch `origin/main`, then create the branch from that ref.
- Final verification should use the existing skill-helper test suite before commit.

## Steps

- [x] Fetch `origin/main` and create a new `codex/*` branch from it.
- [x] Review the pending diff and run final verification.
- [x] Commit the intended files with a clear message.
- [x] Push the branch and open the PR.

## Risks / edge cases

- The dirty worktree may contain changes that do not belong in the PR.
- Branch creation from `origin/main` can fail if the current worktree conflicts with the target base.
- PR creation depends on `gh` auth and push access being available.

## Verification plan

- Confirm the branch points to `origin/main` plus the intended working-tree changes.
- Run `bash scripts/test-skill-helpers.sh` before commit.
- Review `git status` after staging to ensure only intended files are included.

## Review

- Created `codex/rust-skill-helpers` from the latest `origin/main` after `git fetch origin --prune`.
- Committed the staged change set as `feat: add rust-based skill helper tooling` (`ce0c73e`).
- Pushed the branch to `origin/codex/rust-skill-helpers`.
- Opened GitHub PR #13: `feat: add rust-based skill helper tooling`.
- Verification:
  - `bash scripts/test-skill-helpers.sh`
  - `git diff --cached --stat`
  - `git push -u origin codex/rust-skill-helpers`

# Skill Helper Test Suite

## Goal

Add a repeatable test suite for the Rust-based skill helper scripts so behavior can be verified without relying on manual smoke tests.

## Success criteria

- Deterministic helper logic has automated Rust tests.
- There is one top-level command/script to run the skill-helper test suite.
- The suite covers both the Codex and Claude helper trees where scripts are mirrored.
- Verification results are recorded here.

## Assumptions / constraints

- Keep tests local and offline; do not depend on live `gh`, network access, or Atlas automation permissions.
- Prefer unit tests around parsing/classification/rendering logic over brittle end-to-end mocking.
- Preserve existing CLI behavior while refactoring only enough to expose pure logic for tests.

## Steps

- [x] Identify the pure helper logic that should be covered by tests.
- [x] Add Rust unit tests to the helper scripts and supporting functions.
- [x] Add a top-level runner for the skill-helper test suite.
- [x] Run the focused test suite and record the review summary.

## Risks / edge cases

- Some helpers are duplicated across `dot_codex/skills` and `dot_claude/skills`, so tests need to stay aligned across both trees.
- Atlas helpers depend on macOS-only tooling, so coverage needs to stay focused on deterministic parsing/query logic.
- Cargo test may still need the Rust dependency cache to exist locally.

## Verification plan

- Run the new top-level test suite command.
- Confirm the targeted Cargo packages report non-zero real test counts instead of build-only success.
- Review the diff for mirrored Codex/Claude test coverage where appropriate.

## Review

- Added inline Rust unit tests for deterministic helper logic in the Codex source-of-truth scripts:
  - `dot_codex/skills/atlas/scripts/src/main.rs`
  - `dot_codex/skills/atlas/scripts/src/atlas_common.rs`
  - `dot_codex/skills/gh-address-comments/scripts/src/bin/fetch_comments.rs`
  - `dot_codex/skills/gh-address-comments/scripts/src/bin/summarize_threads.rs`
  - `dot_codex/skills/gh-fix-ci/scripts/src/bin/classify_ci_log.rs`
  - `dot_codex/skills/gh-fix-ci/scripts/src/bin/inspect_pr_checks.rs`
  - `dot_codex/skills/gh-manage-pr/scripts/summarize_diff.rs`
- Mirrored the tested helper source files into the Claude skill tree so the duplicated scripts share the same test coverage and behavior checks.
- Added a one-command runner at `scripts/test-skill-helpers.sh` that executes the full offline suite across Codex and Claude helpers.
- Coverage focus:
  - Atlas: CLI arg parsing, SQL/query generation, bookmark collection, escaping, local copy, and permission hints.
  - GitHub comment helpers: arg parsing, compact rendering, sanitization, TSV summarization, and unresolved/blocking grouping.
  - GitHub CI helpers: log classification, failure snippet extraction, field parsing, and run/job id extraction.
  - PR summarizer: diffstat grouping, insertion/deletion parsing, and empty-input handling.
- Verification:
  - `bash scripts/test-skill-helpers.sh`
  - The suite reported real test execution, not build-only success:
    - Codex Atlas: 6 tests
    - Codex gh-address-comments: 6 tests
    - Codex gh-fix-ci: 9 tests
    - Codex gh-manage-pr: 3 tests
    - Claude gh-address-comments: 6 tests
    - Claude gh-fix-ci: 9 tests
    - Claude gh-manage-pr: 3 tests

# Claude Skill Sync

## Goal

Mirror the recent Rust helper, asset, and documentation upgrades into the matching `dot_claude/skills` tree so the Claude skills stay in lockstep with the Codex skills.

## Success criteria

- Claude-side `gh-manage-pr`, `gh-fix-ci`, and `gh-address-comments` include the same Rust helper coverage as the Codex skills.
- Claude-side `frontend-design` includes the same anti-generic reference guidance added on the Codex side.
- Updated Claude skill docs point at the bundled helpers/resources instead of older markdown-only workflows.
- Claude-side Rust helpers build and smoke-test successfully.
- Verification and review notes are recorded here.

## Assumptions / constraints

- Preserve Claude-specific reply wording and guidance where it already differs intentionally from the Codex copy.
- Use the installed Claude skill path (`$HOME/.claude/skills/...`) in command examples.
- Scope is limited to the mirrored skills already present under `dot_claude/skills`.

## Steps

- [x] Add the missing Claude-side helper files, assets, and references.
- [x] Update the affected Claude `SKILL.md` files to document the new helper workflows.
- [x] Compile and smoke-test the Claude-side Rust helpers.
- [x] Add a review summary.

## Risks / edge cases

- The Claude skills are not byte-for-byte copies of the Codex skills, so some wording needs to stay Claude-specific.
- Helper examples need to use a Claude-appropriate install path without introducing broken path assumptions.
- The new Cargo packages rely on crates.io during the first build.

## Verification plan

- Build the Claude-side Cargo packages with `cargo build --release`.
- Run `--help` or fixture-based smoke tests for the new helper binaries.
- Search `dot_claude/skills` for stale Python references after the sync.
- Review the diff to ensure the added resources match the intended Codex-side functionality.

# Python-to-Rust Skill Script Migration

## Goal

Convert all remaining Python scripts under `dot_codex/skills` into Rust-based scripts and update the affected skills to use the new Rust entrypoints.

## Success criteria

- No `.py` files remain under `dot_codex/skills`.
- Atlas, GitHub comments, and GitHub CI scripts all have Rust replacements with equivalent CLI entrypoints.
- Affected `SKILL.md` files no longer reference Python or `.py` files.
- New Rust packages compile successfully.
- Verification and review notes are recorded here.

## Assumptions / constraints

- Scope is limited to repo-managed skills under `dot_codex/skills`, not preinstalled `.system` skills outside this repo.
- Cargo packages are acceptable where JSON or SQLite support makes std-only Rust impractical.
- Existing skill behavior should remain recognizable even if the implementation path changes.

## Steps

- [x] Replace the remaining Python scripts with Rust implementations.
- [x] Update skill documentation and command examples to use Rust/Cargo.
- [x] Remove Python file references from the repo-managed skills.
- [x] Compile the new Rust packages and run focused smoke tests.
- [x] Add a review summary.

## Risks / edge cases

- Atlas history and bookmarks rely on JSON parsing and SQLite access, which are more complex in Rust than in Python.
- Cargo builds will create `target/` directories unless ignored.
- GitHub helper behavior depends on `gh` output shapes, so CLI compatibility needs smoke testing.

## Verification plan

- Search for `.py` files under `dot_codex/skills` after the migration.
- Compile each new Rust package with `cargo build --release`.
- Run `--help` or fixture-based smoke tests for each migrated script.
- Review the final diff for stale Python references.

## Review

- Migrated all repo-managed Python scripts under `dot_codex/skills` to Rust:
  - `atlas/scripts/atlas_cli.py` + `atlas/scripts/atlas_common.py` -> Cargo package with `src/main.rs` and `src/atlas_common.rs`
  - `gh-address-comments/scripts/fetch_comments.py` -> Cargo bin `fetch-comments`
  - `gh-fix-ci/scripts/inspect_pr_checks.py` -> Cargo bin `inspect-pr-checks`
- Consolidated the new Rust helpers into Cargo packages so JSON and SQLite support can be handled natively in Rust without keeping Python wrappers.
- Updated skill docs to use Cargo-based commands and removed stale Python references.
- Added `.gitignore` entries for `.DS_Store` and Cargo `target/` directories.
- Verification:
  - `find dot_codex/skills -type f -name '*.py'` returned no results.
  - `cargo build --release --manifest-path dot_codex/skills/atlas/scripts/Cargo.toml`
  - `cargo build --release --manifest-path dot_codex/skills/gh-address-comments/scripts/Cargo.toml`
  - `cargo build --release --manifest-path dot_codex/skills/gh-fix-ci/scripts/Cargo.toml`
  - `dot_codex/skills/atlas/scripts/target/release/atlas-cli --help`
  - `dot_codex/skills/gh-address-comments/scripts/target/release/fetch-comments --help`
  - `dot_codex/skills/gh-address-comments/scripts/target/release/summarize-threads /tmp/pr-threads.tsv`
  - `dot_codex/skills/gh-fix-ci/scripts/target/release/inspect-pr-checks --help`
  - `dot_codex/skills/gh-fix-ci/scripts/target/release/classify-ci-log /tmp/failed.log`
- Remaining note: the worktree still contains earlier uncommitted changes from the previous Rust rollout (`gh-manage-pr`, `frontend-design`, rustup bootstrap, and task files). They were preserved and not reverted.

## Claude Skill Sync Review

- Mirrored the recent helper-backed skill upgrades into `dot_claude/skills`:
  - `gh-manage-pr` now includes `scripts/summarize_diff.rs`, `assets/pr-body-template.md`, and a helper-first workflow in `SKILL.md`.
  - `gh-fix-ci` now includes a Cargo package with `inspect-pr-checks` and `classify-ci-log`, plus updated bundled-resource guidance in `SKILL.md`.
  - `gh-address-comments` now includes a Cargo package with `fetch-comments` and `summarize-threads`, while preserving the Claude-specific reply conventions and thread-action output section.
  - `frontend-design` now includes `references/design-gotchas.md` and matching quick-start/gotcha/reference guidance.
- Verification:
  - `find dot_claude/skills -type f | sort`
  - `rg -n '\.py|python|uv run --python|Python helper' dot_claude/skills`
  - `"$HOME/.cargo/bin/cargo" build --release --manifest-path dot_claude/skills/gh-address-comments/scripts/Cargo.toml`
  - `"$HOME/.cargo/bin/cargo" build --release --manifest-path dot_claude/skills/gh-fix-ci/scripts/Cargo.toml`
  - `rustc dot_claude/skills/gh-manage-pr/scripts/summarize_diff.rs -O -o /tmp/claude-gh-manage-pr-summarize`
  - `dot_claude/skills/gh-address-comments/scripts/target/release/fetch-comments --help`
  - `printf 'thread_id\tpath\tis_resolved\tis_outdated\tline\treviewer\treview_state\tcomment_count\tpreview\n1\tsrc/app.ts\tfalse\tfalse\t42\talice\tCHANGES_REQUESTED\t2\tNeeds a null check\n' | dot_claude/skills/gh-address-comments/scripts/target/release/summarize-threads`
  - `dot_claude/skills/gh-fix-ci/scripts/target/release/inspect-pr-checks --help`
  - `printf 'Compiling app\nerror[E0425]: cannot find value \`x\` in this scope\nBuild failed\n' | dot_claude/skills/gh-fix-ci/scripts/target/release/classify-ci-log`
  - `printf ' src/lib.rs | 4 ++--\n README.md | 2 +-\n 2 files changed, 3 insertions(+), 3 deletions(-)\n' | /tmp/claude-gh-manage-pr-summarize`
- Note: the first Claude-side Cargo builds required network-enabled escalation because the sandbox could not resolve `index.crates.io`.

# Rust Helper Test Strategy Review

## Goal

Inspect the Rust helper scripts under `dot_codex/skills` and `dot_claude/skills` and recommend the most pragmatic automated test strategy across unit tests, Cargo integration tests, and any top-level shell harness usage.

## Success criteria

- Enumerate the Rust helper crates and standalone Rust scripts currently in scope.
- Identify which files/modules contain pure parsing or formatting logic versus CLI and process orchestration.
- Recommend a primary test approach with concrete tradeoffs.
- Call out the exact files or modules that should receive coverage first.
- Record review and verification notes here.

## Assumptions / constraints

- This task is analysis-only; no production Rust code changes are required.
- The Codex and Claude skill trees are mirrored in several places, so duplicated helpers should not be tested independently unless behavior diverges.
- Recommendations should optimize for low maintenance in a dotfiles/skills repo rather than maximal Rust testing sophistication.

## Steps

- [x] Inventory the Rust helper entrypoints and shared modules in both skill trees.
- [x] Inspect where the meaningful logic lives and separate pure transforms from CLI or subprocess glue.
- [x] Compare unit-test, Cargo integration-test, and shell-harness options against the current code shape.
- [x] Write a concise recommendation with tradeoffs and concrete coverage targets.
- [x] Add a review summary.

## Risks / edge cases

- Some helpers are duplicated byte-for-byte across `dot_codex` and `dot_claude`, which can hide whether coverage should live once or twice.
- Several binaries call external tools (`gh`, `git`, `osascript`, `sqlite3`), so recommendations need to distinguish deterministic local logic from environment-dependent behavior.
- A few helpers are standalone `.rs` files compiled with `rustc`, not Cargo crates, which changes the practical test options.

## Verification plan

- Read each relevant Rust file and Cargo manifest under the two skill trees.
- Diff mirrored helper files where needed to confirm whether coverage can be shared conceptually.
- Summarize the recommendation against the actual file/module layout rather than generic Rust testing advice.

## Review

- Inventory:
  - Cargo crates: `dot_codex/skills/gh-fix-ci/scripts`, `dot_codex/skills/gh-address-comments/scripts`, `dot_codex/skills/atlas/scripts`, plus mirrored Cargo crates under `dot_claude/skills/gh-fix-ci/scripts` and `dot_claude/skills/gh-address-comments/scripts`.
  - Standalone Rust scripts compiled with `rustc`: `dot_codex/skills/gh-manage-pr/scripts/summarize_diff.rs` and `dot_claude/skills/gh-manage-pr/scripts/summarize_diff.rs`.
- Mirror check:
  - Identical source pairs: `classify_ci_log.rs`, `summarize_threads.rs`, and both `summarize_diff.rs` files.
  - `inspect_pr_checks.rs` and `fetch_comments.rs` differ only in formatting, not behavior.
- Recommendation:
  - Use inline Rust unit tests as the primary strategy for the pure parsing and rendering helpers already embedded in the binaries.
  - Keep a very small shell-based smoke layer only for CLI invocation and environment-sensitive helpers.
  - Do not invest in Cargo integration tests as the default path unless the crates are first refactored to expose `src/lib.rs` modules.
- Why:
  - Most meaningful logic is pure and local: `inspect_pr_checks.rs` has parser/snippet helpers, `classify_ci_log.rs` is a pure classifier, `fetch_comments.rs` has pure compact-rendering helpers, `summarize_threads.rs` and `summarize_diff.rs` are pure fixture transforms, and Atlas contains several pure query/bookmark/time helpers.
  - The hard parts of the binaries are subprocess and environment boundaries (`gh`, `git`, `sqlite3`, `osascript`), which are awkward to cover well with Cargo integration tests in the current binary-only layout.
  - A top-level shell harness would be useful for smoke checks, but using it as the main test layer would be brittle, slower, and duplicative across the mirrored Codex/Claude trees.
- First coverage targets:
  - `dot_codex/skills/gh-fix-ci/scripts/src/bin/classify_ci_log.rs`
  - `dot_codex/skills/gh-fix-ci/scripts/src/bin/inspect_pr_checks.rs`
  - `dot_codex/skills/gh-address-comments/scripts/src/bin/summarize_threads.rs`
  - `dot_codex/skills/gh-address-comments/scripts/src/bin/fetch_comments.rs`
  - `dot_codex/skills/gh-manage-pr/scripts/summarize_diff.rs`
  - `dot_codex/skills/atlas/scripts/src/main.rs`
  - `dot_codex/skills/atlas/scripts/src/atlas_common.rs`
  - Claude-side duplicates only need smoke or compile parity unless behavior intentionally diverges later.
- Verification:
  - `rg --files dot_codex/skills dot_claude/skills`
  - `sed -n` review of the relevant `Cargo.toml`, `SKILL.md`, and Rust source files
  - `shasum` comparison across mirrored Rust helpers
  - `diff -u` on the non-identical mirrored files to confirm formatting-only differences
  - `find dot_codex/skills dot_claude/skills -path '*/tests' -type d` returned no test directories

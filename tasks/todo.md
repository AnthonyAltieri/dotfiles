# Rust Helper Conventions Audit

# Programming Skill Review

## Goal

Review `dot_codex/skills/programming` and `dot_codex/AGENTS.md` for low-signal guidance, including redundant, weak, or bloated lines that should be trimmed, and identify any missing high-impact principle from the user's requested list.

## Success criteria

- The programming skill files are inspected with concrete file and line references.
- `dot_codex/AGENTS.md` is checked for overlap or contradiction with the skill guidance.
- The review clearly distinguishes redundant, weak, and bloated guidance.
- Any missing high-impact principle from the requested list is called out explicitly.
- Review notes are recorded here.

## Assumptions / constraints

- Scope is limited to review only; no skill or agent files will be edited.
- Task-log updates in `tasks/todo.md` are allowed for process tracking.
- The user wants concise, high-signal recommendations rather than a rewrite.

## Steps

- [x] Read `dot_codex/AGENTS.md` and all files under `dot_codex/skills/programming`.
- [x] Compare the programming skill guidance against the requested principle list and against existing agent-level guidance.
- [x] Produce a concise findings-first review with exact trim targets and one missing-principle assessment.
- [x] Record review notes here.

## Risks / edge cases

- Some lines may be intentionally repetitive across agent and skill layers, so suggestions need to distinguish useful reinforcement from actual bloat.
- The "requested list" is inferred from the repo-level AGENTS guidance provided in the prompt, so any missing-principle callout must stay anchored to that source.

## Verification plan

- Cross-check every target file in `dot_codex/skills/programming`.
- Verify cited lines against the current file contents before finalizing the review.
- Confirm whether each suggested trim is redundant with nearby text or with `dot_codex/AGENTS.md`.

## Review

- Highest-value trim is duplicated programming-default text across `dot_codex/AGENTS.md`, `dot_codex/skills/programming/SKILL.md`, and `dot_codex/skills/programming/agents/openai.yaml`; one pointer plus one compact definition is enough.
- The weakest lines are slogan-style statements that restate nearby rules without adding actionability, especially in `SKILL.md` Observability, Tests, and Review Pass.
- The TypeScript reference includes one repo-style-specific default (`lowercase kebab-case` filenames) that is too opinionated for a cross-repo programming skill and likely to conflict with framework conventions.
- The TypeScript example is longer than necessary for a guidance file because it only re-demonstrates bullets already stated above it.
- The main missing high-impact principle in the programming skill package is evidence-first debugging: the skill says to use it for debugging, but it does not carry over the AGENTS requirement to start from logs/errors/failing tests, reproduce first, and verify the fix against the failing case.

## Goal

Inspect the existing Rust helper crates under `dot_codex/skills` and `dot_claude/skills` and extract the conventions that a new `sql-read` crate should follow.

## Success criteria

- The existing helper crates are inventoried.
- Repeated `Cargo.toml` patterns are identified.
- Repeated test-layout patterns are identified.
- Repeated helper CLI patterns are identified.
- Concrete file examples are captured for the final notes.

## Assumptions / constraints

- Scope is limited to actual Cargo crates under the mirrored skill trees.
- Mirrored Claude crates may confirm conventions but should not be treated as independent patterns when they are direct copies.
- The output is a concise implementation guide, not a design proposal for `sql-read`.

## Steps

- [x] Inventory the existing Rust helper crates in both skill trees.
- [x] Inspect manifest, source, and test patterns in representative files.
- [x] Summarize actionable conventions for `sql-read` with file examples.
- [x] Record review notes here.

## Risks / edge cases

- Some Rust helpers in the repo are standalone `.rs` scripts rather than Cargo crates, so they should not drive crate-structure guidance.
- Atlas is a single-binary crate while GitHub helpers are multi-bin crates, so `sql-read` needs the right pattern chosen deliberately.

## Verification plan

- Cross-check every `Cargo.toml` found under `dot_codex/skills` and `dot_claude/skills`.
- Confirm test placement by locating `#[cfg(test)]` usage in the helper sources.
- Confirm CLI conventions by checking argument parsing, `--help`, exit codes, and stdout/stderr behavior in representative binaries.

## Review

- Found three actual helper crates under the skill trees:
  - `dot_codex/skills/atlas/scripts`
  - `dot_codex/skills/gh-address-comments/scripts` mirrored in `dot_claude/skills/gh-address-comments/scripts`
  - `dot_codex/skills/gh-fix-ci/scripts` mirrored in `dot_claude/skills/gh-fix-ci/scripts`
- Manifest convention is intentionally small: package metadata, minimal dependencies, and explicit `[[bin]]` entries only when a crate exposes multiple executables.
- Test convention is inline unit tests in the same source file via `#[cfg(test)]`; there are no `tests/` directories under either skill tree.
- CLI convention is a thin `main()` wrapper around a `run()` function, manual argument parsing, `--help` usage text on stdout, errors on stderr, and deterministic machine-friendly stdout output.
- Shared verification currently uses `cargo test --offline --manifest-path ...` in `scripts/test-skill-helpers.sh`, so new helper crates should keep a committed lockfile and avoid requiring network access during normal test runs.

# GH Address Comments Mutation Helpers

## Goal

Add Rust helpers to `gh-address-comments` for posting PR comments, posting review-thread replies, and resolving review threads, with robot-emoji prefixing on every comment-creation path.

## Success criteria

- The Codex `gh-address-comments` Rust crate exposes helpers to create PR comments, create review-thread replies, and resolve review threads.
- Every comment-creation helper automatically prefixes the submitted body with a robot emoji without double-prefixing already-prefixed input.
- The Claude `gh-address-comments` tree mirrors the same helper scripts and documentation updates.
- The existing offline Cargo tests and shared helper suite cover the new functionality.
- Verification and review notes are recorded here.

## Assumptions / constraints

- Scope is limited to GitHub pull requests: top-level PR comments plus review-thread replies/resolution.
- Live GitHub mutations should stay on `gh`; the Rust helpers should assemble and submit focused GraphQL mutations locally.
- Existing `fetch-comments` and `summarize-threads` behavior should remain intact.

## Steps

- [x] Add the new top-level comment helper plus the reply/resolve workflow to the Codex `gh-address-comments` crate and skill docs.
- [x] Add offline Rust tests for mutation payload construction, robot-prefix behavior, and argument parsing.
- [x] Mirror the helper and documentation changes into the Claude skill tree.
- [x] Run focused Cargo tests plus the shared helper suite and record the review summary.

## Risks / edge cases

- GitHub review-thread mutations use thread IDs, while top-level PR comments target the pull request subject ID, so the helpers must keep those identifiers explicit.
- Auto-prefixing should not duplicate the robot emoji when the caller already included it.
- The helper output must stay machine-friendly and should not leak raw GraphQL input bodies in error text unnecessarily.

## Verification plan

- Run `cargo test --offline --manifest-path dot_codex/skills/gh-address-comments/scripts/Cargo.toml`.
- Run `cargo test --offline --manifest-path dot_claude/skills/gh-address-comments/scripts/Cargo.toml`.
- Run `bash scripts/test-skill-helpers.sh`.

## Review

- Added a shared Rust helper library at `dot_codex/skills/gh-address-comments/scripts/src/lib.rs` and mirrored it to `dot_claude/skills/gh-address-comments/scripts/src/lib.rs`.
- The shared library now owns:
  - `gh` auth checks
  - GraphQL command execution helpers
  - robot-prefix enforcement via `ensure_robot_prefix`
- Added three comment-mutation Rust binaries in both trees:
  - `create-comment`
    - creates a top-level PR comment
    - targets the current branch PR by default and accepts `--pr` for an explicit PR target
    - accepts `--body`, `--body-file`, or stdin
    - automatically prefixes the final body with `🤖 `
  - `create-thread-reply`
    - creates a review-thread reply
    - accepts `--thread-id` plus either `--body`, `--body-file`, or stdin
    - automatically prefixes the final body with `🤖 `
  - `resolve-thread`
    - resolves a review thread by thread ID
    - emits compact JSON with the thread id and resolved state
- Refactored `fetch-comments` to reuse the shared `gh`/GraphQL helpers instead of keeping another local command-execution copy.
- Updated both `gh-address-comments` skill docs to use the new Rust helpers instead of raw GraphQL mutation examples.
- The workflow now documents that comment bodies should stay agent-specific (`FROM CODEX:` / `FROM CLAUDE:`), while the helpers add the robot emoji prefix.
- Verification:
  - `cargo fmt --manifest-path dot_codex/skills/gh-address-comments/scripts/Cargo.toml`
  - `cargo fmt --manifest-path dot_claude/skills/gh-address-comments/scripts/Cargo.toml`
  - `cargo test --offline --manifest-path dot_codex/skills/gh-address-comments/scripts/Cargo.toml`
  - `cargo test --offline --manifest-path dot_claude/skills/gh-address-comments/scripts/Cargo.toml`
  - `bash scripts/test-skill-helpers.sh`

# SQL Read Skill

## Goal

Add a mirrored `sql-read` skill with a Rust-backed `sql-read safe-ro` entrypoint for blanket-approvable read-only Postgres and SQLite access, plus a manual `sql-read query` path.

## Success criteria

- New `sql-read` skills exist under both `dot_codex/skills` and `dot_claude/skills`.
- The Rust crate exposes one binary `sql-read` with `safe-ro` and `query` subcommands.
- `safe-ro` enforces env-var-only targets and read-only execution.
- `query` supports env-var or raw targets but still enforces read-only execution.
- SQLite tests run locally and the shared test runner includes the new skill.
- Verification and review notes are recorded here.

## Assumptions / constraints

- v1 scope is Postgres and SQLite only.
- Postgres integration tests may need to be ignored unless a test DSN is available.
- The blanket-approved path is `sql-read safe-ro:*`, not `sql-read:*`.

## Steps

- [x] Add the Codex `sql-read` skill resources and Rust crate.
- [x] Add tests for parsing, query validation, output shaping, and SQLite execution.
- [x] Mirror the skill and crate into the Claude skill tree.
- [x] Update the shared helper test runner and record verification.

## Risks / edge cases

- New Rust dependencies may require a networked Cargo fetch the first time.
- Postgres value handling must avoid leaking DSNs while still returning stable JSON.
- SQL parsing must stay conservative and reject ambiguous statements.

## Verification plan

- Run Cargo tests for the new Codex and Claude `sql-read` crates.
- Run the shared `scripts/test-skill-helpers.sh` suite after updating it.
- Review the final diff for mirrored Codex/Claude behavior and safe-ro/query separation.

## Review

- Added a new mirrored `sql-read` skill under `dot_codex/skills/sql-read` and `dot_claude/skills/sql-read`.
- The skill stays lean and follows the documented best-practice shape:
  - `SKILL.md` for trigger rules, workflow, and gotchas
  - `references/postgres.md` and `references/sqlite.md` for engine-specific guidance
  - `assets/queries/` for reusable schema-inspection templates
  - a Rust crate in `scripts/` with one `sql-read` binary
- Implemented one binary with two subcommands:
  - `sql-read safe-ro` for the approval-friendly env-var-only path
  - `sql-read query` for manual env-var or raw-target exceptions
- Both paths enforce read-only behavior:
  - Postgres starts a read-only transaction and applies a statement timeout
  - SQLite opens the database in read-only mode and applies a busy timeout
- Added conservative SQL validation with `sqlparser`:
  - exactly one statement
  - only `Statement::Query` is allowed
  - multi-statement, DDL, DML, transaction control, `EXPLAIN`, and SQLite `PRAGMA` forms are rejected by staying query-only
- Output is stable and compact:
  - default `json`
  - optional `table` and `tsv`
  - raw DSNs and raw SQLite paths are redacted from errors and never echoed in the result payload
- Added inline Rust tests for:
  - subcommand and target-flag validation
  - env-var-only enforcement on `safe-ro`
  - raw-target support on `query`
  - SQL guard behavior
  - truncation/output shaping
  - SQLite read-only execution
  - an ignored Postgres integration test gated on `SQL_READ_TEST_POSTGRES_DSN`
- Updated `scripts/test-skill-helpers.sh` so the shared offline suite now covers both Codex and Claude `sql-read` crates.
- Verification:
  - `cargo test --manifest-path dot_codex/skills/sql-read/scripts/Cargo.toml`
  - `cargo test --offline --manifest-path dot_claude/skills/sql-read/scripts/Cargo.toml`
  - `cargo fmt --manifest-path dot_codex/skills/sql-read/scripts/Cargo.toml`
  - `cargo fmt --manifest-path dot_claude/skills/sql-read/scripts/Cargo.toml`
  - `bash scripts/test-skill-helpers.sh`
- Notes:
  - the first Codex-side Cargo test required a one-time crates.io fetch before the suite could run offline
  - Postgres runtime verification remains env-gated because no disposable DSN was configured in this repo

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

# Skill Convention Audit

## Goal

Inspect the existing skill folder conventions for mirrored Codex and Claude skills and summarize the current patterns for `SKILL.md`, references/assets usage, and agent metadata.

## Success criteria

- The mirrored skill directories under `dot_codex/skills` and `dot_claude/skills` are compared directly.
- The summary calls out the common `SKILL.md` structure with file examples.
- The summary notes how `references`, `assets`, `scripts`, and related folders are used today.
- The summary highlights concrete differences between Codex and Claude skill packaging, including agent metadata.

## Assumptions / constraints

- This is a documentation audit only; no repo behavior changes are needed.
- The output should stay concise and grounded in current on-disk examples.
- File examples should prefer mirrored skills where possible.

## Steps

- [x] Inspect representative mirrored skill folders and `SKILL.md` files.
- [x] Compare supporting folders such as `references`, `assets`, `scripts`, and `agents`.
- [x] Summarize the conventions and differences in a concise checklist.
- [x] Record a brief review note here.

## Risks / edge cases

- The mirrored trees are not exact copies, so a convention may apply only to a subset of skills.
- Some skills exist only in one tree, which can skew a naive folder-level comparison.
- Folder naming is not fully normalized (`reference` vs `references`), so examples need to be precise.

## Verification plan

- Read a representative set of mirrored `SKILL.md` files from both trees.
- List folder structures for both trees to confirm where supporting resources exist.
- Check for agent metadata files and note where they are present or absent.

## Review

- Mirrored skills with substantive content today are `frontend-design`, `gh-address-comments`, `gh-fix-ci`, and `gh-manage-pr`; `sql-read` exists as a populated Codex skill but only as an empty directory in the Claude tree.
- Shared `SKILL.md` convention is YAML frontmatter (`name`, `description`, optional `metadata.short-description`) followed by a task-oriented markdown body with `Quick start`, `Workflow`, and resource/gotcha sections.
- Shared resource usage is relative-path linking from `SKILL.md` into bundled helpers such as `references/design-gotchas.md`, `assets/pr-body-template.md`, and Rust helper crates under `scripts/`.
- Codex-specific packaging adds `agents/openai.yaml` interface metadata and, for some skills, icon assets and `LICENSE.txt`; Claude mirrored skills currently omit per-skill `agents/` metadata.
- Claude `SKILL.md` files are not byte-for-byte mirrors: they swap command paths to `$HOME/.claude/skills/...` and sometimes include extra Claude-specific workflow detail.

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

# Programming Skill Design

## Goal

Design a high-signal `programming` skill that codifies the user's type-safety, boundary-validation, simplicity, composition, observability, and testing principles in a form that is concise enough to trigger often without wasting context.

## Success criteria

- The final artifact set is decided before writing the skill.
- The skill name and trigger description are explicit enough to invoke on coding, refactoring, and bug-fix tasks without being so broad that they add noise.
- The core `SKILL.md` structure is defined, including which principles belong in the main file versus optional references.
- Type-system, boundary-validation, observability, testing, and readability rules are organized into a durable taxonomy rather than a flat principle dump.
- TypeScript-specific guidance is separated cleanly from language-agnostic guidance.
- The implementation plan accounts for the mirrored skill trees in this repo.
- A concrete validation plan exists for syntax, trigger quality, and instruction density.

## Assumptions / constraints

- The user's bullet list is the canonical source for the skill content; the linked X post is treated as optional inspiration and was not required to define the requested principles.
- Per the local `skill-creator` guidance, the main `SKILL.md` should stay lean; references should only exist if they materially reduce token cost or improve reuse.
- The likely deliverables are `dot_codex/skills/programming/SKILL.md`, `dot_codex/skills/programming/agents/openai.yaml`, and a mirrored `dot_claude/skills/programming/SKILL.md`; any references should be mirrored as well.
- v1 should avoid scripts or assets unless we find a repeated deterministic task that truly belongs outside the prompt text.
- "Most information dense" means high signal per line, not maximal length.

## Steps

- [x] Normalize the raw principles into a small set of sections with a clear precedence order.
- [x] Choose the skill trigger language and metadata so the skill is pulled in for substantive coding/refactoring tasks.
- [x] Define the `SKILL.md` outline, including a short "when to use" section and a compact set of non-negotiable rules.
- [x] Decide which language-specific guidance belongs inline versus in `references/`.
- [x] Decide whether to include tiny contrastive examples for boundaries, discriminated unions, observability, and tests.
- [x] Implement the skill in the Codex tree and mirror the relevant files into the Claude tree.
- [x] Validate the finished skill with `quick_validate.py` and a manual prompt-quality review.
- [x] Record final review notes here.

## Risks / edge cases

- A bloated skill will be less useful than a strict, compressed one, even if it contains more principles.
- If the trigger description is too generic, the skill may fire on low-value tasks and consume context unnecessarily.
- If the skill mixes timeless programming principles with repo-specific workflow rules, it will become harder to reuse and reason about.
- Too many examples can duplicate model priors instead of adding durable guidance.
- TypeScript-specific rules may dominate the skill unless they are isolated cleanly from the language-agnostic core.

## Verification plan

- Review the final skill against the local `skill-creator` rules: concise frontmatter, compact body, and progressive disclosure.
- Run `quick_validate.py` against the new skill directory.
- Manually inspect whether the trigger description would fire for the intended cases: coding, refactoring, debugging, and design-review tasks.
- Do a density pass after drafting: remove any line that does not change behavior or sharpen decision-making.
- Optionally use a subagent for an independent "would this skill improve a real coding task?" validation pass before closing.

## Review

- Added a new mirrored `programming` skill at `dot_codex/skills/programming` and `dot_claude/skills/programming`.
- Kept the core `SKILL.md` focused on decision order and defaults rather than turning it into a long manifesto:
  - validate boundaries first
  - encode invariants and future changes in types
  - prefer composition and readability over abstraction
  - keep observability high-signal
  - keep tests sparse but strict around critical behavior
- Moved language-specific guidance into progressive-disclosure references:
  - `references/typescript.md` for `zod`, string literals over enums, exhaustive matching, kebab-case filenames, and class avoidance
  - `references/python.md` for `pydantic`, tagged unions, `match`, and stateful-class guidance
- Generated `dot_codex/skills/programming/agents/openai.yaml` with the local skill tooling so the Codex skill has standard UI metadata and a default prompt.
- Added a short pointer in `dot_codex/AGENTS.md` so always-on instructions can invoke `$programming` without duplicating the philosophy text.
- Updated the root `README.md` Codex skill list so it reflects the actual managed skill set, including `frontend-design`, `sql-read`, and the new `programming` skill.
- Did not create a Claude-side `CLAUDE.md` because this repo does not currently manage one; the Claude-side implementation is the mirrored skill itself.
- Verification:
  - `uv run --with pyyaml /Users/anthonyaltieri/.codex/skills/.system/skill-creator/scripts/generate_openai_yaml.py dot_codex/skills/programming --interface short_description='Write simpler, safer application code' --interface default_prompt='Use $programming to design or refactor this code for validated boundaries, strong internal types, simple composition, deliberate observability, and minimal critical-path tests.'`
  - `uv run --with pyyaml /Users/anthonyaltieri/.codex/skills/.system/skill-creator/scripts/quick_validate.py dot_codex/skills/programming`
  - `uv run --with pyyaml /Users/anthonyaltieri/.codex/skills/.system/skill-creator/scripts/quick_validate.py dot_claude/skills/programming`
  - manual diff review of `README.md`, `dot_codex/AGENTS.md`, and the new mirrored skill files
- Notes:
  - The stock `python3` environment did not have `PyYAML`, so the local skill tooling was run through `uv`.
  - No repo-level markdown linter or pre-commit config was present at the workspace root for targeted linting of these docs files.

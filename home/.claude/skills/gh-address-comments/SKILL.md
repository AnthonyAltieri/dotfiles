---
name: gh-address-comments
description: Handle actionable GitHub pull request review feedback end-to-end by fetching unresolved threads, implementing and verifying fixes, replying on GitHub, and resolving handled threads by default. Use for requests to address, fix, or handle PR review comments; honor no-write, read-only, dry-run, draft-only, or equivalent requests by making no GitHub mutations.
metadata:
  short-description: Fix, reply to, and resolve PR feedback
---

# Github Handle Comments

Use the `gh` CLI to fetch PR comments for the current branch and address actionable feedback.

The active Nix profile puts the Rust helper commands on `PATH`, so call them directly.

If no PR exists for the current branch, report this and stop.

## Write mode

- Default to GitHub writes enabled. Reply to every successfully handled review thread, then resolve it.
- Treat `no write`, `no GitHub writes`, `do not post`, `do not reply or resolve`, `dry run`, `draft only`, or equivalent as no-GitHub-write mode. Local changes remain allowed when the user requested implementation.
- Treat `read-only` or an explicit request not to change local files as both no-GitHub-write mode and no-local-edit mode.
- In no-GitHub-write mode, return drafted replies and intended resolution states without posting or resolving anything.

## Inputs

- `repo`: repository path (default `.`)
- `pr`: PR number or URL (optional; defaults to current branch PR)
- optional flags:
  - `--all` / `--include-resolved`: include resolved threads
  - default behavior: unresolved threads only

## Quick start

1. Fetch and summarize review data with a direct helper pipeline when you need compact grouping first.
   - `fetch-comments --format compact | summarize-threads`
2. Fetch raw thread JSON directly when you need the full review payload.
   - `fetch-comments --format json`
3. Summarize unresolved threads before reading full comment bodies.
4. Post a top-level PR comment when you need to leave a general note outside a review thread.
   - `create-comment --body "FROM CLAUDE: Ready for another look."`
5. Post a thread reply with the bundled helper.
   - `create-thread-reply --thread-id "<thread_id>" --body "FROM CLAUDE: Addressed in <sha> - <description>"`
6. Resolve the thread after replying.
   - `resolve-thread --thread-id "<thread_id>"`

## Workflow

1. Gather PR context.
   - `gh pr view --json number,url,title,body,baseRefName,headRefName,reviews,state,statusCheckRollup`
   - `gh pr diff`
   - `gh pr checks`
2. Fetch comments and review threads.
   - Preferred: run `fetch-comments` for full conversation/review/thread data.
   - For large review sets, use `fetch-comments --format compact | summarize-threads` first so the model sees grouped metadata before opening individual threads.
   - Manual fallback via GraphQL:
     - `gh api graphql` query for `reviewThreads`, `reviews`, and thread comments.
3. Filter scope.
   - By default, process unresolved threads only.
   - Skip outdated threads unless still relevant.
   - Skip pure bot noise unless it points to real breakage.
4. Organize comments for efficient action.
   - Group by file, then thread, then reviewer.
   - Classify each item:
     - Blocking: typically from `CHANGES_REQUESTED`
     - Suggestion: improvement requests
     - Question: clarify rationale/intent
     - Nitpick: style/preferences
5. Process each file's unresolved threads.
   - Inspect file-specific diff context:
     - `git diff <baseRefName>...HEAD -- <filepath>`
   - Read the full thread before acting.
   - Triage false positives vs legitimate issues.
   - For legitimate issues, apply cohesive fixes file-by-file.
   - Check for similar issues in related code paths:
     - `git diff <baseRefName>...HEAD`
     - `git diff`
6. Commit strategy.
   - If the user asks for commits, make one commit per thread (or cohesive thread group).
   - Use conventional commit types (`fix`, `refactor`, `style`, `docs`, `test`).
   - Link commit body to the specific PR comment URL.
7. Reply and resolve threads.
   - For each successfully processed thread, reply and resolve by default using the thread `id` from step 2.
   - **Reply rules:**
     | Classification | Reply | Resolve? |
     |----------------|-------|----------|
     | False positive | `FROM CLAUDE: <explanation>` | Yes |
     | Addressed | `FROM CLAUDE: Addressed in <sha> — <description>` | Yes |
     | Question | `FROM CLAUDE: <answer or clarification request>` | Yes when answered conclusively; otherwise no |
   - **Reply helper:**
     ```bash
     create-thread-reply --thread-id "{thread_id}" --body "{reply_body}"
     ```
   - `create-thread-reply` automatically prefixes the final comment body with `🤖 `.
   - Use `create-comment` for top-level PR comments that are not attached to a review thread:
     ```bash
     create-comment --body "{comment_body}"
     ```
   - `create-comment` also automatically prefixes the final comment body with `🤖 `.
   - **Resolve helper** (only after replying):
     ```bash
     resolve-thread --thread-id "{thread_id}"
     ```
   - Always reply BEFORE resolving.
   - If the reply fails, do not resolve the thread.
   - Resolve a question thread when the answer is conclusive. Leave it open when the response asks the reviewer for clarification or a decision.
   - Leave ambiguous, conflicting, regressive, failed-verification, and still-relevant outdated feedback open until it is genuinely handled.
   - Skip all reply and resolve commands in no-GitHub-write mode.
   - `resolve-thread` is idempotent through GitHub's mutation behavior — already-resolved threads won't error.
8. Re-run focused checks/tests relevant to touched files and summarize results.
9. Report the review result.
   - Use the required output format below rather than replacing per-thread entries with an aggregate list.
   - Update the PR title or description only when the user explicitly requests that separate operation.

## Gotchas

- Do not read every raw thread body first on large PRs; summarize and filter by path, reviewer, and unresolved state before opening details.
- Resolved and outdated threads are often noise unless the user explicitly asks for a full audit.
- Keep GraphQL fetching in `gh`; the Rust helper should only post-process saved thread metadata.
- When multiple reviewers comment on the same file, address the blocking or request-changes paths first.
- `create-comment` targets the current branch PR by default and can take `--pr` when you need an explicit PR target.
- `create-thread-reply` expects a review thread ID, not a comment ID.
- Keep the reply text agent-specific (`FROM CLAUDE:` etc.); the helper adds only the robot emoji prefix.
- If any helper command is missing, reapply the profile so the packaged helpers are rebuilt and activated.

## Required output format

Include one entry for every in-scope review thread. Group exact duplicates only when every thread remains identifiable.

For each thread, include:

- `Comment`: a concise summary of the reviewer's feedback.
- `Our response (posted)` or `Our response (draft)`: the response text verbatim when available, otherwise a faithful concise paraphrase.
- `Outcome`: `resolved` or `open`, followed by the reason.
- `Verification`: the focused evidence supporting the disposition, or `not applicable`.

Label the entry with the reviewer and file location when available. When the thread caused a code change, always add `Code change` with a fenced `diff` or source snippet showing the essential few lines. Omit `Code change` entirely for unchanged code, explanation-only responses, and false positives.

Finish with totals for handled, resolved, and still-open threads.

## Notes

- If `gh` auth fails, ask user to run `gh auth login`, then retry.
- Keep responses concise and factual when a comment is a false positive.

## Bundled Resources

- `fetch-comments --format compact` - Emits flattened tab-separated thread metadata for local summarization and pipes cleanly into `summarize-threads`.
- `summarize-threads` - Groups flattened thread metadata from stdin or a file path by file, reviewer, and resolution state into compact JSON.
- `create-comment` - Creates a top-level PR comment and automatically prefixes the body with `🤖 `.
- `create-thread-reply` - Creates a review-thread reply and automatically prefixes the body with `🤖 `.
- `resolve-thread` - Resolves a review thread by thread ID.
- `scripts/` - Rust source package that the Nix profile builds into the helper commands on `PATH`.

---
name: gh-address-comments
description: Use when a user asks to review and address GitHub PR comments on the current branch; fetch review threads with gh, triage unresolved items, and apply focused fixes.
metadata:
  short-description: Address GitHub PR review comments
---

# PR Comment Handler

Use the `gh` CLI to fetch PR comments for the current branch and address actionable feedback.

Bootstrap installs the Rust helper commands into `~/.local/bin`, so call them directly.

If no PR exists for the current branch, report this and stop.

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
   - `create-comment --body "FROM CODEX: Ready for another look."`
5. Post a thread reply with the bundled helper.
   - `create-thread-reply --thread-id "<thread_id>" --body "FROM CODEX: Addressed in <sha> - <description>"`
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
     - `gh pr diff -- <filepath>`
   - Read the full thread before acting.
   - Triage false positives vs legitimate issues.
   - For legitimate issues, apply cohesive fixes file-by-file.
   - Check for similar issues in related code paths:
     - `git diff main...HEAD`
     - `git diff`
6. Commit strategy.
   - If the user asks for commits, make one commit per thread (or cohesive thread group).
   - Use conventional commit types (`fix`, `refactor`, `style`, `docs`, `test`).
   - Link commit body to the specific PR comment URL.
7. Reply and resolve threads.
   - For each processed thread, reply and optionally resolve using the thread `id` from step 2.
   - **Reply rules:**
     | Classification | Reply | Resolve? |
     |----------------|-------|----------|
     | False positive | `FROM CODEX: <explanation>` | Yes |
     | Addressed | `FROM CODEX: Addressed in <sha> — <description>` | Yes |
     | Question | `FROM CODEX: <answer>` | No |
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
   - Do NOT resolve question threads — leave open for the reviewer.
   - `resolve-thread` is idempotent through GitHub's mutation behavior — already-resolved threads won't error.
8. Re-run focused checks/tests relevant to touched files and summarize results.
9. Update PR description.
   - After all comments are addressed and committed, update the PR description to reflect the **current state** of the PR (not the history of steps taken).
   - Follow the **gh-manage-pr** skill workflow to regenerate and apply the updated description.

## Gotchas

- Do not read every raw thread body first on large PRs; summarize and filter by path, reviewer, and unresolved state before opening details.
- Resolved and outdated threads are often noise unless the user explicitly asks for a full audit.
- Keep GraphQL fetching in `gh`; the Rust helper should only post-process saved thread metadata.
- When multiple reviewers comment on the same file, address the blocking or request-changes paths first.
- `create-comment` targets the current branch PR by default and can take `--pr` when you need an explicit PR target.
- `create-thread-reply` expects a review thread ID, not a comment ID.
- Keep the reply text agent-specific (`FROM CODEX:` etc.); the helper adds only the robot emoji prefix.
- If any helper command is missing, rerun bootstrap so the installed binaries in `~/.local/bin` are refreshed.

## Output Format

1. Code Examples
   - Before/after snippets grouped by file
2. Summary Table
   - File, line, reviewer, type, comment, resolution, commit (if any)

## Notes

- If `gh` auth fails, ask user to run `gh auth login`, then retry.
- Keep responses concise and factual when a comment is a false positive.

## Bundled Resources

- `fetch-comments --format compact` - Emits flattened tab-separated thread metadata for local summarization and pipes cleanly into `summarize-threads`.
- `summarize-threads` - Groups flattened thread metadata from stdin or a file path by file, reviewer, and resolution state into compact JSON.
- `create-comment` - Creates a top-level PR comment and automatically prefixes the body with `🤖 `.
- `create-thread-reply` - Creates a review-thread reply and automatically prefixes the body with `🤖 `.
- `resolve-thread` - Resolves a review thread by thread ID.
- `scripts/` - Rust source package that bootstrap uses to install the helper commands.

---
name: gh-address-comments
description: Use when a user asks to review and address GitHub PR comments on the current branch; fetch review threads with gh, triage unresolved items, and apply focused fixes.
metadata:
  short-description: Address GitHub PR review comments
---

# PR Comment Handler

Use the `gh` CLI to fetch PR comments for the current branch and address actionable feedback. The active Nix profile puts the Rust helper commands on `PATH`, so call them directly.

If no PR exists for the current branch, report this and stop.

## Inputs

- `repo`: repository path (default `.`)
- `pr`: PR number or URL (optional; defaults to current branch PR)
- optional flags: `--all` / `--include-resolved` to include resolved threads (default: unresolved only)

## Workflow

1. Gather PR context.
   - `gh pr view --json number,url,title,body,baseRefName,headRefName,reviews,state,statusCheckRollup`
   - `gh pr diff`
   - `gh pr checks`
2. Fetch comments and review threads.
   - Preferred: `fetch-comments --format json` for full conversation/review/thread data.
   - For large review sets, run `fetch-comments --format compact | summarize-threads` first so grouped metadata arrives before individual thread bodies.
   - Manual fallback: `gh api graphql` query for `reviewThreads`, `reviews`, and thread comments.
3. Filter scope.
   - Process unresolved threads only, unless the user asks for a full audit.
   - Skip outdated threads unless still relevant, and pure bot noise unless it points to real breakage.
4. Organize comments for efficient action.
   - Group by file, then thread, then reviewer.
   - Classify each item: Blocking (typically from `CHANGES_REQUESTED`), Suggestion, Question, or Nitpick.
5. Process each file's unresolved threads.
   - Inspect file-specific diff context: `git diff <baseRefName>...HEAD -- <filepath>`
   - Read the full thread before acting, then triage false positives vs legitimate issues.
   - For legitimate issues, apply cohesive fixes file-by-file, addressing blocking threads first.
   - Check for similar issues in related code paths across the branch diff.
6. Commit strategy.
   - If the user asks for commits, make one commit per thread (or cohesive thread group).
   - Use conventional commit types and link the commit body to the specific PR comment URL.
7. Reply and resolve threads using the thread `id` from step 2.
   | Classification | Reply | Resolve? |
   |----------------|-------|----------|
   | False positive | `FROM CLAUDE: <explanation>` | Yes |
   | Addressed | `FROM CLAUDE: Addressed in <sha> — <description>` | Yes |
   | Question | `FROM CLAUDE: <answer>` | No — leave open for the reviewer |
   - Thread reply: `create-thread-reply --thread-id "<thread_id>" --body "<reply_body>"`
   - Top-level comment (outside any review thread): `create-comment --body "<comment_body>"`
   - Resolve only after replying: `resolve-thread --thread-id "<thread_id>"`
8. Re-run focused checks/tests relevant to touched files and summarize results.
9. Report the result: addressed, deferred, and still-open threads plus focused verification. Update the PR title or description only when the user explicitly requests that separate operation.

## Gotchas

- Keep GraphQL fetching in `gh`; the helpers only post-process saved thread metadata.
- `create-comment` targets the current branch PR by default and accepts `--pr` for an explicit target.
- `create-thread-reply` expects a review thread ID, not a comment ID.
- Both posting helpers automatically prefix the final body with `🤖 `; keep the reply text itself agent-specific (`FROM CLAUDE:`).
- `resolve-thread` is idempotent; already-resolved threads won't error.
- If any helper command is missing, reapply the profile so the packaged helpers are rebuilt and activated.
- If `gh` auth fails, ask the user to run `gh auth login`, then retry.

## Output Format

1. Code Examples — before/after snippets grouped by file
2. Summary Table — file, line, reviewer, type, comment, resolution, commit (if any)

## Bundled Resources

- `fetch-comments --format compact` - Emits flattened tab-separated thread metadata that pipes cleanly into `summarize-threads`.
- `summarize-threads` - Groups flattened thread metadata by file, reviewer, and resolution state into compact JSON.
- `create-comment` - Creates a top-level PR comment.
- `create-thread-reply` - Creates a review-thread reply.
- `resolve-thread` - Resolves a review thread by thread ID.

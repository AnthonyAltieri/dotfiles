---
name: gh-address-comments
description: Use when a user asks to review and address GitHub PR comments on the current branch; fetch review threads with gh, triage unresolved items, and apply focused fixes.
metadata:
  short-description: Address GitHub PR review comments
---

# PR Comment Handler

Use the `gh` CLI to fetch PR comments for the current branch and address actionable feedback.

If no PR exists for the current branch, report this and stop.

## Inputs

- `repo`: repository path (default `.`)
- `pr`: PR number or URL (optional; defaults to current branch PR)
- optional flags:
  - `--all` / `--include-resolved`: include resolved threads
  - default behavior: unresolved threads only

## Quick start

1. Fetch review data with the Rust helper.
   - `cargo run --quiet --release --manifest-path "$CODEX_HOME/skills/gh-address-comments/scripts/Cargo.toml" --bin fetch-comments -- --format compact > /tmp/pr-threads.tsv`
2. Compile or run the Rust summarizer when you need compact grouping instead of raw thread JSON.
   - `cargo run --quiet --release --manifest-path "$CODEX_HOME/skills/gh-address-comments/scripts/Cargo.toml" --bin summarize-threads -- /tmp/pr-threads.tsv`
3. Summarize unresolved threads before reading full comment bodies.
   - Or build once and run the binary from `target/release/summarize-threads`

## Workflow

1. Gather PR context.
   - `gh pr view --json number,url,title,body,baseRefName,headRefName,reviews,state,statusCheckRollup`
   - `gh pr diff`
   - `gh pr checks`
2. Fetch comments and review threads.
   - Preferred: run `scripts/fetch-comments` for full conversation/review/thread data.
   - For large review sets, use `--format compact` and `scripts/summarize-threads` first so the model sees grouped metadata before opening individual threads.
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
   - **Reply mutation:**
     ```bash
     gh api graphql -f query='
       mutation($threadId: ID!, $body: String!) {
         addPullRequestReviewThreadReply(input: {
           pullRequestReviewThreadId: $threadId, body: $body
         }) { comment { id } }
       }
     ' -f threadId="{thread_id}" -f body="{reply_body}"
     ```
   - **Resolve mutation** (only after replying):
     ```bash
     gh api graphql -f query='
       mutation($threadId: ID!) {
         resolveReviewThread(input: { threadId: $threadId }) {
           thread { isResolved }
         }
       }
     ' -f threadId="{thread_id}"
     ```
   - Always reply BEFORE resolving.
   - Do NOT resolve question threads — leave open for the reviewer.
   - `resolveReviewThread` is idempotent — already-resolved threads won't error.
8. Re-run focused checks/tests relevant to touched files and summarize results.
9. Update PR description.
   - After all comments are addressed and committed, update the PR description to reflect the **current state** of the PR (not the history of steps taken).
   - Follow the **gh-manage-pr** skill workflow to regenerate and apply the updated description.

## Gotchas

- Do not read every raw thread body first on large PRs; summarize and filter by path, reviewer, and unresolved state before opening details.
- Resolved and outdated threads are often noise unless the user explicitly asks for a full audit.
- Keep GraphQL fetching in `gh`; the Rust helper should only post-process saved thread metadata.
- When multiple reviewers comment on the same file, address the blocking or request-changes paths first.

## Output Format

1. Code Examples
   - Before/after snippets grouped by file
2. Summary Table
   - File, line, reviewer, type, comment, resolution, commit (if any)

## Notes

- If `gh` auth fails, ask user to run `gh auth login`, then retry.
- Keep responses concise and factual when a comment is a false positive.

## Bundled Resources

- `scripts/fetch-comments --format compact` - Emits flattened tab-separated thread metadata for local summarization.
- `scripts/summarize-threads` - Groups flattened thread metadata by file, reviewer, and resolution state into compact JSON.

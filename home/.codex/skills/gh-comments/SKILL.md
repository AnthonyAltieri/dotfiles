---
name: gh-comments
description: GitHub PR comment companion for fetching comments, summarizing review threads, and performing prompt-gated comment, reply, or resolve actions. Use when the user asks for those comment operations; use github:gh-address-comments when code changes are required.
---

# GitHub Comments

Use the bundled helpers for deterministic PR review-thread reads and narrowly scoped mutations. This skill does not edit application code, commit changes, update PR descriptions, or publish branches.

## Routing boundary

- Use this skill for explicit requests to fetch or summarize PR comments, post a top-level comment, reply to a review thread, or resolve a thread.
- Use `github:gh-address-comments` when feedback must be triaged and implemented in the codebase.
- Use `gh-pr-body` for PR title, body, or body-image updates.
- Use `gh-ci` for deterministic GitHub Actions log extraction or classification.

## Read workflow

1. Confirm that the current branch has a PR with `gh pr view --json number,url,title,state`.
2. Fetch unresolved threads by default:
   - `fetch-comments --format compact | summarize-threads`
   - `fetch-comments --format json` when full bodies are required.
3. Add `--include-resolved` or `--all` only when the user requests resolved-thread history.
4. Group large results before opening full comment bodies.

The helper derives the base repository from the PR URL, so fork PRs query the repository that owns the pull request rather than the contributor's head fork.

## Mutation workflow

Only mutate GitHub when the user explicitly asks for the corresponding action. Use the helper command so the configured approval gate remains visible; do not replace it with a direct GraphQL mutation.

- Top-level comment: `create-comment --body-file <path>`
- Thread reply: `create-thread-reply --thread-id <thread-id> --body-file <path>`
- Resolve: `resolve-thread --thread-id <thread-id>`

Prefer `--body-file` or stdin over an inline body when text contains shell metacharacters. Reply before resolving. Leave question threads open unless the user explicitly asks to resolve them. The comment helpers add the robot prefix automatically.

When a bundled helper spawns `gh`, run it with the approval required by the local environment. If it reports an authentication failure only inside the sandbox, retry through the approved helper path before asking the user to authenticate.

## Bundled resources

- `fetch-comments` fetches PR conversation comments, reviews, and review threads.
- `summarize-threads` groups compact thread metadata locally.
- `create-comment` creates a top-level PR comment.
- `create-thread-reply` replies to a review thread.
- `resolve-thread` resolves a review thread.
- `scripts/` contains the Rust package used to build the commands.

---
name: gh-comments
description: Summarize GitHub pull request comments and unresolved review threads without making changes. Use when the user asks to fetch, inspect, or summarize PR conversation comments, reviews, inline comments, or thread state; use github:gh-address-comments when feedback must be implemented, replied to, or resolved.
---

# Github Summarize Comments

Use the bundled helpers for deterministic, thread-aware pull request comment summaries. Keep this workflow read-only: do not edit application code or make GitHub writes.

## Routing boundary

- Use this skill to fetch, inspect, or summarize PR conversation comments, reviews, and review threads.
- Use `github:gh-address-comments` when feedback must be implemented, answered on GitHub, or resolved.
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

## Read-only boundary

- Do not post top-level comments, reply to threads, resolve threads, submit reviews, edit PR metadata, or change repository files.
- Do not turn discovered feedback into code changes within this skill.
- Route any requested mutation or implementation to the appropriate skill instead of expanding this workflow.

## Bundled resources

- `fetch-comments` fetches PR conversation comments, reviews, and review threads.
- `summarize-threads` groups compact thread metadata locally.
- `scripts/` contains the Rust package used to build the commands.

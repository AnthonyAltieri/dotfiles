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

## Workflow

1. Gather PR context.
   - `gh pr view --json number,url,title,body,baseRefName,headRefName,reviews,state,statusCheckRollup`
   - `gh pr diff`
   - `gh pr checks`
2. Fetch comments and review threads.
   - Preferred: run `scripts/fetch_comments.py` for full conversation/review/thread data.
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
7. Re-run focused checks/tests relevant to touched files and summarize results.

## Output Format

1. Code Examples
   - Before/after snippets grouped by file
2. Summary Table
   - File, line, reviewer, type, comment, resolution, commit (if any)

## Notes

- If `gh` auth fails, ask user to run `gh auth login`, then retry.
- Keep responses concise and factual when a comment is a false positive.

---
name: gh-manage-pr
description: Use when a user asks to create or update a GitHub pull request; detect existing PR for the branch, generate a dense structured PR body from branch changes, and apply it via gh.
metadata:
  short-description: Create or update GitHub PRs with structured descriptions
---

# Create or Update PR

Create or update a pull request with the GitHub CLI (`gh`).

## Inputs

- `repo`: repository path (default `.`)
- `base`: base branch for comparison (default `master`, fallback `main` if needed)
- optional title/body hints from user

## Workflow

1. Resolve PR context.
   - Check whether a PR already exists for the current branch:
     - `gh pr view --json number,url,title,body,baseRefName,headRefName`
   - If no PR exists, prepare `gh pr create`.
   - If PR exists, prepare `gh pr edit`.
2. Analyze changes against base branch.
   - `git diff <base>...HEAD --stat`
   - `git diff <base>...HEAD`
   - Group changes by major feature/area.
3. Draft information-dense PR description.
   - Section 1: feature summary (bullets only, user-facing capabilities)
   - Section 2+: implementation details by major change area
   - Include concise rationale, focused code examples, and tables when useful.
4. Apply the PR update.
   - Create:
     - `gh pr create --title "<title>" --body-file <tmpfile>`
   - Update:
     - `gh pr edit <pr> --title "<title>" --body-file <tmpfile>`
5. Return final PR URL and a concise summary of what was updated.

## PR Body Structure

### 1. Summary

- Bullet points only
- Focus on capabilities and outcomes, not low-level implementation details
- Answer: what users/developers can do now that they could not before

### 2+. Implementation

For each major change area:
- Why key decisions were made
- Example snippets showing usage patterns
- Tables for before/after, APIs, config options, or behavior deltas

## Style Guidelines

- Keep writing concise and information-dense
- Prefer tables for structured details
- Use fenced code blocks with language tags
- Avoid filler phrases

## Output Format

1. PR action taken
   - Created or updated
   - PR number + URL
2. Final title
3. Final description preview (or key sections summary)
4. Any follow-up recommendations (for example requested reviewers, labels)

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

## Quick start

1. Capture the branch diff and diff stat.
   - `git diff <base>...HEAD --stat > /tmp/pr.diffstat`
   - `git diff <base>...HEAD > /tmp/pr.diff`
2. Compile the Rust summarizer when you need compact structure instead of raw diff context.
   - `rustc "$CODEX_HOME/skills/gh-manage-pr/scripts/summarize_diff.rs" -O -o /tmp/gh-manage-pr-summarize`
3. Run the summarizer and use the JSON output plus `assets/pr-body-template.md` to draft the PR body.
   - `/tmp/gh-manage-pr-summarize /tmp/pr.diffstat`

## Workflow

1. Resolve PR context.
   - Check whether a PR already exists for the current branch:
     - `gh pr view --json number,url,title,body,baseRefName,headRefName`
   - If no PR exists, prepare `gh pr create --draft` unless the user explicitly asks for a ready-for-review/open PR.
   - If PR exists, prepare `gh pr edit`.
2. Analyze changes against base branch.
   - `git diff <base>...HEAD --stat`
   - `git diff <base>...HEAD`
   - Group changes by major feature/area.
   - Prefer the Rust summarizer for large diffs so the model reads compact JSON instead of the full diff first.
3. Draft information-dense PR description.
   - Section 1: feature summary (bullets only, user-facing capabilities)
   - Section 2+: implementation details by major change area
   - Include concise rationale, focused code examples, and tables when useful.
   - Start from `assets/pr-body-template.md` rather than freehanding the structure.
4. Apply the PR update.
   - Create:
     - Default: `gh pr create --draft --title "<title>" --body-file <tmpfile>`
     - Only omit `--draft` when the user explicitly asks for a ready-for-review/open PR.
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

## Gotchas

- Avoid narrating the implementation process; the PR body should describe the current state of the branch.
- Do not let raw diff volume dominate the prompt. Summarize first, then pull exact snippets only for the sections that need examples.
- For mixed-feature branches, group by subsystem and user-visible capability instead of by commit order.
- Keep the summary section outcome-focused; implementation details belong in later sections.
- New PRs default to draft unless the user explicitly asks for a ready-for-review/open PR.

## Output Format

1. PR action taken
   - Created or updated
   - PR number + URL
2. Final title
3. Final description preview (or key sections summary)
4. Any follow-up recommendations (for example requested reviewers, labels)

## Bundled Resources

- `scripts/summarize_diff.rs` - Converts `git diff --stat` output into compact JSON grouped by subsystem, with exact top-level insertion/deletion totals and per-section change magnitude.
- `assets/pr-body-template.md` - Reusable PR body structure with placeholders for summary and implementation sections.

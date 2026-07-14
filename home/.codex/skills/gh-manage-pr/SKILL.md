---
name: gh-manage-pr
description: Use when a user asks to create or update a GitHub pull request or add an image to a PR body; detect existing PR context, generate a dense structured description, apply it via gh, and use the dedicated prompt-gated image helper for supported uploads.
metadata:
  short-description: Create, update, or add an image to a GitHub PR
---

# Create, Update, or Add an Image to a PR

Create or update a pull request with the GitHub CLI (`gh`), and use `gh-pr-image` when an image must be added to its body.

## Inputs

- `repo`: repository path (default `.`)
- `base`: base branch for comparison (default `master`, fallback `main` if needed)
- `pr`: PR number, URL, or branch when the image target should not be inferred
- optional image path and required accessible alt text for PR-body images
- optional title/body hints from user

## Quick start

1. Capture the branch diff and diff stat.
   - `git diff <base>...HEAD --stat > /tmp/pr.diffstat`
   - `git diff <base>...HEAD > /tmp/pr.diff`
2. Use the installed summarizer helper when you need compact structure instead of raw diff context.
   - `gh-manage-pr-summarize /tmp/pr.diffstat`
3. Run the summarizer and use the JSON output plus `assets/pr-body-template.md` to draft the PR body.
   - `gh-manage-pr-summarize /tmp/pr.diffstat`
4. When asked to add an image to the PR body, use the prompt-gated image helper.
   - `gh-pr-image add <image> --alt <text> [--pr ...] [-R ...]`

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
5. Add a requested image to the PR body.
   - You must use `gh-pr-image add <image> --alt <text> [--pr ...] [-R ...]` rather than constructing a separate upload or image-hosting workflow.
   - The current MVP accepts exactly one PNG, JPEG, or GIF per invocation.
   - Use it only for a public PR whose head and base are in the same repository. Private repositories and fork-authored PRs are not supported.
   - The command is prompt-gated because it uploads bytes and updates GitHub state. Allow that approval flow; do not bypass it with lower-level commands.
   - The upload uses an experimental, undocumented GitHub endpoint. If the target is unsupported, report the limitation instead of silently selecting another backend.
6. Return the final PR URL and a concise summary of what was updated.

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
- `gh-pr-image` is intentionally limited to one PNG, JPEG, or GIF per invocation on public, same-repository PRs.
- Treat a failure from its experimental, undocumented upload endpoint as a compatibility failure; do not fall back to browser cookies, third-party hosting, or repository-backed assets without a separate user decision.

## Output Format

1. PR action taken
   - Created or updated
   - PR number + URL
2. Final title
3. Final description preview (or key sections summary)
4. Any follow-up recommendations (for example requested reviewers, labels)

## Bundled Resources

- `gh-manage-pr-summarize` - Installed helper that converts `git diff --stat` output into compact JSON grouped by subsystem.
- `gh-pr-image` - Prompt-gated helper that adds one supported image to the body of a public, same-repository PR through an experimental GitHub upload endpoint.
- `scripts/summarize_diff.rs` - Converts `git diff --stat` output into compact JSON grouped by subsystem, with exact top-level insertion/deletion totals and per-section change magnitude.
- `assets/pr-body-template.md` - Reusable PR body structure with placeholders for summary and implementation sections.

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
- `base`: optional explicit comparison branch; otherwise use the existing PR's `baseRefName` or the repository's `defaultBranchRef.name`
- `pr`: PR number, URL, or branch when the image target should not be inferred
- optional image path and required accessible alt text for PR-body images
- optional title/body hints from user

## Workflow

1. Resolve PR context.
   - Check for an existing PR: `gh pr view --json number,url,title,body,baseRefName,headRefName`
   - No PR: prepare `gh pr create --draft`. Omit `--draft` only when the user explicitly asks for a ready-for-review/open PR.
   - PR exists: prepare `gh pr edit`.
2. Analyze changes against the base branch.
   - Use the existing PR's `baseRefName`, an explicitly requested base, or `gh repo view --json defaultBranchRef`.
   - `git diff <base>...HEAD --stat` and `git diff <base>...HEAD`
   - For large diffs, run `gh-manage-pr-summarize` on the saved diffstat so compact JSON grouped by subsystem arrives instead of the full diff. Pull exact snippets back only for sections that need examples.
3. Draft the description per the `gh-pr-description` skill: discover the
   repo's PR template and PR-lint rules first (headings, title grammar,
   labels, size ceilings), then write a Why-first, code-snippet-heavy body
   against them. The repo contract wins over any default template.
4. Apply the PR update.
   - Create: `gh pr create --draft --title "<title>" --body-file <tmpfile>`
   - Update: `gh pr edit <pr> --title "<title>" --body-file <tmpfile>`
5. Add a requested image to the PR body.
   - Use `gh-pr-image add <image> --alt <text> [--pr ...] [-R ...]` — never construct a separate upload or image-hosting workflow.
   - Accepts exactly one PNG, JPEG, or GIF per invocation, on public PRs that the authenticated GitHub account can update and whose head and base are in the same repository. Private, internal, and fork-authored PRs are unsupported.
   - The command is prompt-gated because it uploads bytes and updates GitHub state; allow that approval flow rather than bypassing it with lower-level commands.
   - The upload uses an experimental, undocumented GitHub endpoint. If the target is unsupported or the upload fails, report the limitation — do not fall back to browser cookies, third-party hosting, or repository-backed assets without a separate user decision.
6. If a PR lint job posts a verdict (sticky comment or check), confirm it
   re-ran clean against the new title/body and required labels.
7. Return the final PR URL and a concise summary of what was updated.

## Output Format

1. PR action taken — created or updated, PR number + URL
2. Final title
3. Final description preview (or key sections summary)
4. Any follow-up recommendations (for example requested reviewers, labels)

## Bundled Resources

- `gh-manage-pr-summarize` - Installed helper that converts `git diff --stat` output into compact JSON grouped by subsystem.
- `gh-pr-image` - Prompt-gated helper that adds one supported image to a PR body.
- The `gh-pr-description` skill owns the body-writing method and the default template.

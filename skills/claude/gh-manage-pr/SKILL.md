---
name: gh-manage-pr
description: Use when a user asks to create or update a GitHub pull request or attach an image or video to a PR body; detect existing PR context, generate a dense structured description, and apply it with gh, uploading media through gh's built-in --attach flag.
metadata:
  short-description: Create, update, or attach media to a GitHub PR
---

# Create, Update, or Attach Media to a PR

Create or update a pull request with the GitHub CLI (`gh`). Images and videos go through `gh`'s own `--attach` flag; never build a separate upload path.

## Inputs

- `repo`: repository path (default `.`)
- `base`: optional explicit comparison branch; otherwise use the existing PR's `baseRefName` or the repository's `defaultBranchRef.name`
- `pr`: PR number, URL, or branch when the target should not be inferred
- optional image or video paths, with alt text for each image
- optional title/body hints from user

## Workflow

1. Resolve PR context.
   - Check for an existing PR: `gh pr view --json number,url,title,body,baseRefName,headRefName`
   - No PR: prepare `gh pr create --draft`. Omit `--draft` only when the user explicitly asks for a ready-for-review/open PR.
   - PR exists: prepare `gh pr edit`.
2. Analyze changes against the base branch.
   - Use the existing PR's `baseRefName`, an explicitly requested base, or `gh repo view --json defaultBranchRef`.
   - `git diff <base>...HEAD --stat` and `git diff <base>...HEAD`
   - For large diffs, read `git diff <base>...HEAD --dirstat=files,0` and the diffstat first to see which subsystems changed, then pull hunks only for the sections that need snippets.
3. Draft the description per the `gh-pr-description` skill: discover the
   repo's PR template and PR-lint rules first (headings, title grammar,
   labels, size ceilings), then write a Why-first, code-snippet-heavy body
   against them. The repo contract wins over any default template.
4. Apply the PR update, adding `--attach` flags on the same command when media is requested (step 5).
   - Create: `gh pr create --draft --title "<title>" --body-file <tmpfile>`
   - Update: `gh pr edit <pr> --title "<title>" --body-file <tmpfile>`
5. Attach images or videos with `--attach`.
   - Requires `gh` 2.99.0 or newer (`gh --version`). If the flag is missing, report that and ask the user to upgrade `gh`. Do not fall back to browser cookies, third-party hosting, repository-committed assets, or undocumented endpoints.
   - Put each file where it belongs in the body by referencing its local path in Markdown, then pass the same path with `--attach`; `gh` uploads the file and rewrites the reference in place, keeping the Markdown alt text.
     - Image: `![<alt text>](./shot.png)`
     - Video: `![](./demo.mp4)` alone in its own paragraph, so it renders as a player rather than a link. Videos have no alt text.
   - A file the body does not reference is appended to the end in flag order. Give appended images alt text as `--attach './shot.png#<alt text>'`; without it, `gh` uses the filename.
   - Repeat `--attach` per file, up to 50 per command, never the same file twice. Limits match web uploads: 10 MB per image or GIF; 10 MB per video on free plans and 100 MB on paid plans. The authenticated account needs push access to the repository.
   - Example: `gh pr edit <pr> --body-file <tmpfile> --attach './before.png#Login form before' --attach './after.png#Login form after'`
   - Read the body back afterwards and confirm every local path was replaced with an uploaded URL.
6. If a PR lint job posts a verdict (sticky comment or check), confirm it
   re-ran clean against the new title/body and required labels.
7. Return the final PR URL and a concise summary of what was updated.

## Output Format

1. PR action taken — created or updated, PR number + URL
2. Final title
3. Final description preview (or key sections summary)
4. Attachments added, if any, with their alt text
5. Any follow-up recommendations (for example requested reviewers, labels)

## Related Skills

- The `gh-pr-description` skill owns the body-writing method and the default template.

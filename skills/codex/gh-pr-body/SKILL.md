---
name: gh-pr-body
description: Update the title or body of an existing GitHub pull request and attach requested images or videos through gh's built-in --attach flag. Use for existing-PR description maintenance or PR-body media; do not use to create, commit, push, publish, review, or diagnose a pull request.
---

# GitHub PR Body

Maintain the current state description of an existing pull request. Use `github:yeet` or another explicitly requested publication workflow when no PR exists.

## Resolve context

1. Read the existing PR and its actual base:

   ```bash
   gh pr view --json number,url,title,body,baseRefName,headRefName
   ```

2. If no PR exists, stop and route creation to the publication workflow. Never create a PR from this skill.
3. Compare the branch with `baseRefName`; do not assume `master` or `main`:

   ```bash
   git diff <baseRefName>...HEAD --stat
   git diff <baseRefName>...HEAD
   ```

For a large diff, read `git diff <baseRefName>...HEAD --dirstat=files,0` and the diffstat first, then pull hunks only for the sections that need snippets.

## Draft the body

Draft per the `gh-pr-description` skill: discover the repo's PR template and
PR-lint rules first (headings, title grammar, labels, size ceilings), then
write a Why-first, code-snippet-heavy body against them. The repo contract
wins over any default template. Preserve unrelated user-authored sections
unless the requested update clearly replaces them.

Apply an authorized update with `gh pr edit --title ... --body-file ...`, then
read the PR back, verify the exact title/body, and confirm any PR lint verdict
re-ran clean.

## Attach an image or video

Use `gh`'s built-in `--attach` on the same `gh pr edit` call; never build a separate upload path (browser cookies, direct GraphQL mutations, third-party hosting, repository-committed assets, or undocumented endpoints).

```bash
gh pr edit <pr> --body-file <tmpfile> --attach './before.png#Login form before' --attach './after.png#Login form after'
```

- Requires `gh` 2.99.0 or newer (`gh --version`). If the flag is missing, report that and ask the user to upgrade `gh`.
- Reference each file's local path in the body Markdown so it lands where intended; `gh` uploads it and rewrites the reference in place, keeping the Markdown alt text. Images: `![<alt text>](./shot.png)`. Videos: `![](./demo.mp4)` alone in its own paragraph so it renders as a player. Videos have no alt text.
- A file the body does not reference is appended to the end in flag order; give appended images alt text as `--attach './shot.png#<alt text>'`.
- Repeat `--attach` per file, up to 50 per command, never the same file twice. Limits match web uploads: 10 MB per image or GIF; 10 MB per video on free plans and 100 MB on paid plans. The authenticated account needs push access to the repository.

After `gh` returns, read the PR body back and verify every local path was replaced with an uploaded URL.

## Output

Return the PR URL, final title, changed body sections, attachments added when applicable, and readback verification.

## Related skills

- The `gh-pr-description` skill owns the body-writing method and the default template.

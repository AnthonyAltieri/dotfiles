---
name: gh-pr-body
description: Update the title or body of an existing GitHub pull request and add a requested image through the prompt-gated `gh-pr-image` helper. Use for existing-PR description maintenance or supported PR-body attachments; do not use to create, commit, push, publish, review, or diagnose a pull request.
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

For a large diffstat, `gh-manage-pr-summarize` can produce compact JSON grouped by subsystem.

## Draft the body

Draft per the `gh-pr-description` skill: discover the repo's PR template and
PR-lint rules first (headings, title grammar, labels, size ceilings), then
write a Why-first, code-snippet-heavy body against them. The repo contract
wins over any default template. Preserve unrelated user-authored sections
unless the requested update clearly replaces them.

Apply an authorized update with `gh pr edit --title ... --body-file ...`, then
read the PR back, verify the exact title/body, and confirm any PR lint verdict
re-ran clean.

## Add an image

When the user asks to add an image, use only:

```bash
gh-pr-image add <image> --alt <text> [--pr ...] [-R ...]
```

The helper is prompt-gated because it uploads bytes and changes GitHub state. Do not bypass it with browser cookies, direct GraphQL mutations, third-party hosting, or repository-backed assets.

The current helper accepts exactly one PNG, JPEG, or GIF per invocation and supports only public, same-repository PRs that the authenticated viewer can update. Fork-authored, private, and internal PRs are unsupported. If its experimental upload endpoint fails, report the compatibility failure instead of selecting another backend.

After the helper returns, read the PR body back and verify the managed attachment entry.

## Output

Return the PR URL, final title, changed body sections, image result when applicable, and readback verification.

## Bundled resources

- `gh-pr-image` validates the image, preserves a recovery journal, updates a managed attachment block idempotently, and verifies the final body.
- `gh-manage-pr-summarize` compacts a diffstat when needed.
- The `gh-pr-description` skill owns the body-writing method and the default template.

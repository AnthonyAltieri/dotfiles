---
name: gh-pr-description
description: Write or rewrite a GitHub PR title and description. Use when drafting a PR body — directly or from gh-manage-pr / gh-pr-body; conforms to the repo's PR template and PR-lint CI, then explains the branch with code snippets. Does not create, push, or edit PRs itself.
---

# Write a PR Description

Produce an information-dense description of the branch's current state. The
repo's own contract always wins over the default template bundled here.

## 1. Discover the repo contract

Before drafting, gather what the repository enforces:

1. PR template: `.github/pull_request_template.md` (or `PULL_REQUEST_TEMPLATE/`).
   Its headings are the required skeleton — keep their exact names; the
   template's HTML comments describe each section's intent.
2. PR lint CI: grep `.github/workflows/` for jobs linting the PR
   (title/body/label checks). When the job uses an external action, fetch its
   source to learn the actual rules instead of guessing:

   ```bash
   gh api repos/<org>/<actions-repo>/contents/<path>/checks.go --jq .content | base64 -d
   ```

   Extract: title grammar (conventional type, scope, ticket-key), required
   body headings, required labels (authorship, risk), and diff-size ceilings
   with their override labels.
3. Size ceilings: compute the non-generated diff size against the lint's
   exclusion globs. If over a hard ceiling, add the override label and justify
   it in the body (why the change is atomic / why splitting costs more).

## 2. Structure

Use the repo template's headings when they exist; otherwise start from
`assets/pr-body-template.md`. Either way, cover:

- **Why** — the problem in 1–3 sentences, then the quantified net effect
  (lines removed, calls collapsed, joins eliminated, ms saved). Numbers over
  adjectives. Link the ticket; leave contract details in the ticket.
- **What changed** — one `###` subsection per subsystem or user-visible
  capability (never commit order). Each subsection: one line of rationale,
  then code.
- **How to verify** — numbered steps a reviewer follows to reach the changed
  code (flag to flip, URL to open, command to run, what they should see).
  For cases needing awkward setup, write `covered by <test file>` instead.
  End with the exact gate commands that passed.
- **Risks / notes** — only consequences the reviewer must act on: breaking
  contracts with deploy ordering, removed behavior, observability changes,
  and the justification for any policy-override label.

## 3. Explain with code

Prefer a snippet over a paragraph wherever the change has a shape:

- **Contract deltas**: before/after request or response payloads as `jsonc`
  with `// before:` / `// after:` comments.
- **Schema/DDL**: the deciding lines only — keys, constraints, the copy/drop
  statements — with `-- + ...` comments for elided columns.
- **Renames/moves**: paired before → after lines or a two-column table, not
  prose.
- **Key logic**: quote the actual new code (hash formulas, defaults, guards)
  verbatim so the reviewer reads it here first.
- **Query/dataflow topology**: joins and call chains as comment diagrams
  (`a ⨝ b ⨝ c` → `a ⨝ b`).

Every fence has a language tag. Trim each snippet to what the reviewer needs;
elide with comments rather than pasting whole files.

## 4. Density rules

- Describe the branch's current state; never narrate the implementation
  process or preserve stale claims from a previous body.
- Every sentence must tell the reviewer something they can't get faster from
  the diff — counts, orderings, invariants, compat windows.
- Tables for behavior deltas, API surfaces, config options; bullets elsewhere;
  no filler headings.

## 5. Verify the result

After the body is applied (by the calling workflow), read it back, and if a PR
lint job posts a verdict (sticky comment or check), confirm it re-ran clean —
required labels present, no blocking errors. Report any advisory warnings.

## Bundled resources

- `assets/pr-body-template.md` — the default skeleton, used only when the repo
  has no PR template of its own.

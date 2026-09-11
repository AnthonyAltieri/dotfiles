---
name: gh-pr-description
description: Write or rewrite a GitHub PR title and description. Use when drafting a PR body — directly or from gh-manage-pr / gh-pr-body; conforms strictly to the repo's PR template and PR-lint CI by default, writes the prose in the plain human voice of the bro skill, and explains the branch with small snippets (type signatures and pseudocode preferred). Does not create, push, or edit PRs itself.
---

# Write a PR Description

Produce an information-dense description of the branch's current state, in
plain human language. The repo's own contract always wins over the default
template bundled here.

Two defaults hold unless the user says otherwise in the request:

- **Strict compliance.** The PR must pass every rule the repository's PR
  template and PR-lint configuration enforce, exactly as configured. Do not
  loosen, skip, or reinterpret a rule because it is inconvenient; do not add a
  heading the template does not have or drop one it requires. Only an explicit
  user instruction to deviate changes this.
- **Bro voice.** The prose follows the `bro` skill's rule: plain human
  language, no jargon, one human talking to another. Section 3 below spells out
  how that applies to a PR.

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
   exclusion globs. If over a hard ceiling, add the override label the lint
   itself defines and justify it in the body (why the change is atomic / why
   splitting costs more). An override label is the lint's own escape hatch and
   still counts as compliant; inventing one, or omitting a required label, does
   not.
4. No local contract: when the repo has neither a PR template nor a PR-lint
   job, use `assets/pr-body-template.md` and the conventional-commit title
   grammar. Say so in the report.

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

## 3. Voice: write it like bro

Apply the `bro` skill's rule to every sentence of prose: plain human language,
no jargon, one human talking to another. Concretely:

- Short sentences with a verb. Say what the code does now and why, the way you
  would tell a teammate at their desk.
- No internal shorthand, acronyms, or codenames without a one-time plain
  expansion. No "leverage", "utilize", "robust", "seamless", or other filler.
- Facts still win: keep the numbers, orderings, and invariants from section 4.
  Plain does not mean vague; it means a reader outside the team follows it on
  the first pass.
- Do not narrate your process or your reasoning. Describe the branch.
- Section headings come from the repo template and are never rewritten for
  voice; the template is part of the compliance contract.

The `bro` skill is a user-invoked command, so do not try to call it while
drafting. Apply its rule yourself, then read the body back once as if you were
the reviewer and simplify anything you would have to reread.

## 4. Explain with small snippets

Reach for a snippet when the change has a shape a reader grasps faster from
code than from prose. Keep each snippet small enough to read in one glance,
and prefer the most legible form:

- **Type signatures** first. A function or type signature usually says more
  than a paragraph and stays short:

  ```ts
  // before
  function claim(issue: Issue): Promise<void>
  // after
  function claim(issue: Issue, owner: Actor): Promise<ClaimResult>
  ```

- **Pseudocode** for control flow, ordering, and invariants. Strip error
  handling, logging, and types that do not matter to the point:

  ```text
  for each ready issue:
    if owner exists -> resume, never spawn a second worker
    else            -> create thread in fresh worktree
  ```

- **Contract deltas**: before/after payloads as `jsonc` with `// before:` /
  `// after:` comments, trimmed to the keys that changed.
- **Schema/DDL**: the deciding lines only — keys, constraints, the copy/drop
  statements — with `-- + ...` comments for elided columns.
- **Renames/moves**: paired before → after lines or a two-column table.
- **Verbatim code** only for the exact lines a reviewer must see character for
  character: a hash formula, a default value, a guard condition. Never a whole
  function.
- **Query/dataflow topology**: joins and call chains as comment diagrams
  (`a ⨝ b ⨝ c` → `a ⨝ b`).

Every fence has a language tag (`text` for pseudocode). Aim for under ten
lines per snippet; elide with comments rather than pasting whole files. If a
change has no shape worth showing, say it in one plain sentence instead of
forcing a snippet.

## 5. Density rules

- Describe the branch's current state; never narrate the implementation
  process or preserve stale claims from a previous body.
- Every sentence must tell the reviewer something they can't get faster from
  the diff — counts, orderings, invariants, compat windows.
- Tables for behavior deltas, API surfaces, config options; bullets elsewhere;
  no filler headings.

## 6. Verify the result

After the body is applied (by the calling workflow), read it back, and if a PR
lint job posts a verdict (sticky comment or check), confirm it re-ran clean —
required labels present, no blocking errors. A failing lint verdict is not
done: fix the title, body, or labels and re-verify. Report any advisory
warnings, and report plainly if the user asked for a deviation from the lint
contract and what that deviation was.

## Bundled resources

- `assets/pr-body-template.md` — the default skeleton, used only when the repo
  has no PR template of its own.

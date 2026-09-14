---
name: gh-pr-description
description: Write or rewrite a GitHub PR title and description. Use when drafting a PR body, directly or from gh-manage-pr / gh-pr-body. Obeys the repo's PR template and PR-lint CI exactly, explains each change as a Before and After pseudocode pair that a reader outside the codebase can follow, and writes the prose in the plain voice of the bro and technical-writing skills. Does not create, push, or edit PRs itself.
---

# Write a PR description

Write the description so a reviewer who has never opened this repo can say,
after one read, what the branch changes and why. They should not need the
diff for that. The diff is for checking the work, not for finding out what
the work is.

Two rules sit above everything else:

- **The repo's PR contract wins.** If the repo has a PR template or a PR-lint
  job, the description passes every rule it enforces, exactly as configured.
  Do not loosen, skip, or reinterpret a rule because it gets in the way. Do
  not add a heading the template lacks or drop one it requires. Only an
  explicit request from the user changes this, and then the report says what
  was deviated from.
- **Plain voice.** Write the way the `bro`, `technical-writing`, and `unslop`
  skills say to: short sentences, everyday words, one thought per sentence,
  one human talking to another. Section 5 puts the rules that matter for a PR
  in one list. Those skills are user-invoked, so do not call them while
  drafting. Apply their rules yourself.

## 1. Find the repo's rules

Before drafting, collect what the repository enforces.

1. **PR template.** `.github/pull_request_template.md` or
   `.github/PULL_REQUEST_TEMPLATE/`. Its headings are the skeleton. Keep their
   exact names and order. HTML comments in the template say what each section
   is for.
2. **PR lint.** Grep `.github/workflows/` for a job that checks the PR title,
   body, or labels. When the job uses an external action, fetch its source and
   read the actual rules instead of guessing:

   ```bash
   gh api repos/<org>/<actions-repo>/contents/<path>/checks.go --jq .content | base64 -d
   ```

   Write down: title grammar (conventional type, scope, ticket key), required
   body headings, required labels (authorship, risk), and diff-size ceilings
   with their override labels.
3. **Size ceilings.** Compute the non-generated diff size using the lint's own
   exclusion globs. If the diff is over a hard ceiling, add the override label
   the lint defines and justify it in the body: why the change is one unit,
   and why splitting costs more than it saves. The lint's own override label
   counts as compliant. An invented label, or a missing required label, does
   not.
4. **No local contract.** When the repo has neither a template nor a lint job,
   use `assets/pr-body-template.md` and conventional-commit title grammar. Say
   so in the report.

## 2. Lay out the body

Use the repo template's headings when they exist. Otherwise start from
`assets/pr-body-template.md`. Under either skeleton the body carries these
four things, in this order, placed under whichever headings the template
gives you:

- **Why.** The problem in one to three sentences, then the effect of the
  branch in numbers where numbers exist (lines removed, calls collapsed,
  requests saved, ms cut). Link the ticket. The body still has to stand alone
  if the ticket link dies.
- **What changed.** One `###` subsection per point, each written as a Before
  and After pair. Section 3 defines a point and the shape of the pair. Order
  the points by how much a reviewer needs them, not by commit order or file
  order.
- **How to verify.** Numbered steps a reviewer follows to reach the changed
  code: the flag to flip, the URL to open, the command to run, and what they
  should see. For setups too awkward to repeat, write `covered by <test
  file>`. End with the exact gate commands that passed on the final head.
- **Risks and notes.** Only what the reviewer must act on: broken contracts
  and their deploy order, removed behavior, changed logs or metrics, and the
  reason for any override label. Delete the section when there is nothing, or
  write "None" if the template requires the heading.

When the branch touches many files, open **What changed** with one line that
says where to read first.

## 3. Write each point as Before and After

A **point** is one change in behavior a reader would state in one sentence.
"Claims now record who owns them." "The scheduler no longer spawns a second
worker for an issue that already has one." Most branches have one to four. A
point is not a file, a commit, or a function. If two points can only be
understood together, they are one point.

Every point gets the same shape:

````markdown
### <the effect, as a short sentence>

- <what a reader sees differently now>
- <why that is better, or what broke before>
- <what stays the same, if the reader would wonder>

Before:

```text
<pseudocode of how it worked>
```

After:

```text
<pseudocode of how it works now>
```
````

Rules for the bullets and the pseudocode:

- Two or three bullets above the blocks. Each bullet is one plain sentence.
  The first says what changed, the second why. Add a third only when the
  reader would wonder what stayed the same.
- Show the shape, not the code. Keep the branch, the ordering, the call, or
  the field that changed. Strip logging, error handling, imports, and types
  that do not affect the point.
- Ten lines per block or fewer. Elide with a comment (`# ... unchanged`)
  rather than pasting more.
- Use real names from the codebase for functions, fields, flags, and files.
  Invented names make the reader re-map everything against the diff.
- Say what an unfamiliar name is the first time it appears, in a few words:
  `claim(issue)  # marks an issue as taken`.
- Fence with a language tag. `text` for pseudocode. Use the real language only
  when the exact syntax is the point, such as a type signature.
- Make the two blocks line up. Same structure, same order, so the difference
  jumps out. If they cannot line up, the point is probably two points.
- When one side is empty, write it out: `(nothing: the check did not exist)`
  or `(removed)`. Do not drop the block.

Pick the form that shows the point fastest:

| Change | Before and After form |
|---|---|
| control flow, ordering, an invariant | pseudocode in `text` |
| a function or type shape | type signature in the real language |
| a request, response, or config payload | `jsonc` trimmed to the keys that changed |
| a schema | the deciding DDL lines, `-- ...` for the rest |
| a rename or move | a two-column table, or paired lines |
| a query or call chain | a one-line comment diagram: `a -> b -> c` |

If a point truly has no shape (a copy fix, a bumped constant), write the
bullets and skip the blocks. Do not force a snippet.

## 4. Write for someone outside the codebase

The reader knows how to program. They do not know this repo, its nicknames,
or its history. Write for that person.

- **Effect first, mechanism second.** "Retries stop after three attempts
  instead of running forever" before "add `maxAttempts` to `RetryPolicy`".
- **Expand every internal name once.** A subsystem, codename, acronym, or
  ticket key gets a few plain words the first time: "the lease clock (the
  timer that decides when a claim expires)". After that, use the real name.
- **Do not point at context you do not include.** "See the ticket" and "as
  discussed" tell the reader nothing. Put the one sentence of context in the
  body and link the rest.
- **Say what stays the same when the reader would wonder.** "Existing claims
  keep their old owner" saves a question.
- **Tell the reviewer where to look.** Which point carries the risk, which
  file to read first, what kind of feedback you want.
- **Numbers over adjectives.** "Cuts the query from three joins to one" beats
  "makes the query much faster".
- **Describe the branch as it is now.** Never the process of writing it, and
  never a claim left over from an earlier body.
- **Keep it short.** Most bodies fit in 200 to 400 words of prose plus the
  blocks. Past that, cut before you add.

A test before you finish: cover the code blocks and read the prose alone. If
a competent stranger could not say what changed and why, rewrite the prose.
Then cover the prose and read the blocks alone. If the same stranger could
not tell what moved, fix the blocks.

## 5. Voice

Apply these on every sentence. They are the `bro`, `technical-writing`, and
`unslop` rules that matter most in a PR.

- Short sentences with a verb. Split any sentence over about 20 words.
- One thought per sentence.
- Everyday words. "Use", not "utilize". "Do", not "perform". No "leverage",
  "robust", "seamless", "comprehensive", "enhance".
- Say who does what. "The scheduler checks", not "is checked".
- Periods, not semicolons. A new sentence, not an em dash. No parentheses
  except for a plain expansion of a name.
- Keep "only" and "not" next to the word they change.
- One name per thing, everywhere in the body.
- No metaphors, idioms, or invented jargon. If a developer would not say the
  word out loud at a desk, replace it.
- No narration of your own process or reasoning.
- Section headings come from the repo template and are never reworded for
  voice.

Read the body back once as the reviewer. Simplify anything you had to read
twice.

## 6. Title

The title stands alone in `git log` and in a reviewer's inbox. Write it as
one imperative sentence that says what the branch does: "Record the owner on
every claim", not "Claim changes" or "Phase 1". When the PR lint defines
title grammar (conventional type, scope, ticket key), that grammar wins. Fit
the sentence inside it.

## 7. Verify the result

After the calling workflow applies the body, read it back from GitHub. If a
PR lint job posts a verdict (a check or a sticky comment), confirm it re-ran
clean: required labels present, no blocking errors. A failing verdict is not
done. Fix the title, body, or labels and re-verify. Report advisory warnings.
If the user asked for a deviation from the lint contract, say what it was.

## Worked example of one point

### Claims now record who owns them

- Every claim now carries the worker that made it, and `claim` returns whether it won.
- Before, a claim only said an issue was taken, so two workers could pick up the same issue and neither would know.
- Existing claims are untouched. They stay owned by nobody until they expire.

Before:

```text
claim(issue):
  mark issue as taken
  return
```

After:

```text
claim(issue, owner):
  if issue already has an owner -> return { won: false, owner: existing }
  set issue.owner = owner
  return { won: true }
```

## Bundled resources

- `assets/pr-body-template.md`: the default skeleton, used only when the repo
  has no PR template of its own.

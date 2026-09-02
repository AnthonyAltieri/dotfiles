---
name: gh-address-comments
description: Use when the user asks to read/fetch GitHub PR review comments and work through them end-to-end — skeptically validate each comment against the code, push commits fixing confirmed issues, reply to/answer the review threads with evidence and commit links, and resolve the threads. Triggers include "handle comments", "handle PR comments", "address PR comments", "read PR comments", "push fixes", "answer threads", "respond to review", "resolve comments/threads".
metadata:
  short-description: Validate, fix, answer, and resolve PR review threads
---

# PR Comment Handler

Fetch the review threads on the current branch's PR and drive every unresolved thread to closure with an evidence-first loop. The core stance: **a review comment is an unproven claim, and the code under review is not presumed correct either.** Reviewers misread diffs; authors ship bugs. Neither gets the benefit of the doubt — proof does. Every thread therefore ends in exactly one of two states:

- **Confirmed** — proof shows the reviewer is right: fix it, commit, push, reply with a link to the fix, resolve.
- **Refuted** — a genuine attempt to prove the claim came up empty: reply documenting what was tried and why the claim doesn't hold, resolve.

Never resolve a thread silently, never reply without evidence, and never "fix" something just to appease a comment you could not confirm.

Use the `gh` CLI for all GitHub reads and top-level comments, and the Rust helper commands (on `PATH` via the active Nix profile) for review-thread replies and resolution. If no PR exists for the current branch, report this and stop.

## Inputs

- `repo`: repository path (default `.`)
- `pr`: PR number or URL (optional; defaults to current branch PR)
- optional flags: `--all` / `--include-resolved` to include resolved threads (default: unresolved only)

## Workflow

### Phase 1 — Gather the comments and context

1. Pull PR context:
   - `gh pr view --json number,url,title,body,baseRefName,headRefName,reviews,state,statusCheckRollup`
   - `gh pr diff`
   - `gh pr checks`
2. Fetch review threads:
   - Preferred: `fetch-comments --format json` for full conversation/review/thread data.
   - For large review sets, run `fetch-comments --format compact | summarize-threads` first so grouped metadata arrives before individual thread bodies.
   - Manual fallback: `gh api graphql` query for `reviewThreads`, `reviews`, and thread comments. Capture each thread's `id` — replies and resolution need it.
3. Scope to unresolved threads unless the user asks for a full audit. Note outdated threads (the code may have moved) but do not skip them — an outdated anchor does not make the underlying claim wrong.

### Phase 2 — Interrogate each claim (skeptical validation)

Work thread by thread, grouped by file. For each thread:

1. **Restate the claim precisely.** What failure is the reviewer actually asserting — wrong value, missed edge case, race, leak, security hole, style drift? A claim you can't state crisply, you can't test.
2. **Hunt for proof, not for agreement.** Read the actual code and its callers, not just the diff hunk (`git diff <baseRefName>...HEAD -- <filepath>`, then the surrounding file). Trace the data flow the comment implicates. Where feasible, force the question empirically: write a small repro, run the existing test that should catch it, or evaluate the exact input the reviewer worries about.
3. **Interrogate the code with the same suspicion.** While in the area, check whether the code has the bug the reviewer described *or a neighboring one* — the comment is often a symptom of a real problem one line away, and the same defect frequently repeats in sibling code paths across the branch diff.
4. **Reach a verdict backed by artifacts** — a failing repro, a traced code path, a spec/doc citation, a passing test. "Seems fine" and "reviewer is probably right" are both non-verdicts; keep digging until the evidence points one way.

Classify the outcome: **Confirmed** (proof the comment is correct, or that a closely related defect exists), **Refuted** (a real attempt to prove it failed), or **Question** (the reviewer is asking, not asserting — answer it with evidence from the code, then resolve like a refutation).

### Phase 3 — Act on the verdict

**Confirmed → fix, push, reply with the receipt, resolve:**

1. Apply a focused fix — root cause, not symptom. One commit per thread (or per cohesive thread group), conventional commit type, with the PR comment URL in the commit body.
2. Run targeted lint/tests on the touched files before committing.
3. **Push before replying** — links to unpushed commits 404.
4. Reply on the thread explaining what was wrong, how the commit addresses it, and link the fix. Get `owner/repo` from `gh repo view --json nameWithOwner -q .nameWithOwner`, then link:
   - the commit: `https://github.com/<owner>/<repo>/commit/<sha>`
   - or, when a specific line tells the story better, the line at that commit: `https://github.com/<owner>/<repo>/blob/<sha>/<path>#L<line>`
   - `create-thread-reply --thread-id "<thread_id>" --body "FROM <AGENT>: Confirmed and fixed in <link> — <what was wrong and how the fix addresses it>."`
5. Resolve: `resolve-thread --thread-id "<thread_id>"`

**Refuted → reply with the investigation, resolve:**

1. Reply on the thread stating (a) the claim as understood, (b) what was checked — the code paths traced, tests run, inputs tried, (c) why the evidence says the code is correct as written.
   - `create-thread-reply --thread-id "<thread_id>" --body "FROM <AGENT>: Investigated — <claim>. Checked <evidence gathered>. <Why the code is correct as written>."`
2. Resolve: `resolve-thread --thread-id "<thread_id>"`. The written investigation is what earns the resolution — the reviewer can reopen if they disagree with the evidence.

**Question → answer, resolve:** reply with the evidence-backed answer (link the relevant code) and resolve.

### Phase 4 — Verify and report

1. Re-run focused checks/tests relevant to all touched files; confirm `gh pr checks` isn't newly broken.
2. Report: confirmed-and-fixed threads (with commits), refuted threads (with the evidence summary), answered questions, and anything deferred with the reason. Update the PR title or description only when the user explicitly requests that separate operation.

## Gotchas

- Keep GraphQL fetching in `gh`; the helpers only post-process saved thread metadata.
- For a top-level comment outside any review thread, use `gh pr comment [<pr>] --body "🤖 FROM <AGENT>: ..."`; add `--attach <file>` (gh 2.99.0+) when a screenshot or recording is the evidence.
- `create-thread-reply` expects a review thread ID, not a comment ID.
- `create-thread-reply` automatically prefixes the final body with `🤖 `; keep the reply text itself agent-specific — replace `<AGENT>` with the agent actually running (`FROM CLAUDE:` from Claude, `FROM CODEX:` from Codex).
- `resolve-thread` is idempotent; already-resolved threads won't error.
- Always reply **before** resolving — a resolution with no explanation reads as dismissal.
- If any helper command is missing, reapply the profile so the packaged helpers are rebuilt and activated.
- If `gh` auth fails, ask the user to run `gh auth login`, then retry.

## Output Format

1. Code Examples — before/after snippets grouped by file
2. Summary Table — file, line, reviewer, claim, verdict (confirmed/refuted/question), evidence, commit link (if any)

## Bundled Resources

- `fetch-comments --format compact` - Emits flattened tab-separated thread metadata that pipes cleanly into `summarize-threads`.
- `summarize-threads` - Groups flattened thread metadata by file, reviewer, and resolution state into compact JSON.
- `create-thread-reply` - Creates a review-thread reply.
- `resolve-thread` - Resolves a review thread by thread ID.

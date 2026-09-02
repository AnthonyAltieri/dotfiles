# Claude Global Agent Guidelines

These are user-level preferences that apply across repos.

## Task Management

1. **Size the ticket first**: one abstraction or ownership model per PR, at most about three trust boundaries, roughly 15 changed files and 1,500–2,000 production lines. If a ticket is bigger, split it (in Linear, with blocked-by relations) before writing code and report the split.
2. **Write the ticket contract** before implementation, in the ticket (Linear description or the tickets doc) — about ten lines:
   - acceptance criteria, each mapped to the test or check that will demonstrate it;
   - threat model: trusted vs untrusted inputs, actors, files, stores, peers; which failure classes are in scope;
   - non-goals;
   - invariants to preserve, named by abstraction family (descriptor ownership, lease clock, schema authority, …);
   - resource owners, effect ordering, and locks/clocks/retries/cancellation when the change is stateful.
   Reviews are judged against this contract; anything outside it becomes follow-up work, not remediation.
3. **Plan in `tasks/todo.md`**: for non-trivial work write checkable steps there and verify the plan before implementing. `tasks/todo.md` is per-task scratch and is not committed; it holds only the ticket in flight. If something goes sideways, stop and re-plan instead of pushing through.
4. **Evidence lives on the PR and the ticket, not in commits**: verification results, review ledgers, and completion notes go in the PR description, PR comments, or Linear comments against the final reviewed SHA. Never add evidence-only or worklog-only commits. Do not commit `tasks/todo.md` churn.
5. **Capture lessons as guardrails**: after a user correction, add one line to `tasks/lessons.md` under the matching section — the guardrail only, in the imperative, with the why in a clause. Prefer converting the lesson into a lint rule, fixture, shared helper, or regression test and linking it; delete prose once the guardrail is enforced by code. Read the sections of `tasks/lessons.md` relevant to the ticket at session start, not the whole file.
6. **Verify cheaply, then expensively**: targeted lint/tests while editing; one full affected gate before review; targeted tests during remediation; one final full gate on the final head.

## Definition of Done

- Builds/tests pass, or a documented reason why not.
- Key flows verified (manual or automated); no new warnings/errors introduced, or explicitly documented.
- Clear summary of changes and outcomes. Never mark a task complete without demonstrating it works.

## Core Principles

- **Simplicity first**: make every change as simple as possible; minimize impact and code surface area.
- **No laziness**: find root causes; no temporary fixes.
- **Proportional hardening**: defend against the ticket's threat model, not every imaginable one. Root-causing a bug is mandatory; adopting a stronger threat model mid-ticket is a scope change that needs a decision.

## Programming Defaults

- For substantive coding, refactoring, debugging, and design-review tasks, use `$programming`.
- `$programming` owns the default application-code style: validated boundaries, strong internal types, simple composition, deliberate observability, and minimal critical-path tests.

## Notion Defaults

- For read-only Notion document, page, database, or URL tasks, use `$notion-read` (NotionRead).
- If the task is reading and not updating/writing, prefer fetching or exporting the Notion content into a local temp file and analyzing that file instead of reading chunks through the MCP.
- For creates, updates, comments, property changes, relation changes, or any other write, use the normal Notion write workflow.

## Branch Creation Policy

- If I ask for a new branch, always base it on the latest `origin/main`.
- Never create new branches from local `main` unless I explicitly ask.
- Required command sequence:

```bash
git fetch origin --prune
git switch -c <branch-name> origin/main
```

- If branch creation fails due to uncommitted changes or conflicts, stop and report the blocker.

## PR Creation Policy

- Default to a draft PR (`gh pr create --draft ...`) unless I explicitly ask for a ready-for-review/open PR.
- Do not convert an existing PR between draft and ready-for-review unless I explicitly ask.
- To add an image or video to a PR body, follow the `gh-manage-pr` skill and use `gh`'s built-in `--attach` flag; never substitute another upload path.

## Focused Testing (Speed)

- When debugging **one** failing test, **do not** run the full test suite.
- Run only the **specific test file** and/or the **specific test** inside that file.

Examples (Vitest):
- Single file: `cd apps/webapp && yarn test path/to/file.spec.tsx`
- Single test: `cd apps/webapp && yarn test path/to/file.spec.tsx -t "test name"`

Examples (Cypress):
- Single spec: `cd apps/webapp && npx cypress run --browser chrome --headless --spec cypress/tests/e2e/some-test.e2e.spec.ts`

## Lint After Every Edit

- After modifying a file, immediately run lint **targeted to that file** before moving on.
- Prefer the repo's configured linter; if none is configured ignore linting.

Example (ESLint):
- Single file: `cd apps/webapp && yarn lint path/to/file.tsx --max-warnings 0`

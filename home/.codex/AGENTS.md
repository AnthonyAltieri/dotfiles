# Codex Global Agent Guidelines

These are user-level preferences that apply across repos.

## Task Management

1. **Plan first**: for non-trivial work (3+ steps, multiple files, or architectural decisions), write the plan to `tasks/todo.md` with checkable items and verify it before implementing. If something goes sideways, stop and re-plan instead of pushing through.
2. **Track progress**: mark items complete as you go and add a review section to `tasks/todo.md` when done.
3. **Capture lessons**: after any correction from the user, update `tasks/lessons.md` with what went wrong, why it happened, and the prevention rule. Review relevant lessons at session start.

## Definition of Done

- Builds/tests pass, or a documented reason why not.
- Key flows verified (manual or automated); no new warnings/errors introduced, or explicitly documented.
- Clear summary of changes and outcomes. Never mark a task complete without demonstrating it works.

## Core Principles

- **Simplicity first**: make every change as simple as possible; minimize impact and code surface area.
- **No laziness**: find root causes; no temporary fixes.

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
- To add an image to a PR body, follow the `gh-pr-body` skill and its prompt-gated `gh-pr-image` helper; never bypass its approval gate or substitute another upload path.

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

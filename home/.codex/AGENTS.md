# Codex Global Agent Guidelines

These are user-level preferences that apply across repos.

## Workflow Orchestration
### 1) Plan Mode Default
Use planning before doing work when the task is non-trivial.
- Enter plan mode for **any** non-trivial task (3+ steps, multiple files, or architectural decisions).
- If something goes sideways: **stop**, re-plan immediately, and proceed with the revised plan (do not “push through”).
- Use plan mode for **verification steps**, not just for building.
- Write detailed specs up front to reduce ambiguity and rework.
**Plan should include:**
- Goal + success criteria
- Assumptions / constraints
- Steps (checklist)
- Risks / edge cases
- Verification plan
---
### 2) Subagent Strategy
Use subagents to keep the main thread focused and the context window clean.
- Use subagents liberally for research, exploration, and parallel analysis.
- For complex problems, delegate pieces and/or “throw more compute” at it via multiple subagents.
- Keep **one task per subagent** to maintain focus and clear outcomes.
**Good subagent tasks:**
- “Scan logs/tests and summarize failure causes.”
- “Propose 2–3 architectural options with tradeoffs.”
- “Draft a migration plan and verification checklist.”
---
### 3) Self-Improvement Loop
Treat mistakes as inputs to a repeatable improvement process.
- After **any** correction from the user, update `tasks/lessons.md` with:
  - what went wrong
  - why it happened
  - the prevention rule / guardrail
- Write rules for yourself that prevent the same mistake.
- Ruthlessly iterate on these lessons until the mistake rate drops.
- Review relevant lessons at session start for the project you’re working on.
---
### 4) Verification Before Done
Never consider work finished until it is demonstrated correct.
- Do not mark a task complete without proving it works.
- If you changed behavior, **diff** main vs. your changes (or before vs. after) when relevant.
- Ask: **“Would a staff engineer approve this?”**
- Run tests, check logs, and demonstrate correctness.
**Definition of Done (minimum):**
- Builds/tests pass (or a documented reason why not)
- Key flows verified (manual or automated)
- No new warnings/errors introduced (or explicitly documented)
- Clear summary of changes and outcomes
---
### 5) Demand Elegance (Balanced)
Prefer clean solutions without over-engineering.
- For non-trivial changes, pause and ask: **“Is there a more elegant way?”**
- If a fix feels hacky: implement the solution you’d choose **knowing everything you know now**.
- Skip “elegance push” for simple, obvious fixes—don’t over-engineer.
- Challenge your own work before presenting it.
---
### 6) Autonomous Bug Fixing
When given a bug report, fix it end-to-end.
- Don’t ask for hand-holding—investigate and resolve.
- Start from evidence: logs, errors, failing tests.
- Require **zero** context switching from the user.
- Fix failing CI tests without being told how.
**Bug-fix loop:**
1. Reproduce (or isolate) the failure
2. Identify root cause
3. Implement the minimal correct fix
4. Add/adjust tests where appropriate
5. Verify locally and in CI signals
6. Document what changed and why
---
## Task Management
1. **Plan First**: Write the plan to `tasks/todo.md` with checkable items.
2. **Verify Plan**: Check the plan before starting implementation.
3. **Track Progress**: Mark items complete as you go.
4. **Explain Changes**: Provide a high-level summary at each step.
5. **Document Results**: Add a review section to `tasks/todo.md`.
6. **Capture Lessons**: Update `tasks/lessons.md` after corrections.
---
## Core Principles
- **Simplicity First**: Make every change as simple as possible. Minimize impact and code surface area.
- **No Laziness**: Find root causes. No temporary fixes. Hold to senior developer standards.
- **Minimal Impact**: Touch only what’s necessary. Avoid introducing new bugs.
---
## Branch Creation Policy

- If I ask for a new branch, always base it on the latest `origin/main`.
- Never create new branches from local `main` unless I explicitly ask.
- Required command sequence:

```bash
git fetch origin --prune
git switch -c <branch-name> origin/main
```

- If branch creation fails due to uncommitted changes or conflicts, stop and report the blocker.
---
## Focused Testing (Speed)
- When debugging **one** failing test, **do not** run the full test suite.
- Run only the **specific test file** and/or the **specific test** inside that file.

Examples (Vitest):
- Single file: `cd apps/webapp && yarn test path/to/file.spec.tsx`
- Single test: `cd apps/webapp && yarn test path/to/file.spec.tsx -t "test name"`

Examples (Cypress):
- Single spec: `cd apps/webapp && npx cypress run --browser chrome --headless --spec cypress/tests/e2e/some-test.e2e.spec.ts`
---
## Lint After Every Edit
- After modifying a file, immediately run lint **targeted to that file** before moving on.
- Prefer the repo's configured linter; if none is configured ignore linting

Examples (ESLint):
- Single file: `cd apps/webapp && yarn lint path/to/file.tsx --max-warnings 0`

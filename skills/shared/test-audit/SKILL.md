---
name: test-audit
description: Apply the testing policy when writing, changing, reviewing, or auditing tests. Use to decide whether a test should exist, which tier it belongs to, how to keep it deterministic and reasonably fast, and to audit an existing suite for worthwhile improvements; skip for non-test code.
---

# Test Audit

Tests exist to catch regressions cheaply. Every test costs wall-clock time on every run forever; it must earn that. This skill is the policy and the audit procedure that enforces it. Follow the caller's planning, task-tracking, verification, and git instructions.

## Policy

**Runtime targets (not hard limits):** aim for the whole unit suite to run as close to 10s and the whole e2e suite as close to 60s as reasonably practical; faster suites are welcome. Exceeding these targets alone is not a CI failure or a reason to remove useful coverage.

**Proportionate optimization:** prioritize improvements expected to reduce the affected whole suite's runtime by at least 10%. Do not spend significant time chasing smaller gains; quick, low-risk improvements are fine. Preserve regression coverage and stop when further optimization would take disproportionate effort. Never add retries or bump timeouts to disguise slow or flaky tests.

**Run the smallest test that proves the point.** While iterating, run one test or one file, never the whole suite. By default, run the full suite exactly twice: once before opening or updating the PR, once on the final head. In default mode, if nothing smaller than the suite can prove a change, the change is too big or the tests overlap; fix that first. Honor an explicitly selected verification mode as described below.

**Affected-only verification (`--min-tests`).** When the user or the caller's brief selects this mode, replace both full-suite gates with the smallest useful tests for changed behavior and affected dependents. Select cases, files, or targets from the diff and its effects on callers and user flows, including relevant regression tests. Re-evaluate the selection after code or base changes and verify the final head within that scope. Do not run whole suites for verification, review, or timing audits. If affected tests cannot be selected, report the coverage gap and use available focused checks instead of falling back to the full suite. Report commands, durations, coverage rationale, and gaps; do not imply full-suite verification. Required provider CI checks still apply.

**Deterministic, always.** A test passes or fails for the same reason every run. No sleeps, no polling loops, no retries, no timeouts-as-synchronization, no reliance on wall-clock, randomness, ordering, or leftover state. Wait only on an explicit signal (promise, event, job completion) that the code under test emits. If a test needs a retry to pass, the test or the code is wrong; fix that.

**Two tiers only.** Unit or e2e. No "integration" middle tier.

**Unit tests**

- Test the public API of a module, not its internals. A refactor that preserves behavior must not break tests.
- One behavior, one test. Do not re-cover a behavior another test already asserts. Prefer one parametrized/table test over N near-duplicates.
- Do not write a test for what the type checker can prove. Encode invariants in types first: parse at boundaries (Zod / Pydantic), make illegal states unrepresentable, exhaustive unions. Type check is part of the test gate.
- Mock only process boundaries (network, clock, fs, db). Never mock our own modules. Inject the clock; never read real time.
- Must pass in random order and in parallel.
- Every bug fix ships exactly one regression test that failed before the fix.
- No tests for getters, config, wiring, or framework behavior. Coverage is not a target.
- No snapshot tests except for serialized wire contracts.

**E2e tests**

- Purpose: ossify key expected behavior and critical failure cases. Nothing else.
- One happy path per critical user flow, plus the failure modes that would page someone. If it wouldn't page, it isn't e2e.
- Real dependencies (disposable containers), no mocks. Each test owns and tears down its own state.
- A flaky e2e test is fixed or deleted the same day. Never `retry`, never `skip`.

**Every test answers:** what bug does this catch? If you can't say, don't write it.

## When Writing Or Changing Tests

1. Name the bug the test catches. No answer means no test.
2. Pick the tier. Unit for a module's public behavior; e2e only for a critical flow or a failure that would page. Anything in between is either a unit test against a public API or nothing.
3. Check for overlap. Search the suite for an existing test that already asserts the behavior; extend a table test before adding a case.
4. Check what types already prove. Prefer tightening a schema or union over asserting the same invariant at runtime.
5. Isolate: inject the clock, mock only process boundaries, own and tear down state, wait on emitted signals only.
6. Run just the new or changed test, then the file. At the two PR gates, follow the selected verification mode: full suites by default, affected tests only with `--min-tests`.

## When Auditing A Suite

Report runtime observations and policy violations in this order, with the relevant file, test name, and policy where applicable. During review or audit, report; do not change tests unless asked.

With `--min-tests`, audit the changed tests and affected behavior using scoped check results and any existing timing evidence. Do not launch whole suites to measure runtime targets or treat missing full-suite evidence as a violation. The suite-wide runtime measurement below applies to the default mode.

1. **Runtime**: measure the unit and e2e suites against the 10s and 60s targets. If either is above target, identify the main bottlenecks and estimate potential gains as a percentage of that whole suite's runtime. Prioritize worthwhile improvements, especially gains of 10% or more; do not spend significant time on smaller gains. Accept and explain an above-target runtime when further work would be disproportionate or would sacrifice useful coverage. Being above target alone is not a policy violation.
2. **Nondeterminism**: sleeps, polling loops, retries, `skip`, timeouts used as synchronization, real clock or randomness, order or shared-state dependence.
3. **Wrong tier**: tests labelled integration, unit tests hitting real dependencies, e2e tests covering flows that would not page.
4. **Internals and mocks**: tests reaching past the public API, mocks of our own modules, snapshot tests that are not wire contracts.
5. **Redundancy**: multiple tests asserting one behavior, near-duplicate cases that belong in one table test, tests of getters, config, wiring, framework behavior, or anything the type checker already proves.
6. **Missing regression tests**: bug fixes in scope without exactly one test that failed before the fix.

For each finding, state the action: optimize, accept the runtime with a reason, delete, merge into a named test, move tier, or rewrite. For test changes, state what bug the surviving test catches.

## Run Commands

Use the repository's configured runners. Run a single test or file while iterating. At PR gates, run the full unit suite, full e2e suite, and type checker by default; with `--min-tests`, select affected test cases, files, or targets and relevant lint/type checks. If the repository has no runner for a tier or cannot select affected tests, report that limitation instead of inventing a runner or expanding to a whole-suite test command.

---
name: gh-fix-ci
description: Debug or fix failing GitHub PR checks; inspect checks/logs with gh, classify root causes, and propose focused fixes.
metadata:
  short-description: Debug failing PR checks
---

# PR Checks Review

Use the `gh` CLI to analyze CI status for the current branch PR.

The active Nix profile puts the Rust helper commands on `PATH`, so call them directly.

If no PR exists for the current branch, report this and stop.

## Inputs

- `repo`: repository path (default `.`)
- `pr`: PR number or URL (optional; default current branch PR)
- `gh` authentication with repo/workflow access

## Quick start

1. Fetch failing checks with `gh` via the bundled Rust helper.
   - `inspect-pr-checks --repo "." --json`
2. Prefer a direct helper pipeline when the raw logs are too large to hand directly to the model.
   - `gh run view <run_id> --log-failed | classify-ci-log`
3. If you already saved a log locally, classify it directly.
   - `classify-ci-log /tmp/failed.log`
4. Summarize failing logs before reading full job output when the raw logs are large.

## Workflow

1. Gather PR and check context.
   - `gh pr view --json number,url,title,baseRefName,headRefName,statusCheckRollup,commits`
   - `gh pr checks --json name,state,startedAt,completedAt,bucket,description,link`
   - If all checks pass, report success with a brief summary and stop.
2. Identify failed checks and collect logs.
   - Preferred quick path:
     - `inspect-pr-checks --repo "." --pr "<number-or-url>"`
     - Add `--json` for structured summaries.
     - Use `gh run view <run_id> --log-failed | classify-ci-log` when the raw logs are large and you need a local classifier to shrink the context without introducing redirection-heavy wrappers.
   - Manual deep dive:
     - `gh run view <run_id> --log-failed`
     - `gh run view <run_id> --json jobs --jq '.jobs[] | {name, status, conclusion, steps}'`
     - `gh run view <run_id> --job=<job_id> --log`
3. Handle external CI providers.
   - If a failed check URL is not GitHub Actions, treat it as external.
   - For CircleCI jobs (identified by `circleci` in the name or details URL), use CircleCI MCP if available:
     - Prefer the project slug plus branch flow if you have them.
     - Pull failing job logs and test metadata before classifying the failure.
   - For other external providers without available tooling, report the details URL for manual investigation.
4. Gather additional context for root-cause analysis.
   - `gh pr diff`
   - `git show HEAD --stat`
   - Fetch workflow files or artifacts if needed:
     - `gh api repos/<owner>/<repo>/contents/.github/workflows/<workflow_file> --jq '.content' | base64 -d`
     - `gh run view <run_id> --json artifacts`
     - `gh run download <run_id> -n <artifact_name>`
5. Analyze and classify each failure.
   - Build: compilation/bundling/type failures
   - Test: assertion/integration/snapshot failures
   - Lint: style/static-analysis/type-policy failures
   - Environment: timeout/OOM/network/flaky CI infrastructure
   - Config: workflow/toolchain/secrets/path misconfiguration
6. Correlate with PR changes.
   - Parse exact error and file/line.
   - Determine whether failure is introduced by this PR.
   - Check for pre-existing patterns:
     - `gh run list --branch=main --limit=5`
7. Recommend next action per failure.
   - Environment/flaky: recommend rerun (`gh run rerun <run_id> --failed`)
   - Config: identify workflow/config changes needed
   - Code issue: explain root cause and propose concrete fix
   - Pre-existing failure: call out as not introduced by this PR
8. Before implementation, request explicit user approval for code changes when the fix is non-trivial or ambiguous.
9. After implementation, summarize changed files and validation, then re-check relevant statuses.
10. Update PR description.
    - After fixes are committed and verified, update the PR description to reflect the **current state** of the PR (not the history of steps taken).
    - Follow the **gh-manage-pr** skill workflow to regenerate and apply the updated description.

## Output Format

1. Status Overview
   - Passed / Failed / Skipped checks
2. Failure Analysis
   - Error snippet, root cause, PR correlation
3. Code Examples
   - Key before/after snippets grouped by failure type
4. Summary Table
   - Check, type, error, root cause, resolution
5. Recommended Actions
   - Prioritized next steps

## Bundled Resources

### `inspect-pr-checks`

Use for fast inspection of failing checks and extraction of actionable log snippets.

Examples:
- `inspect-pr-checks --repo "."`
- `inspect-pr-checks --repo "." --pr "123" --json`
- `inspect-pr-checks --repo "." --pr "https://github.com/org/repo/pull/123" --json`
- `inspect-pr-checks --repo "." --max-lines 200 --context 40`

### `classify-ci-log`

Classifies raw CI log text into `build`, `test`, `lint`, `config`, or `environment`, and emits compact JSON snippets around the highest-signal failures.

## Gotchas

- Do not assume the first error line is the root cause; use the helper output to identify repeated failure markers before deciding.
- Keep GitHub fetching and auth on `gh`; the Rust helpers should only process saved logs locally.
- When a failure looks environmental, cross-check recent `main` runs before proposing code changes.
- Large logs should be summarized first; only pull the exact failing job section back into the prompt when needed.
- If either helper command is missing, reapply the profile so the packaged helpers are rebuilt and activated.

## Notes

- If `gh` auth fails, ask user to run `gh auth login`, then retry.
- For external CI providers without available tooling, report the URL for manual investigation.

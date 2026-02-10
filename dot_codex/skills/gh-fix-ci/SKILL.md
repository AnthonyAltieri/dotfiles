---
name: gh-fix-ci
description: Use when a user asks to debug or fix failing GitHub PR checks; inspect checks/logs with gh, classify root causes, and propose focused fixes. Prefer GitHub Actions and report external CI URLs when direct tooling is unavailable.
---

# PR Checks Review

Use the `gh` CLI to analyze CI status for the current branch PR.

If no PR exists for the current branch, report this and stop.

## Inputs

- `repo`: repository path (default `.`)
- `pr`: PR number or URL (optional; default current branch PR)
- `gh` authentication with repo/workflow access

## Workflow

1. Gather PR and check context.
   - `gh pr view --json number,url,title,baseRefName,headRefName,statusCheckRollup,commits`
   - `gh pr checks --json name,state,startedAt,completedAt,bucket,description,link`
   - If all checks pass, report success with a brief summary and stop.
2. Identify failed checks and collect logs.
   - Preferred quick path:
     - `python "<path-to-skill>/scripts/inspect_pr_checks.py" --repo "." --pr "<number-or-url>"`
     - Add `--json` for structured summaries.
   - Manual deep dive:
     - `gh run view <run_id> --log-failed`
     - `gh run view <run_id> --json jobs --jq '.jobs[] | {name, status, conclusion, steps}'`
     - `gh run view <run_id> --job=<job_id> --log`
3. Handle external CI providers.
   - If a failed check URL is not GitHub Actions, treat it as external.
   - If CircleCI tooling is available in the environment, use it for deeper details.
   - Otherwise report the details URL and classify it as out-of-scope for direct retrieval.
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

### `scripts/inspect_pr_checks.py`

Use for fast inspection of failing checks and extraction of actionable log snippets.

Examples:
- `python "<path-to-skill>/scripts/inspect_pr_checks.py" --repo "."`
- `python "<path-to-skill>/scripts/inspect_pr_checks.py" --repo "." --pr "123" --json`
- `python "<path-to-skill>/scripts/inspect_pr_checks.py" --repo "." --pr "123"`
- `python "<path-to-skill>/scripts/inspect_pr_checks.py" --repo "." --pr "https://github.com/org/repo/pull/123" --json`
- `python "<path-to-skill>/scripts/inspect_pr_checks.py" --repo "." --max-lines 200 --context 40`

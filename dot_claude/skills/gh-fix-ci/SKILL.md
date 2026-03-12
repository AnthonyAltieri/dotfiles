---
name: gh-fix-ci
description: Debug or fix failing GitHub PR checks; inspect checks/logs with gh, classify root causes, and propose focused fixes.
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
   - `gh run view <run_id> --log-failed`
   - `gh run view <run_id> --json jobs --jq '.jobs[] | {name, status, conclusion, steps}'`
   - `gh run view <run_id> --job=<job_id> --log`
3. Handle external CI providers.
   - If a failed check URL is not GitHub Actions, treat it as external.
   - For CircleCI jobs (identified by `circleci` in the name or details URL), use CircleCI MCP if available:
     1. `mcp: circleci_get_project {project_slug}` (slug format: `gh/{org}/{repo}`)
     2. `mcp: circleci_list_pipelines {project_slug}`
     3. `mcp: circleci_get_pipeline_workflows {pipeline_id}`
     4. `mcp: circleci_get_workflow_jobs {workflow_id}`
     5. `mcp: circleci_get_job_details {project_slug} {job_number}` and `circleci_get_job_logs`
     6. `mcp: circleci_get_job_tests {project_slug} {job_number}`
     7. `mcp: circleci_get_job_artifacts {project_slug} {job_number}`
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

## Notes

- If `gh` auth fails, ask user to run `gh auth login`, then retry.
- For external CI providers without available tooling, report the URL for manual investigation.

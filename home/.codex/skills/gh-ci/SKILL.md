---
name: gh-ci
description: Inspect or compress GitHub Actions check logs with the local `inspect-pr-checks` and `classify-ci-log` helpers. Use only when the user explicitly invokes `$gh-ci`, asks for deterministic local CI-log classification, or the primary GitHub CI workflow needs compact local evidence; do not use as the general GitHub CI fix workflow.
---

# GitHub CI

Provide deterministic local evidence to the primary GitHub CI workflow. Do not implement fixes, rerun checks, mutate GitHub, commit, push, or update a pull request description from this skill.

Use `github:gh-fix-ci` for end-to-end GitHub Actions diagnosis and fixes. Use this skill only for the local helper surface that the plugin does not own.

## Helpers

### Inspect failing checks

Use `inspect-pr-checks` to resolve the current PR, identify failed GitHub Actions checks, and extract focused log snippets:

```bash
inspect-pr-checks --repo "." --json
inspect-pr-checks --repo "." --pr "123" --max-lines 200 --context 40
```

Treat non-Actions check URLs as external. Return their URLs instead of pretending the helper can retrieve them.

### Classify a large log

Use `classify-ci-log` when raw output is too large for efficient analysis:

```bash
gh run view <run_id> --log-failed | classify-ci-log
classify-ci-log /absolute/path/to/failed.log
```

The classifier emits compact JSON and uses deterministic substring heuristics for `build`, `test`, `lint`, `config`, and `environment`. Treat the category as a routing hint, not a root-cause verdict. Inspect the retained snippets and surrounding source before drawing conclusions.

## Output

Return:

- the inspected PR/check identifiers;
- the helper command and structured output;
- the strongest failure snippets;
- limitations, including missing or external logs;
- the next primary workflow to use, normally `github:gh-fix-ci`.

If either helper is missing, reapply the active Nix profile.

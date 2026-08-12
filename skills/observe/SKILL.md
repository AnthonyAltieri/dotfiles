---
name: observe
description: Investigate Laurel metrics, logs, traces, and other telemetry with read-only Observe CLI and OPAL queries. Use for bounded incident diagnosis, service or infrastructure health checks, telemetry searches, and evidence-backed summaries; do not use for Observe administration or data mutation.
---

# Observe

Use the PATH command `observe` for read-only diagnosis. Treat every dataset name, field,
schema, and infrastructure identifier in bundled references as a discovery hint, not current
truth.

## Safety contract

- Run only read operations: `list`, `get`, and bounded `query` commands.
- Do not perform mutations, access-control changes, or object management.
- Never print, parse, copy, summarize, or pass the Observe config or token on a command line.
- Never request or expose a password. If setup is required, have the user run the CLI's SSO
  login interactively.
- Start with the smallest useful time window and result limit. Expand one dimension at a time.
- Do not write large telemetry exports into the repository. Use a protected temporary file only
  when local analysis requires one, then remove it.

## Preflight

1. Verify the binary without assuming an install location:

   ```bash
   command -v observe
   ```

2. Validate configuration and authentication with a harmless read:

   ```bash
   observe list workspace >/dev/null
   ```

Treat the CLI read as authoritative because Observe may use `OBSERVE_CONFIG`, `--config`, or its
own default path. If it fails, report the failure without dumping debug configuration. When the user
asks for authentication help, instruct them to use `observe login --help` and an interactive
SSO login; do not initiate browser login or accept credentials.

## Diagnostic workflow

1. Restate the service/system, environment, symptom, and time range. Default an unspecified
   incident window to the last 15 minutes.
2. Discover candidate datasets live with `observe list dataset [filter]`.
3. Sample the chosen dataset before filtering. Start with `limit 5`; if it is a Resource
   dataset, use `topk 5`. Inspect only fields needed for the question.
4. Confirm exact field names and value shapes from that sample. Never copy a catalog query
   before this step.
5. Run a bounded query, usually 15 minutes and at most 50 rows. Aggregate before retrieving
   detailed records.
6. Expand time, rows, or dataset scope only when the prior result justifies it. State the
   reason for each expansion.
7. Corroborate consequential conclusions with a second signal when available, such as logs plus
   traces or metrics plus deployment events.
8. Report the query scope, datasets, key evidence, uncertainty, and the next discriminating
   check. Distinguish zero matches from proof that an event did not occur.

Minimal discovery and sample:

```bash
observe list dataset "<service-or-signal>"
observe query -i '<LIVE_DATASET>' -q 'limit 5' -r 15m --json
```

## Conditional references

- Read [references/cli-and-opal.md](references/cli-and-opal.md) only when command syntax, output
  formats, time windows, or OPAL construction is needed.
- Read [references/investigation-playbooks.md](references/investigation-playbooks.md) only for a
  multi-signal incident, latency, error, or resource investigation.
- Read [references/laurel.md](references/laurel.md) only for Laurel dataset candidates, field
  gotchas, cluster hints, or organization-specific examples. Perform its live discovery gate
  before using any listed name or field.

# Observe CLI and OPAL

Use this reference only after the read-only and bounded-query contract in `../SKILL.md`.

## Discover commands and datasets

Prefer the installed CLI's help over remembered flags:

```bash
observe --help
observe query --help
observe list dataset
observe list dataset "<substring>"
observe get dataset <LIVE_DATASET_ID>
```

Use `list` and `get` only for dataset and workspace discovery; they do not authorize broader
object management.

## Query shape

```bash
observe query -i '<LIVE_DATASET>' -q '<OPAL>' -r 15m --json
```

Confirm flags with `observe query --help`. Common forms are:

- `-i` / `--input`: live dataset ID or qualified name.
- `-q` / `--query`: OPAL query.
- `-r` / `--relative`: relative window such as `15m`, `4h`, or `1d`.
- `-s` / `--start-time` and `-e` / `--end-time`: explicit incident bounds.
- `--json`: newline-delimited JSON for programmatic inspection.
- `-x`: extended human-readable output for long records.
- `-w 0`: disable table truncation; prefer JSON when processing values.

Specify at most two of start, end, and relative time. Quote the OPAL and dataset arguments.
Use an OPAL row bound for record retrieval.

## OPAL building blocks

Adapt these only after sampling the live schema:

```opal
filter body ~ /error|fail|exception/i
pick_col timestamp, body, service
statsby count:count(1), group_by(service)
timechart 5m, count:count(1), group_by(service)
make_col status:string(attributes["status"])
limit 20
```

Build in stages:

1. Sample five rows and identify dataset type and temporal columns.
2. Add one exact filter and keep a small row bound.
3. Aggregate with low-cardinality groupings.
4. Add only the columns required to answer the question.

For Resource datasets, use `topk` rather than `limit`. For interval datasets such as spans,
preserve the live valid-from and valid-to columns when using `pick_col`; these are often
`start_time` and `end_time`, but discover them rather than assuming.

## Output handling

- Prefer table or extended output for quick human inspection and JSON for structured analysis.
- Treat numeric aggregates in JSON as possibly encoded strings; validate and convert explicitly.
- Keep high-cardinality fields such as log body, trace ID, and span ID out of `group_by` unless
  their cardinality is the subject of the query.
- Avoid shell-built giant regexes, unbounded joins, and broad exports. If correlation cannot be
  expressed safely in one bounded query, narrow the time/service set or ask before expanding.
- Treat empty output as ambiguous: verify time coverage, ingestion health, dataset choice, and
  filter spelling before concluding absence.

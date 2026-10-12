---
name: perf-trace
description: Find where the time goes when something is slow by measuring it, then present a duration tree with each level's time and share. Use when the user says a page, job, request, or command is slow, laggy, or "taking so long", asks for "a stack trace with the duration of each level", or asks to check every page for slowness or missing data. Covers sampling profilers (py-spy, perf, samply, Node and Bun CPU profiles), OpenTelemetry traces, and browser page loads. Do not use for correctness bugs with no latency symptom.
---

# Perf Trace

Measure first, then explain. The deliverable is a duration tree the user can read in ten seconds, the one or two steps that dominate it, and a concrete fix with its expected gain.

## 1. Pick the Measurement

- **A process is busy now** (a job, a worker, a stuck request): sample it in place. Find it with `ps -eo pid,ppid,etime,pcpu,rss,cmd --sort=-pcpu | head`; for process pools, dump each child to find the one doing the work before recording.
  - Python: `uvx py-spy record --pid <pid> --duration <s> --rate 50 --format raw --output <file> --nonblocking` (add `--subprocesses --threads --idle` for pools and I/O waits). `uvx py-spy dump --pid <pid>` shows the current stacks.
  - Native code, Rust: `perf record -F 99 -g -p <pid> -- sleep <s>`, then `perf script | stackcollapse-perf.pl`, or `samply record -p <pid>`.
  - Node or Bun: restart the entry point with `--cpu-prof`, or attach the inspector and take a CPU profile.
- **It is reproducible on demand** (one scoring run, one CLI command): write a small script in the scratchpad that runs exactly that, then profile the script. Use a detached worktree from the fetched base, not the hub checkout, and remove it afterwards.
- **A request or page across services**: use the repository's tracing. Find the trace endpoint the services export to (`OTEL_EXPORTER_OTLP_*` in the repository's `.env` or docs). For a local motel server, `GET /api/traces/search?service=<s>&minDurationMs=<n>` finds slow traces and `GET /api/traces/<id>/spans` gives the tree. Otherwise query the configured backend.
- **A web page is slow**: load it in the browser, then read navigation timing, the slowest network requests, long tasks, and console errors. Trace the slowest API request to its server-side span or profile.

Run every probe against data and load that match the complaint. Record what else was running, because contention inflates absolute times.

## 2. Build the Tree

For collapsed stacks, use the helper beside this skill:

```bash
python3 <skill dir>/scripts/stack_tree.py <file> --rate <samples/s> [--focus <frame text>] [--min-pct 1]
```

`--focus` roots the tree at the operation the user asked about (for example `score` or `RunDiscovery`). For traces, build the same shape from span start, end, and parent ids.

## 3. Report

Lead with one sentence naming the dominant cost and the fix. Then show the tree in a code block, trimmed to the levels that matter, with seconds, share, and `file:line` for each step:

```text
101s 100%  score (model.py:75)
 71s  70%  ├─ evaluate_many (model.py:114)   ← recomputes every feature at every refit
 25s  24%  ├─ _standardize (model.py:115)
 <2s  <2%  └─ _fit + predict                 ← the model itself is almost free
```

Then state, in bullets:
- how it was measured: tool, sampling rate, duration, and data size;
- caveats that change the absolute numbers, such as concurrent jobs or a cold cache, and whether the proportions still hold;
- the fix for each dominant step and its expected gain, measured or estimated, labeled as such;
- one-time costs, such as cold loads, kept separate from steady-state costs.

When the user approves a fix, file it as a ticket with the tree, the target speed-up, and an acceptance check: same outputs as before, and old and new timings measured back to back.

## Page Sweep

When the user asks to check every page:

1. List the routes from the router or the navigation, including each variant reachable by query parameters the user mentions.
2. Load each route in the browser. Record time to first meaningful data, the slowest request, console errors, failed requests, and whether the page shows real data or an empty, error, or loading state. Spread the routes across subagents when there are many.
3. Report one table: route, status (ok / slow / empty / error), time to data, slowest request, and evidence. Sort it by problem severity, then offer a ticket per distinct root cause, not per page.

## Guardrails

- No fix without a measurement that shows the step matters.
- Never profile with a tool that pauses or stops a production process unless the user agrees; prefer non-blocking sampling.
- Keep profiles, scripts, and worktrees in the scratchpad; remove temporary worktrees when done.

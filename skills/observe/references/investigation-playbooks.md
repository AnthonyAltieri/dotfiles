# Bounded investigation playbooks

Apply the common workflow first: discover live, sample schema, start at 15 minutes, aggregate,
and retrieve no more than 50 detailed rows. Expand only with evidence.

## Error or regression

1. Discover the service's log and span datasets; sample both.
2. Count failures by a low-cardinality service, status, error class, or deployment dimension.
3. Chart the count in five-minute buckets across the initial window.
4. Retrieve up to 20 representative errors, preserving timestamps and correlation identifiers.
5. Follow one or two trace IDs through the span dataset, preserving its interval columns.
6. Compare with a nearby healthy period or service only if the initial evidence needs a baseline.

Stop when one falsifiable cause explains the timing, affected surface, and corroborating signal.
Report alternative explanations that remain plausible.

## Latency

1. Confirm the duration unit from live values or dataset metadata.
2. Compare count and latency distribution by service/operation; do not infer a percentile from an
   average.
3. Split by status/error only after establishing the overall shape.
4. Inspect up to 20 slow traces and identify which child span dominates duration.
5. Check a resource or dependency signal over the same exact window.

Do not label a dependency causal merely because it appears in slow traces. Establish ordering
and compare with normal traces when possible.

## Kubernetes or resource health

1. Discover live log, entity, and metric datasets for the cluster or workload.
2. Confirm how cluster, namespace, pod, container, and metric labels are represented in each.
3. Count affected workloads before reading individual logs.
4. Check restarts, scheduling/state transitions, saturation, and error logs over the same window.
5. Retrieve details for at most 20 affected workloads and correlate timestamps.

Resource datasets may require `topk`; event or metric datasets generally accept `limit`. Let a
sample query establish the dataset behavior.

## Business impact

1. Confirm the event/span attribute and numeric unit from live schema and representative values.
2. Count successful and failed events before summing value.
3. Compute impact only over the observed window and clearly label extrapolation.
4. Segment by one known-low-cardinality dimension at a time.
5. Cross-check the total against an independent business or service signal when available.

Never present a trace-derived sum as booked revenue or a projection as observed loss. State
coverage gaps, retries/duplicates, sampling, and unit assumptions.

## Expansion budget

Without a user-supplied scope, use these investigation ceilings:

- Initial window: 15 minutes.
- First expansion: up to 1 hour.
- Second expansion: up to 24 hours only when needed for rarity or baseline comparison.
- Detailed rows: 20 initially, 50 maximum per query.
- Trace follow-up: two representative traces before broader correlation.
- Dataset fan-out: two primary signals plus one corroborating signal.

Ask before exceeding these bounds, exporting a large result, or launching many parallel queries.

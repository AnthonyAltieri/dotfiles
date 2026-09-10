# Laurel Observe hints

Every item here is volatile. Use it only to form discovery searches; never query a listed dataset
or field until the live catalog and a current sample confirm it.

## Mandatory discovery gate

```bash
observe list workspace
observe list dataset "Laurel"
observe list dataset "<service-or-signal>"
observe query -i '<CONFIRMED_DATASET>' -q 'limit 5' -r 15m --json
```

If `limit` fails because the dataset is a Resource, retry the sample with `topk 5`. Record the
confirmed dataset name/ID and schema in the investigation notes; do not update this reference
from one observation without explicit maintenance work.

## Dataset search hints

Likely discovery terms and historically useful qualified names include:

| Signal | Search terms | Historical candidate |
| --- | --- | --- |
| Container logs | Kubernetes Logs, Parsed Container Logs | `LaurelAI.Kubernetes Explorer/Kubernetes Logs` |
| Workload state | Kubernetes Entity | `LaurelAI.Kubernetes Explorer/Kubernetes Entity` |
| Cluster metrics | Prometheus Metrics | `LaurelAI.Kubernetes Explorer/Prometheus Metrics` |
| HTTP requests | Service Request Logs, Endpoint Logs | `LaurelAI.Service Request Logs` |
| Traces and spans | Trace, Span, Service | `LaurelAI.Tracing/Span` |
| CI | Actions Run | `LaurelAI.github/Actions Run` |
| Authentication | Auth0 | `LaurelAI.Auth0` |
| Database health | MongoDB Metrics, Atlas Metrics | `LaurelAI.MongoDB/Metrics` |

Other historical signals include Lambda logs, VPC flow logs, GuardDuty findings, frontend and
desktop telemetry, monitor alarms, and ingest volume. Discover by topic rather than enumerating
the entire catalog.

## Field and dataset gotchas

Confirm each from a live sample:

- Kubernetes logs have historically used `body` rather than `message`, with `cluster`,
  `namespace`, `pod`, and `container` as top-level fields.
- Kubernetes Entity has historically stored some resource content as stringified JSON. Prefer
  top-level fields or a purpose-built log/metric dataset over pretending the string is traversable.
- Prometheus labels have historically nested cluster under `labels.k8s_cluster_name` and workload
  dimensions under `labels.namespace`, `labels.pod`, and `labels.container`.
- Service request data has historically used camelCase fields such as `statusCode` and
  `responseTime`; confirm response-time units.
- Tracing Service has historically used `service_name`. Span projections must retain discovered
  valid-from and valid-to columns.
- Resource datasets such as Kubernetes Entity and Actions Run may require `topk` instead of
  `limit`.

## Environment hints

Historical cluster names include `iad-prd-eks`, `lhr-prd-eks`, and `iad-stg-eks`. Treat these as
search hints only. Confirm current environment identity in telemetry before attributing impact.

For an Airflow staging investigation, for example, first discover current Kubernetes log
datasets, sample the schema, then confirm the staging cluster value and pod/service naming before
filtering for structured error levels. Never begin with a hard-coded historical query.

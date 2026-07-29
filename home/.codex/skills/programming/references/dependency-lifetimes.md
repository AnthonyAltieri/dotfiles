# Dependency Lifetimes

Use when code creates, stores, shares, or disposes a collaborator, configured value, or resource, especially when construction or behavior depends directly or transitively on environment, config, process state, credentials, or scoped context.

## Decision Model

Before construction, identify captured values/state, the narrowest safe sharing scope, any identity or snapshot that must persist, and the owner of construction, failure, and cleanup.

Choose the narrowest scope that preserves required identity or reuse. Share-safety permits widening; it does not justify it.

An instance must not outlive any resource, credential, mutable state, provider, or scope-bound identity it still uses. Copied immutable values may outlive their source carrier when their validity is not scope-bound.

| Conditions | Ownership | Initialize |
| --- | --- | --- |
| Deliberate reuse across a named runtime; inputs are stable and context-independent; sharing is safe; construction is synchronous/import-safe; no owner-managed cleanup | Process-owned | Module scope in the owning composition module |
| Same reuse, but construction is async or startup order, failure, or cleanup needs orchestration | Process-owned | Once in process bootstrap |
| One identity, stateful resource, or snapshot must span a named scope | Scope-owned | Once at that scope's highest safe owner |
| Only one branch, call, or iteration needs it | Use-owned | At the lowest common point of actual use |

## Configuration And Scope

- Parse ambient state once at the application boundary into typed config; pass config or narrower typed values to constructors. Keep leaf modules from reading ambient sources.
- Treat SDK defaults, credential chains, and imported config modules as indirect ambient access. Distinguish immutable snapshots from live config or credential providers.
- Name the exact scope: process, worker, runtime isolate, invocation, request, job, transaction, operation, branch, or call. Avoid “singleton” without its runtime boundary.
- Treat a module export as one instance per loaded module graph/runtime isolate, not across workers, processes, deployments, duplicate packages, or hot reloads.
- Treat tenant/session caches as owned resources with explicit keys, eviction, cardinality limits, and credential-rotation behavior.

## Place Ownership Deliberately

- **Process-owned:** require deliberate runtime-wide reuse, process-stable inputs, context-independent identity/behavior, safe concurrent sharing, and no narrower-scope state or credentials. Any mutable state must be intentionally process-scoped and concurrency-safe.
- **Scope-owned:** construct at the outermost point inside the scope that has every input, dominates all consumers, and controls cleanup; pass it explicitly and dispose it there.
- **Use-owned:** construct at the lowest common actual-use point; inline when clear, otherwise bind for reuse, cleanup, or readability.
- Interpret “highest” and “lowest” through ownership and control flow, not directory depth, lexical nesting, or architectural prestige.

Treat repeated forwarding of stable dependencies as a misplaced-owner signal. Capture them at the narrowest shared safe scope that dominates their consumers while keeping operation-specific facts explicit. Never widen a dependency beyond the lifetime of captured resources, credentials, identity, or state, and never replace explicit inputs with a broad context bag or ambient access.

Choose ownership before eager/lazy timing. Cost alone never justifies widening scope; use scope-local laziness or memoization instead. Share a safe pool, transport, provider, or immutable substrate while keeping context-bearing wrappers scoped. Separate long-lived providers from short-lived snapshots, resolving dynamic flags, rotating credentials, and reloadable config where a consistent view is required.

## Runtime, Cleanup, And Tests

- Assume asynchronous work can interleave, and each worker, process, or serverless runtime has separate module instances. Process state may survive warm invocations; request/invocation state must not.
- Export a pure factory when tests or alternate composition roots need custom inputs; keep the production instance in a composition module. Do not rely on environment mutation after import.
- Give transactions, timers, subscriptions, sockets, and buffered telemetry explicit lifecycle owners. Do not hide ownership behind imports when deterministic cleanup matters.
- Reuse repository or framework startup/shutdown hooks. Keep bootstrap direct: parse config, construct owned dependencies, inject them, start the application, and close them through the owning hook.
- In placement sketches, show only that flow with narrow placeholders. Name repository types/hooks instead of redeclaring interfaces; register cleanup with the existing owner instead of inventing a runtime object solely for shutdown.
- Do not infer custom signal routing, idempotence, failure aggregation, or partial-start recovery from “graceful shutdown.” Add only required behavior and mention other hardening as caveats.

## Examples

### Process-Owned

```ts
const appConfig = parseAppConfig(process.env);
export const ratePolicy = createRatePolicy(appConfig.rateLimits);
```

Use module scope only when config is a process snapshot, process-wide reuse is intentional, and import-time failure is acceptable. For an otherwise process-owned dependency, use bootstrap only when construction is async or startup order, failure, or cleanup needs orchestration.

### Scope-Owned Transaction

```ts
const handleCommand = async (
  ctx: RequestContext,
  deps: ProcessDependencies,
) => {
  const command = parseCommand(ctx.request);
  const actor = await authenticate(ctx, deps.auth);

  return deps.database.transaction(async (transaction) => {
    const current = await loadCurrent(transaction, command.id);
    const change = decideChange(command, actor, current);
    const saved = await saveChange(transaction, change);
    return present(saved);
  });
};
```

Acquire the transaction after authentication and before every operation sharing its consistency boundary; let its owner close it.

## Review

Name the sharing scope; inspect captured lifetimes/identity and concurrent safety; verify construction, cleanup, provider/snapshot separation, and factory seams.

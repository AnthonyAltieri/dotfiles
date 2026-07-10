# Dependency Lifetimes

Use this reference whenever code creates, stores, shares, or disposes a collaborator, configured value, or resource. Apply it especially when behavior or construction depends directly or transitively on environment, config, process state, credentials, or scoped context.

## Contents

- [Decision Model](#decision-model)
- [Separate Configuration From Construction](#separate-configuration-from-construction)
- [Name The Scope](#name-the-scope)
- [Choose Process Ownership Deliberately](#choose-process-ownership-deliberately)
- [Place Scoped Dependencies By Ownership](#place-scoped-dependencies-by-ownership)
- [Keep Scope Separate From Timing And Cost](#keep-scope-separate-from-timing-and-cost)
- [Account For Runtime And Tests](#account-for-runtime-and-tests)
- [Examples](#examples)
- [Review Checklist](#review-checklist)

## Decision Model

Answer these questions before choosing where to initialize a dependency:

1. What values, resources, identity, and mutable state does it capture?
2. Across what exact scope may one instance be shared safely?
3. Must that instance preserve identity, state, or a consistency snapshot across several uses?
4. Which owner can construct it, handle failure, and release it?

Choose the narrowest scope that preserves required identity or reuse. Treat share-safety as permission to widen a lifetime, not as a reason to widen it.

Enforce this lifetime invariant: an instance must not outlive any resource, credential, mutable state, provider, or scope-bound identity it continues to depend on. Allow copied immutable values to outlive their source carrier when their validity is not scope-bound.

| Conditions | Ownership | Initialize |
| --- | --- | --- |
| One instance must be intentionally reused across a named runtime boundary; its inputs are runtime-stable, context-independent, share-safe, synchronous, import-safe, and require no owner-orchestrated cleanup | Process-owned | At module scope in the owning composition module |
| One instance must be intentionally reused across a named runtime boundary, but construction is async or depends on startup order, failure handling, or cleanup | Process-owned | Once in process bootstrap |
| Reuse one identity, stateful resource, or snapshot throughout a named scope | Scope-owned | Once at the highest safe owner of that scope |
| Needed only by one branch, call, or iteration | Use-owned | At the lowest common point of actual use |

## Separate Configuration From Construction

- Parse raw ambient state once at the application boundary into typed config.
- Pass typed config or narrower typed values to constructors.
- Keep leaf modules from reading `process.env` or another ambient source themselves.
- Treat SDK defaults, credential chains, and imported configuration modules as indirect environment access.
- Distinguish an immutable config snapshot from a live config or credential provider.

## Name The Scope

- Name the scope explicitly: process, worker, runtime isolate, invocation, request, job, transaction, operation, branch, or call.
- Avoid saying "singleton" without naming its runtime boundary.
- Treat a module export as one instance per loaded module graph or runtime isolate, not one instance across workers, processes, deployments, duplicated packages, or hot reloads.
- Treat tenant and session caches as owned resources with explicit keys, eviction, cardinality limits, and credential-rotation behavior.

## Choose Process Ownership Deliberately

Use a process-owned instance only when all of these hold:

- Require one identity or initialized value to be reused deliberately across the named runtime boundary.
- Keep every captured input stable for the process lifetime.
- Keep behavior and identity independent of request, job, tenant, and user context.
- Make concurrent sharing safe, including async interleaving.
- Retain no mutable state or credentials belonging to a narrower scope.
- Keep any process-owned mutable state intentionally process-scoped and safe under concurrent use.

Initialize and export a synchronous, import-safe process dependency that requires no owner-orchestrated cleanup at module scope in its owning composition module.

Initialize it in explicit bootstrap instead when construction is async, startup order matters, failures need orchestration, or the process owner must close or flush it.

## Place Scoped Dependencies By Ownership

Use **scope-owned** dependencies when one identity, resource, mutable state, or consistency snapshot must serve several operations in the same named scope.

- Initialize a scope-owned dependency at its highest safe owner: the outermost point inside that scope, after every construction input exists, that dominates all consumers and controls cleanup.
- Pass it downward explicitly.
- Dispose it at the ownership boundary that constructed it.

Use **use-owned** dependencies when identity need not survive beyond the actual branch, call, or iteration that needs them.

- Initialize a use-owned dependency at the lowest common control-flow point that dominates its actual uses.
- Inline it when the expression stays clear.
- Bind it locally when reuse, cleanup, or readability requires a name.

Interpret "highest" and "lowest" through ownership and control flow, not directory depth, lexical nesting, or architectural prestige.

## Keep Scope Separate From Timing And Cost

- Choose ownership before choosing eager or lazy initialization.
- Use lazy construction or scope-local memoization without widening the sharing scope.
- Do not make a dependency process-owned merely because construction is expensive.
- Share a safe lower-level pool, transport, provider, or immutable substrate while keeping a context-bearing wrapper scoped.
- Keep long-lived providers separate from short-lived snapshots.
- Resolve dynamic flags, rotating credentials, and reloadable config at the scope that needs a consistent view.

## Account For Runtime And Tests

- Assume async requests can interleave even when JavaScript runs on one thread.
- Assume each worker, process, or serverless runtime has separate module instances.
- Allow process-owned state to survive warm serverless invocations, but never retain invocation or request state there.
- Export a pure factory when tests or alternate composition roots need custom inputs.
- Keep the production instance in a composition module.
- Do not rely on mutating environment variables after an importing module has loaded.
- Give transactions, timers, subscriptions, sockets, and buffered telemetry an explicit lifecycle owner.
- Do not hide resource ownership behind an import when deterministic cleanup matters.
- Use the repository or framework's existing startup and shutdown hooks before introducing a custom lifecycle abstraction.
- Keep bootstrap wiring direct: parse config, create owned dependencies, inject them, start the application, and close them through the owning shutdown hook.
- For a placement sketch, show only that ownership flow with narrow placeholders for existing application, server, and telemetry APIs.
- Refer to repository-owned types and hooks by name instead of redeclaring surrounding interfaces merely to make an example self-contained.
- Register cleanup with the existing lifecycle owner instead of returning a new runtime or lifecycle object solely to expose shutdown.
- Do not infer that graceful shutdown requires custom signal routing, idempotence, failure aggregation, or partial-startup recovery; add each only when explicitly required by the task or existing runtime contract.
- Mention unrequested lifecycle hardening as a caveat instead of implementing it.

## Examples

### Process-Owned, Synchronous, And Share-Safe

```ts
import { createRatePolicy } from "./rate-policy";
import { parseAppConfig } from "./parse-app-config";

const appConfig = parseAppConfig(process.env);
export const ratePolicy = createRatePolicy(appConfig.rateLimits);
```

Keep this at module scope when the validated config is a process snapshot, the policy must be reused across the runtime, and invalid configuration may intentionally fail module evaluation. Move parsing and construction to bootstrap when startup must orchestrate that failure.

### Scope-Owned Transaction At The Highest Safe Owner

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

Open the transaction after authentication, before every operation that must share its consistency boundary, and let the transaction owner close it.

### Use-Owned At The Point Of Use

```ts
const present = (result: Result, config: AppConfig) => {
  if (result.kind !== "download") return json(result);
  return csv(createCsvEncoder(config.csv).encode(result.rows));
};
```

Construct the encoder only in the branch that needs it. Introduce a local binding only when construction, reuse, cleanup, or readability justifies one.

## Review Checklist

- Name the exact identity-sharing scope.
- Check every captured input for a shorter lifetime or narrower identity.
- Verify concurrent sharing instead of assuming it.
- Place scope-owned construction at the highest safe owner.
- Place use-owned construction at the lowest common point of use.
- Separate dynamic providers from scope-consistent snapshots.
- Give async or disposable dependencies an explicit lifecycle owner.
- Preserve a factory seam when tests or alternate composition roots need one.

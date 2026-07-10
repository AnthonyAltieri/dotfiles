# TypeScript Defaults

Use these defaults when the task is TypeScript or TSX. Follow established repository conventions when they make a different deliberate choice.

## Boundaries And Domain Types

- Use the repository's canonical runtime schema library and parsers at boundaries; use `zod` when the project already standardizes on it.
- Accept `unknown` at untrusted ingress and parse it before application logic.
- Derive types from canonical schemas when schema output is the internal representation.
- Keep transport DTOs separate from richer internal domain types when their meaning or invariants differ.
- Reuse existing branded or opaque types and their canonical schema, parser, constructor, or guard.
- Do not recreate a domain identifier as `string`, duplicate its schema, or use an assertion to bypass construction.
- Introduce a brand when it prevents a concrete interchange or preserves an invariant across a meaningful boundary, and when it fits the repository's modeling approach.
- Prefer a Zod-backed brand when the repository already uses Zod and the value crosses a runtime boundary.
- Avoid `as` assertions for validation. Keep an unavoidable interop assertion narrow and explain the invariant the external type cannot express.

## Types And Control Flow

- Prefer inference for local trusted values; annotate exported contracts and places where an annotation prevents accidental widening or documents intent.
- Use string literal unions and `as const` objects instead of enums unless an external contract or repository convention requires an enum.
- Represent closed variants as discriminated unions and use exhaustive `switch` statements with a `never` check.
- Prefer `unknown` at boundaries and `never` at impossible states; avoid `any`.
- Use `satisfies` when it checks a shape while preserving useful literal precision.
- Model expected failures with result shapes or unions when callers should branch on them.

## Files

- Name files in lowercase kebab-case.

## Compact Pattern

```ts
import { z } from "zod";

const receiptIdSchema = z.string().uuid().brand<"ReceiptId">();
type ReceiptId = z.infer<typeof receiptIdSchema>;

const chargeKind = {
  ok: "ok",
  retryableError: "retryable-error",
  fatalError: "fatal-error",
} as const;

type ChargeResult =
  | { kind: typeof chargeKind.ok; receiptId: ReceiptId }
  | { kind: typeof chargeKind.retryableError; reason: string }
  | { kind: typeof chargeKind.fatalError; reason: string };

const messageFromChargeResult = (result: ChargeResult): string => {
  switch (result.kind) {
    case chargeKind.ok:
      return result.receiptId;
    case chargeKind.retryableError:
    case chargeKind.fatalError:
      return result.reason;
    default: {
      const exhaustive: never = result;
      return exhaustive;
    }
  }
};
```

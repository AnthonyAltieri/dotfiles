# TypeScript Defaults

Apply for TypeScript or TSX; defer to deliberate repository conventions.

## Boundaries And Domain Types

- Accept `unknown` at untrusted ingress and parse with the canonical runtime schema library; use Zod only when standardized.
- Derive internal types from canonical schemas when their output is the domain representation. Keep transport DTOs separate when meaning or invariants differ.
- Reuse branded/opaque types and canonical construction. Do not recreate identifiers as `string`, duplicate schemas, or bypass construction with assertions.
- Add a brand only to prevent concrete value confusion or preserve a meaningful boundary invariant; prefer a Zod-backed brand when Zod is standard and the value crosses runtime ingress.
- Assertions are not validation. Keep unavoidable interop assertions narrow and explain the invariant the external type omits.

## Types And Control Flow

- Infer trusted locals; annotate exported contracts and places where annotations prevent widening or clarify intent.
- Prefer string-literal unions and `as const` objects to enums unless an external contract or repository convention requires one.
- Model closed variants as discriminated unions with exhaustive `switch`/`never` checks. Use `unknown` at boundaries and `never` for impossible states; avoid `any`.
- Use `satisfies` to check shape while preserving literal precision. Model expected failures with results/unions when callers must branch.
- Name files in lowercase kebab-case.

## Compact Pattern

```ts
import { z } from "zod";

const receiptIdSchema = z.string().uuid().brand<"ReceiptId">();
type ReceiptId = z.infer<typeof receiptIdSchema>;

const chargeKind = {
  ok: "ok",
  error: "error",
} as const;

type ChargeResult =
  | { kind: typeof chargeKind.ok; receiptId: ReceiptId }
  | { kind: typeof chargeKind.error; reason: string };

const messageFrom = (result: ChargeResult): string => {
  switch (result.kind) {
    case chargeKind.ok:
      return result.receiptId;
    case chargeKind.error:
      return result.reason;
    default: {
      const exhaustive: never = result;
      return exhaustive;
    }
  }
};
```

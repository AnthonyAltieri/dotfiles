# Ultragoal Composition

Apply this reference only when the user explicitly pairs `$adversarial-review` with `$ultragoal`.

- Let Ultragoal remain the sole owner of goal design, activation, durable state, approval gates, blocker state, and completion.
- Persist the named adversarial-review gate and its required pass evidence in Ultragoal's durable completion proof, or in the self-contained goal objective when no durable goal file is used.
- Run the candidate's primary and supporting verifiers before review and again after accepted fixes. Review evidence supplements rather than replaces them.
- Do not count Ultragoal's pre-activation self-red-team as an independent adversarial review of the completed candidate.
- Do not call `create_goal` or `update_goal` from reviewer agents or from this skill acting alone.
- Allow Ultragoal to mark completion only when at least two fresh-context reviewers inspected the same current snapshot, the consolidated gate is `passed`, no material finding remains unresolved, and normal verifiers pass on that snapshot.
- Immediately before Ultragoal marks completion, recompute the content-bound reviewed snapshot. Any drift reopens the review gate.

If the pairing is added after goal activation, record it in durable goal state before relying on it. When an active self-contained goal has no durable file, create or update the nearest goal state under Ultragoal's durability rules when safe, record that the active objective itself is unchanged, and require that state to be inspected on resume. If the gate cannot be made durable, report that limitation and keep paired completion inconclusive rather than claiming the active objective contains it.

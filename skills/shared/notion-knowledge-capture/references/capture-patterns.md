# Capture Patterns

Select the narrowest pattern that preserves the useful knowledge. Adapt headings to the source; do not force empty sections or unsupported database properties.

## Taxonomy

| Type | Use for | Essential content |
|---|---|---|
| Decision | A choice and why it was made | Decision, context, alternatives, rationale, consequences, open questions |
| How-to | A repeatable procedure | Goal, prerequisites, steps, verification, failure cases |
| FAQ | Recurring questions with stable answers | Question, concise answer, supporting detail or links |
| Wiki or concept | Shared explanatory knowledge | Summary, context, key concepts, examples, related sources |
| Learning | A reusable observation from an incident or project | Observation, evidence, impact, recommendation, uncertainty |
| Documentation | A system, process, or interface reference | Purpose, scope, behavior, dependencies, operations, limitations |

## Common Header

```markdown
# <Clear title>

## Summary
<Two or three sentences for the intended audience.>

## Context
<Why this exists and what source material it reflects.>
```

Add only source-supported metadata that already exists at the destination, such as type, status, owner, tags, or date. Prefer omission over guessed values.

## Decision

```markdown
## Decision
<The choice that was made.>

## Alternatives considered
- <Alternative>: <why it was not selected>

## Rationale
<Constraints and evidence that drove the choice.>

## Consequences
- <Expected benefit or cost>

## Open questions
- <Unresolved item>
```

## How-to

```markdown
## Goal
<Observable outcome.>

## Prerequisites
- <Required access, input, or state>

## Steps
1. <Action>

## Verify
<How to confirm success.>

## Troubleshooting
- <Symptom>: <supported response>
```

## FAQ

```markdown
## <Question?>
<Direct answer.>

<Optional explanation, caveat, or source link.>
```

## Wiki, Learning, or Documentation

```markdown
## Key points
- <Durable fact or concept>

## Details
<Structured explanation, evidence, or operating guidance.>

## Limitations or unknowns
- <Boundary, uncertainty, or unresolved issue>

## Sources and related material
- <Source title or URL>
```

Keep action items inside the primary page unless the user separately authorizes task creation. Mention related pages without mutating them unless backlink or hub updates were explicitly requested.

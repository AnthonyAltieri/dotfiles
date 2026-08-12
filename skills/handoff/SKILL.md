---
name: handoff
description: Compact the current conversation into a self-contained handoff document for another agent to continue safely. Use when the user asks to hand off, resume in another session, or preserve current task context for a fresh agent.
argument-hint: "What will the next session focus on?"
---

# Handoff

Create a temporary Markdown file with `mktemp -t handoff-XXXXXX.md`. Read the empty file before writing, then capture only the context a fresh agent needs to continue.

Use this concise schema:

```markdown
# Handoff

## Objective and success criteria
## Current state
## Decisions, constraints, and assumptions
## Remaining work
## Verification performed and still needed
## Canonical references
## Suggested skills
```

Tailor the document to any focus supplied by the user. Reference existing plans, issues, ADRs, commits, diffs, and artifacts by path or URL instead of duplicating them. Distinguish completed work from proposed or unverified work, and include exact commands only when they are useful for resumption.

Exclude secrets, tokens, credentials, private keys, raw environment contents, and sensitive payloads. Name the approved secret source or configuration location when the next agent needs to know where to obtain a value; never copy the value itself.

Read the completed file back, verify that it is self-contained and accurate, then return its exact path.

---
name: notion-knowledge-capture
description: Capture conversations, notes, and decisions into authorized Notion pages. Use for creating or updating wiki entries, how-tos, decision records, FAQs, learnings, or documentation; do not use for read-only Notion analysis.
---

# Knowledge Capture

Turn source material into durable Notion knowledge without widening the requested mutation scope.

## Authorization Boundary

- Treat an explicit request to capture into Notion as authorization for the requested primary page creation or stated page update, including a user-specified set of pages.
- Do not create databases, alter schemas, change permissions, move or archive pages, or write secondary records unless the user explicitly requests that operation.
- Do not create follow-up tasks or mutate hub, index, or related pages merely because the captured content mentions them. Include action items and links in the primary page as prose when useful.
- Ask for direction when multiple plausible destinations or existing pages would materially change the result. Never invent a fallback database.
- Use read operations for discovery and verification. Before any update, fetch the current page; never write from stale conversation context or a local export.

## Workflow

1. Define the capture.
   - Identify the audience, content type, source material, destination, and whether the user wants a new page or an update.
   - Use the taxonomy and compact templates in [capture-patterns.md](reference/capture-patterns.md).
2. Draft faithfully.
   - Separate facts, decisions, rationale, action items, and unresolved questions.
   - Preserve source links. Mark unknown values as unknown or omit them; do not invent owners, dates, status, or conclusions.
3. Resolve the live destination.
   - Use the available Notion connector to search only as needed, then fetch the exact current page or destination.
   - Inspect the destination's current properties instead of relying on remembered schemas or example payloads.
   - Prefer updating a clearly matching canonical page over creating a duplicate, but only when the request authorizes an update.
4. Bound the write.
   - Confirm the intended parent or page, create-versus-update choice, title, meaningful properties, and content.
   - Use only properties that exist and whose values are supported by the source material.
   - Discover current connector operations and input shapes from the live tool metadata; do not assume a tool name or payload.
5. Perform the primary write.
   - Make the smallest authorized creation or update.
   - Preserve unrelated content on updates. Do not broaden the operation to improve surrounding workspace organization.
6. Read back and verify.
   - Fetch the written page from Notion after the mutation.
   - Verify page identity, title, destination, important properties, and expected sections. Correct an obvious malformed primary write only within the original authorization; otherwise report the mismatch.
   - Return the page title and URL, summarize what changed, and disclose any requested content that could not be written.

If the Notion connector is unavailable or unauthorized, report the missing capability and stop before mutation. Do not provide product-specific setup commands that may be stale.

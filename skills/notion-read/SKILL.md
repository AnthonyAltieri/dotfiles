---
name: notion-read
description: Read, summarize, analyze, compare, or extract from Notion pages, databases, URLs, and documents without mutation. Use for read-only Notion work that benefits from one current full fetch materialized into a temporary local artifact; do not use for creates, updates, comments, moves, or property changes.
---

# NotionRead

Read current Notion content once, analyze it locally, and leave Notion unchanged.

## Core Rule

- If the user is only reading, summarizing, auditing, comparing, extracting, or answering questions from Notion content, obtain one current complete representation and materialize it into a local temp file before substantive analysis.
- Treat the available Notion connector as the control plane for discovery, identity, permissions, and current retrieval. Treat the local temp file as the data plane for analysis.
- Do not invoke any Notion mutation. If the task creates, updates, comments on, moves, renames, changes properties, links, or otherwise writes to Notion, leave this skill and use an explicitly authorized write workflow.
- If write intent is absent, assume the Notion task is read-only.

## Preference Order

1. Use the available Notion connector to fetch or export one complete, current representation of the target.
2. If no full representation is available, retrieve every relevant chunk or page once, record the coverage, and assemble a single local artifact.
3. Prefer Markdown for prose pages, JSON for block trees or database records, HTML only when structure would otherwise be lost, and plain text only as a last structured-content fallback.
4. Use a user-provided export when it is the requested source or live access is unavailable and its age is acceptable for the task; disclose that it may not reflect current Notion state.
5. Use additional connector reads only for discovery, permissions troubleshooting, explicitly missing content, or a final identity spot-check.

## Workflow

1. Classify intent.
   - Continue only for read-only work.
   - Ask before proceeding only when the user request could reasonably imply a Notion write.
2. Resolve the target.
   - Use connector search, fetch, query, or URL/page-id parsing only as far as needed to identify the exact page, database, or page set.
   - Resolve ambiguous search results before materializing content.
3. Create a temp workspace outside the repo.
   - Use `mktemp -d -t notion-read-XXXXXX` or the platform equivalent.
   - Keep raw exports, normalized text, and manifests together in that directory.
4. Materialize content.
   - Write one file per source page when reading multiple pages.
   - Preserve title, URL, page id, database id when relevant, and fetch timestamp in a small header or `manifest.json`.
   - Keep the raw export when conversion is lossy, then create a normalized `.md` or `.json` file for analysis.
   - Record whether the artifact is complete. If it is partial, record missing pages, blocks, properties, attachments, comments, or inaccessible children before analysis.
5. Analyze locally.
   - Use `rg`, `sed`, JSON tools, parsers, or normal file reads against the temp artifact.
   - Do not keep asking the connector for adjacent chunks once the file exists.
6. Answer from stable document anchors.
   - Cite page titles, headings, row names, or section labels rather than temp paths unless the user asks for the artifact location.
   - State when the local file is a fallback reconstruction from connector results instead of an official/exported representation.
   - State any incomplete coverage before presenting conclusions it could affect.
7. Clean up.
   - Delete the temp workspace after answering unless the user requested retention or the workflow must return the artifact.
   - If retention is requested, return the exact path and note that it may contain sensitive Notion data. If cleanup fails, disclose the remaining path.

## Temp Artifact Standards

- Do not commit temp Notion exports.
- Do not place Notion exports inside the repository unless the user explicitly asks for a tracked artifact.
- Prefer deterministic filenames: slugified title plus short page id.
- For databases, include properties and relation ids in JSON; include rendered row/page prose separately when needed.
- For large pages, build an outline first from the local file, then inspect relevant sections.
- For sensitive docs, minimize quoted output and retain temp files only when the user explicitly requests it.

## Fallback Discipline

- If the current fetch/export fails because the Notion connector is disconnected, unavailable, or unauthorized, report the capability or permission that is missing.
- If only partial content can be fetched, say what is missing before drawing conclusions.
- If the user later asks to update the same Notion page, discard the temp artifact as a write source and refetch current state through the authorized write workflow.

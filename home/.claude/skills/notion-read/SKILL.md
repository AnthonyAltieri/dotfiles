---
name: notion-read
description: Use when reading, summarizing, analyzing, comparing, or extracting from Notion pages, databases, URLs, or docs in read-only tasks; prefer materializing the full target into a local temp Markdown, JSON, HTML, or text file before analysis instead of repeatedly reading MCP chunks; do not use for Notion create, update, or write operations.
---

# NotionRead

Read Notion documents as local artifacts when the task is read-only.

## Core Rule

- If the user is only reading, summarizing, auditing, comparing, extracting, or answering questions from Notion content, fetch or export the target into a local temp file first.
- Treat Notion MCP as the control plane for discovery, identity, permissions, and fallback retrieval. Treat the local temp file as the data plane for analysis.
- If the task creates, updates, comments on, moves, renames, changes properties, links, or otherwise writes to Notion, stop using this read-only shortcut and use the normal Notion write workflow.
- If write intent is absent, assume the Notion task is read-only.

## Preference Order

1. Reuse a user-provided local export when it is current enough for the request.
2. Use an available Notion export, download, connector, API helper, or MCP tool that can materialize the page or database rows into a local file.
3. Prefer Markdown for prose pages, JSON for block trees or database records, HTML only when structure would otherwise be lost, and plain text only as a last structured-content fallback.
4. If the MCP only exposes chunked reads, fetch all relevant chunks once, concatenate them into a temp file, and continue from that file.
5. Use repeated MCP chunk reads only for tiny metadata checks, page discovery, permissions troubleshooting, or final spot checks.

## Workflow

1. Classify intent.
   - Continue only for read-only work.
   - Ask before proceeding only when the user request could reasonably imply a Notion write.
2. Resolve the target.
   - Use Notion search, page fetch, database query, or URL/page-id parsing only as far as needed to identify the page, database, or page set.
   - Avoid walking the document through MCP just to learn what to read.
3. Create a temp workspace outside the repo.
   - Use `mktemp -d -t notion-read-XXXXXX` or the platform equivalent.
   - Keep raw exports, normalized text, and manifests together in that directory.
4. Materialize content.
   - Write one file per source page when reading multiple pages.
   - Preserve title, URL, page id, database id when relevant, and fetch timestamp in a small header or `manifest.json`.
   - Keep the raw export when conversion is lossy, then create a normalized `.md` or `.json` file for analysis.
5. Analyze locally.
   - Use `rg`, `sed`, JSON tools, parsers, or normal file reads against the temp artifact.
   - Do not keep asking the MCP for adjacent chunks once the file exists.
6. Answer from stable document anchors.
   - Cite page titles, headings, row names, or section labels rather than temp paths unless the user asks for the artifact location.
   - State when the local file is a fallback reconstruction from MCP chunks instead of an official/exported representation.

## Temp Artifact Standards

- Do not commit temp Notion exports.
- Do not place Notion exports inside the repository unless the user explicitly asks for a tracked artifact.
- Prefer deterministic filenames: slugified title plus short page id.
- For databases, include properties and relation ids in JSON; include rendered row/page prose separately when needed.
- For large pages, build an outline first from the local file, then inspect relevant sections.
- For sensitive docs, minimize quoted output and delete temp files if the user asks for cleanup.

## Fallback Discipline

- If the local fetch/export fails because Notion MCP is disconnected, unavailable, or unauthorized, report the connection issue and the exact action needed next.
- If only partial content can be fetched, say what is missing before drawing conclusions.
- If the user later asks to update the same Notion page, refetch current state through the write-capable path before editing; do not write from a stale temp export.

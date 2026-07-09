# Claude Global Agent Guidelines

These are user-level preferences that apply across repos.

## Notion Defaults

- For read-only Notion document, page, database, or URL tasks, use `$notion-read` (NotionRead).
- If the task is reading and not updating/writing, prefer fetching or exporting the Notion content into a local temp file and analyzing that file instead of reading chunks through the MCP.
- For creates, updates, comments, property changes, relation changes, or any other write, use the normal Notion write workflow.

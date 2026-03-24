---
name: sql-read
description: Use when a user needs live read-only Postgres or SQLite inspection; configure a named read-only target once, then use the blanket-approvable `sql-read run` path for later queries.
metadata:
  short-description: Read Postgres or SQLite safely
---

# SQL Read

Use the `sql-read` helper from the active Nix profile to inspect Postgres or SQLite data in read-only mode.

Trigger this skill for:
- live schema inspection
- ad hoc read-only analysis queries
- fast table or column lookups when the answer lives in a database

Do not use it for:
- writes, migrations, or backfills
- admin tasks
- general interactive shell work

## Quick Start

The active Nix profile puts `sql-read` on `PATH`, so call it directly.

1. Use the default Codex state dir: `"$HOME/.codex/skills/sql-read/state"`.
2. Export the connection input in its own command.
   - `export PROD_READONLY_URL='postgresql://user:pass@host:5432/dbname'`
3. Persist the named target in a separate command.
   - `sql-read target upsert --state-dir "$HOME/.codex/skills/sql-read/state" --name prod-readonly --engine postgres --dsn-env-var PROD_READONLY_URL`
4. Run read-only queries against the stored target in a separate command.
   - `sql-read run --state-dir "$HOME/.codex/skills/sql-read/state" --target prod-readonly --file "$HOME/.codex/skills/sql-read/assets/queries/postgres-schema-overview.sql" --format json`
5. Use the same split workflow for SQLite targets.
   - `export LOCAL_APP_DB='/absolute/path/to/app.sqlite3'`
   - `sql-read target upsert --state-dir "$HOME/.codex/skills/sql-read/state" --name local-app --engine sqlite --sqlite-db-path-env-var LOCAL_APP_DB`
   - `sql-read run --state-dir "$HOME/.codex/skills/sql-read/state" --target local-app --file "$HOME/.codex/skills/sql-read/assets/queries/sqlite-schema-overview.sql" --format json`
6. Inspect or remove configured targets with explicit target-management commands.
   - `sql-read target list --state-dir "$HOME/.codex/skills/sql-read/state"`
   - `sql-read target remove --state-dir "$HOME/.codex/skills/sql-read/state" --name local-app`

## Workflow

1. Start with schema inspection.
   - Use the bundled query templates in `assets/queries/`.
   - Load the relevant engine notes from `references/postgres.md` or `references/sqlite.md` only when needed.
2. Configure the target once.
   - Use `sql-read target upsert --state-dir <dir> --name <target> ...` to persist the resolved read-only DSN or SQLite path under the skill state dir.
   - Keep env-var assignment and `target upsert` in separate commands.
   - Do target setup in its own command; it is not part of the blanket-approved surface.
3. Keep queries narrow.
   - Ask for aggregates, counts, or explicit filters before scanning large tables.
   - Add an explicit `limit` in the SQL unless the query is already aggregate-only.
4. Prefer JSON output.
   - Use `--format json` by default so the agent sees compact, structured rows.
   - Switch to `table` only when the user explicitly wants a human-readable table.
5. Run read-only queries through the stored target.
   - `sql-read run --state-dir <dir> --target <name> ...` is the only blanket-approved execution path.
   - Later `run` calls do not require the env var to still exist.

## Output

Default JSON output is compact and stable:

```json
{"engine":"postgres","target":{"mode":"named-target","name":"prod-readonly"},"columns":["id","email"],"rows":[[1,"a@example.com"]],"row_count":1,"truncated":false,"duration_ms":38}
```

## Bundled Resources

- `sql-read`
  - The active Nix profile provides this command on `PATH`.
  - `run` is the blanket-approvable read-only execution path.
  - `target upsert|list|remove` manages persisted named targets.
- `scripts/`
  - Contains the Rust source package that the Nix profile builds into `sql-read`.
- `references/postgres.md`
  - Catalog-query patterns and Postgres-specific caveats.
- `references/sqlite.md`
  - SQLite schema-inspection patterns and read-only caveats.
- `assets/queries/`
  - Reusable schema-inspection and table-introspection query templates.

## Gotchas

- Rust is a control and safety tool here, not a speed win over `psql`.
- If `sql-read` is missing, reapply the profile so the packaged helper is rebuilt and activated.
- Blanket approval should target `sql-read run`, not `sql-read target`.
- Keep env-var assignment, `target upsert`, and `run` as separate commands.
- `run` does not accept raw DSNs, raw SQLite paths, or env-var target flags; configure the target first.
- Read-only enforcement in the helper is defense-in-depth, not a substitute for least-privilege credentials.
- Postgres queries with duplicate column names are rejected; alias duplicate columns before running them.

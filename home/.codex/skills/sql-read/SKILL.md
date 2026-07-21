---
name: sql-read
description: Use when a user needs live read-only Postgres or SQLite inspection; configure a named read-only target once, then use the blanket-approvable `sql-read run` path for later queries.
---

# SQL Read

Use the `sql-read` helper from the active Nix profile to inspect Postgres or SQLite data in read-only mode.

Do not use it for writes, migrations, backfills, administration, or general interactive shell work.

## Safety boundary

- Treat `sql-read run` as the only blanket-approvable command prefix.
- Treat every `sql-read target ...` command as explicit setup or state management outside that blanket approval.
- Never place a DSN, password, token, or SQLite path in command text. Raw `--dsn` and `--sqlite-db-path` inputs are rejected.
- Require the connection value to exist in the helper process environment before target setup. The user may arrange this through shell startup configuration, a secret manager, or another out-of-band mechanism.
- Do not run `export ...` in a separate tool call and assume it will persist; tool calls commonly start separate processes. Do not prefix a tool command with a secret-bearing assignment because that exposes the value in command text.
- If the required environment variable is absent, stop and ask the user to arrange it out of band. Pass only its variable name to `target upsert`.

The helper persists the resolved connection value in `targets.json`. On Unix, it sets the state directory to mode `0700` and the store to `0600`; still use least-privilege database credentials.

## State location

Omit `--state-dir` normally. The CLI resolves state in this order:

1. `--state-dir <DIR>`
2. `SQL_READ_STATE_DIR`
3. `$XDG_STATE_HOME/sql-read`
4. `$HOME/.local/state/sql-read`

This shared XDG-owned default survives managed skill refreshes and works across Codex and Claude. Use the explicit flag or `SQL_READ_STATE_DIR` only when isolation is required.

## Workflow

1. Start with schema inspection.
   - Use the bundled query templates in `assets/queries/`.
   - Load the relevant engine notes from `references/postgres.md` or `references/sqlite.md` only when needed.
2. Configure the target once.
   - Postgres: `sql-read target upsert --name prod-readonly --engine postgres --dsn-env-var PROD_READONLY_URL`
   - SQLite: `sql-read target upsert --name local-app --engine sqlite --sqlite-db-path-env-var LOCAL_APP_DB`
   - Pass an environment-variable name only after verifying that its value was arranged out of band.
3. Keep queries narrow.
   - Ask for aggregates, counts, or explicit filters before scanning large tables.
   - Add an explicit `limit` in the SQL unless the query is already aggregate-only.
4. Prefer JSON output.
   - Use `--format json` by default so the agent sees compact, structured rows.
   - Switch to `table` only when the user explicitly wants a human-readable table.
5. Run read-only queries through the stored target.
   - `sql-read run --target <name> --file <query.sql> --format json`
   - Later `run` calls do not require the env var to still exist.
6. Inspect or remove targets explicitly.
   - `sql-read target list`
   - `sql-read target remove --name local-app`

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
- `run` accepts only a configured target name; it does not accept connection values or environment-variable target flags.
- Read-only enforcement in the helper is defense-in-depth, not a substitute for least-privilege credentials.
- Postgres queries with duplicate column names are rejected; alias duplicate columns before running them.

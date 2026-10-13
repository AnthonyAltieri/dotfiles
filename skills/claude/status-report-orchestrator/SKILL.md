---
name: status-report-orchestrator
description: Publish this spawn-orchestrator session's status as a dashboard page on the shared "Orchestrator Status Board" Design canvas, and keep it current for the rest of the run. Use only when the user invokes /status-report-orchestrator or asks for the orchestrator's status dashboard or board page; abort when this session is not running spawn-orchestrator.
---

# Status Report Orchestrator

Companion to `$spawn-orchestrator`. One shared Design canvas, the **Orchestrator Status Board**, holds one page per orchestrator session. This session finds or creates the board, finds or creates its own page, writes the dashboard from the standard template, and refreshes it whenever the orchestrator reports.

## Gate

Continue only when this session is running `$spawn-orchestrator`: the skill was invoked in this conversation and the run state records at least one dispatched or queued issue. Otherwise reply with one line, `No spawn-orchestrator run in this session; nothing to report.`, and stop. Do not create the board, a page, or a run.

## Find or Create the Board

1. Read the board URL from `~/.cache/spawn-orchestrator/status-board-url`.
2. If the file is missing, or a `read` of that URL fails, `list` artifacts with `type: "Design"` and take the one titled `Orchestrator Status Board`. Write its URL to the file.
3. If none exists, run the Artifact `quickstart` with intent `design`, create the canvas from the returned Design `type_url` with `title: "Orchestrator Status Board"`, and write its URL to the file. Follow the Design type's instructions for every write.

Never create a second board while one exists.

## Find or Create This Session's Page

- **Session key:** the first 8 characters of `$CLAUDE_CODE_SESSION_ID`.
- **Page:** id `s-<session key>`, name `<run id> · <epic key> · <YYYY-MM-DD>`.
- **Artboard:** `project/sessions/<run id>-<session key>/Status.dc.html`, with `page` set to the page id, `expand: "fill"`, `is_interactive: true`, `x: 0`, `y: 0`, `w: 1280`, and `h` its height at that width.

Read `project/canvas.json`. If the page or artboard is missing, add both to `pages`, `boards`, and `order`, keeping every other key and entry as read, and publish the index with the new artboard. Other orchestrator sessions write the same index: if a publish is refused, re-read the index, re-apply only this session's entries, and publish again. Never touch another session's page, artboard, or notes.

A canvas holds at most 40 pages. When adding this session's page would exceed that, ask the user once which settled sessions' pages to remove, listing each with its run id and last update; remove only those, and only their page, artboard, and `order` entries.

## Write the Dashboard

Copy `assets/status.dc.html` beside this skill to the artboard path on first publish. It renders the run header, a pinned "Needs you" panel, counts with the `Idle capacity` and `Next` lines, and the issues in three switchable views: Table, Lanes (kanban), and Timeline (with a workers-active chart). Its markup and logic are fixed. On every write, change only the object between `// RUN:BEGIN` and `// RUN:END`, and set the `showExample` default in `data-props` to `false`:

```js
return {
  run, epic, epicTitle, epicUrl,          // run id; Linear epic key, title, URL
  repo, base, mode, tests, session,       // owner/name; base branch; 'automerge' | 'draft PRs'; 'default' | '--min-tests'; session key
  started, now, updated, elapsed,         // 'HH:MM' local 24h (past midnight write 24:10, 25:30); updated adds the zone
  idle, next,                             // the orchestrator's last Idle capacity and Next lines, verbatim
  issueUrlBase, prUrlBase,                // prefixes the issue key and PR number are appended to
  needs: [{ n, key, kind, age, ask, rec, options: [] }],
  issues: [{ key, title, state, model, start, end, pr, merge, waits }]
};
```

- `needs`: every open Sandbox Denials or Stalled Work question and every blocked or parked issue, with its resume condition in `ask`. `kind` is `Sandbox denial`, `Stalled`, `Blocked`, or `Parked`; `options` lists the choices offered in chat, recommended first.
- `issues`: one entry per issue the run owns. `state` is `running`, `queued`, `blocked`, `parked`, `pr-opened`, or `merged`. `model` is `codex` or `opus`. Omit `start` until dispatch and `end` until terminal. `merge` is the short merge SHA, set only for `merged`. `waits` names the blocking issue for queued work.

Take each value from the run ledger (`~/.cache/spawn-orchestrator/<run id>/state.md`), `codex_worker.py status`, `gh pr view`, and Linear. Never fill a value from a worker's claim the orchestrator has not verified; show it as pending instead. Keep each "Needs you" item's number stable until it is answered, because the user replies by number.

## Keep It Current

After the first publish, refresh the page:

- on every `$spawn-orchestrator` Report trigger: each dispatch, verified merge or PR, new blocker, Sandbox Denials or Stalled Work question, answered decision, wave boundary, and the end of the run;
- when the user asks for status in any words ("status?", "how's it going", "what's left"): refresh first, then answer in chat with the orchestrator's routine status (the `Run:` block where the orchestrator posts one), the open "Needs you" items, and the page link;
- after a compaction or resume, rebuilt from the ledger, `gh`, and Linear rather than from memory.

Publish only this session's artboard file; send the index only when adding the page. Refreshing never delays monitoring or dispatch: if a publish fails twice, say so once in the next chat report and keep orchestrating.

When the run settles, publish a final refresh with every row terminal and the update time.

## Updating the Template

`assets/status.dc.html` is the source of truth; pages never read the template from the board. When the user changes the board's **Chosen** frame and asks to carry the change into the skill:

1. Read `project/template/Chosen.dc.html` from the board.
2. Write it to `assets/status.dc.html`, keeping the asset's existing example `RUN` block. Board frames carry real run data, which must not enter this public repository.
3. Diff the two files outside the `RUN` block; they must be identical. Run the template's script for the Table, Lanes, and Timeline views before committing.

## Reply

After the first publish, reply with the board link, the page name, and one line saying the page refreshes on each report. Later refreshes add nothing to chat beyond the orchestrator's own report. The board is private; if the user wants others to see it, they share it from the page's Share menu.

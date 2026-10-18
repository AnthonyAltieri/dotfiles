#!/usr/bin/env python3
"""Read-only view of the spawn-orchestrator sessions on this machine.

Every source is a file the user's own sessions already write, so building the
view costs no model tokens:
- ~/.cache/claude-sessions/<sessionId>.json: per-session state from the
  session_state.py hook (status, the question or permission prompt waiting on
  the user, orchestrator role, dispatched workers, and Haiku's verdict on the
  last message of each orchestrator turn: needs the user, waiting, or done).
- ~/.claude/sessions/<pid>.json: the live session registry (name, process, status).
- Worker files: <run>/<issue>/{pid,exit_code,events.jsonl} for Codex workers and
  ~/.claude/projects/*/<sessionId>/subagents/*.jsonl for Opus workers.
- ~/.cache/spawn-orchestrator/<run>/run.json, when an orchestrator keeps one:
  the settled flag and its run directory only. Its issue states are written by
  hand and drift, so no column reads them.

Subcommands:
  whoami    print this session's name; exit 2 unless the user named it
  snapshot  render the fleet as a markdown table, a terminal table, or JSON
  watch     print one line per health change, forever; a re-armed watch
            resumes from what the last one reported and repeats nothing
  pane      open a herdr or tmux pane that redraws the terminal table every minute
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shlex
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Iterable

SESSIONS_DIR = Path.home() / ".claude" / "sessions"
PROJECTS_DIR = Path.home() / ".claude" / "projects"
STATE_DIR = Path.home() / ".cache" / "claude-sessions"
RUNS_DIR = Path.home() / ".cache" / "spawn-orchestrator"
WATCH_DIR = Path.home() / ".cache" / "root-orchestrator"

STALL_AFTER = 20 * 60
HUNG_AFTER = 20 * 60
NEEDS_ALERT_AFTER = 10 * 60
GONE_VISIBLE_FOR = 12 * 3600

GROUP_ORDER = ("dead", "hung", "needs-you", "stalled", "ok", "settled")
GROUP_TITLES = {"dead": "dead", "hung": "hung", "needs-you": "needs you", "stalled": "stalled", "ok": "ok", "settled": "done"}
COLUMNS = ("Health", "Orchestrator", "Running", "Done", "Note")


@dataclass(frozen=True)
class Session:
    """A live registry entry."""

    name: str
    session_id: str
    cwd: str
    alive: bool
    busy: bool
    status_at: float | None
    named_by_user: bool
    transcript_mtime: float | None
    subagent_mtime: float | None


@dataclass(frozen=True)
class Waiting:
    kind: str  # question | permission
    text: str
    since: float


@dataclass(frozen=True)
class Triage:
    verdict: str  # pending | you | wait | done | failed
    summary: str
    since: float


@dataclass(frozen=True)
class Hooked:
    """What the session_state.py hook recorded for one session."""

    session_id: str
    name: str
    cwd: str
    status: str  # busy | idle | ended, or "" before the hook has seen a turn start or end
    status_at: float | None
    waiting: Waiting | None
    orchestrator: bool
    codex_dirs: tuple[str, ...]
    opus_running: int
    opus_done: int
    updated_at: float
    background_tasks: int = 0
    triage: Triage | None = None


@dataclass(frozen=True)
class Run:
    """The optional run.json an orchestrator keeps."""

    run_id: str
    session_name: str
    repo_path: str
    settled: bool
    updated_at: float | None


@dataclass(frozen=True)
class Workers:
    running: int = 0
    done: int = 0


@dataclass(frozen=True)
class View:
    name: str
    session: Session | None
    hooked: Hooked | None
    run: Run | None
    workers: Workers = field(default_factory=Workers)


@dataclass(frozen=True)
class Health:
    state: str
    detail: str
    alert: bool = False


# ---- pure logic -------------------------------------------------------------


def age(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 48 * 3600:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


def latest(*stamps: float | None) -> float | None:
    present = [s for s in stamps if s is not None]
    return max(present) if present else None


def classify(view: View, now: float) -> Health:
    s, h, run, w = view.session, view.hooked, view.run, view.workers
    if run is not None and run.settled:
        return Health("settled", f"settled {age(now - (run.updated_at or now))} ago")
    if (h is not None and h.status == "ended") or s is None or not s.alive:
        last = latest(h.updated_at if h else None, s.status_at if s else None, run.updated_at if run else None)
        return Health("dead", f"session gone · last seen {age(now - (last or now))} ago", alert=True)
    if h is not None and h.waiting is not None:
        what = "question" if h.waiting.kind == "question" else "permission"
        open_for = now - h.waiting.since
        return Health("needs-you", f"{what}: {h.waiting.text} · {age(open_for)}", alert=open_for > NEEDS_ALERT_AFTER)
    t = h.triage if h is not None and h.status == "idle" else None
    if t is not None and t.verdict == "you":
        open_for = now - t.since
        return Health("needs-you", f"{t.summary} · {age(open_for)}", alert=open_for > NEEDS_ALERT_AFTER)
    if t is not None and t.verdict == "done" and not w.running and not h.background_tasks:
        return Health("settled", f"finished: {t.summary} · {age(now - t.since)} ago")
    if t is not None and t.verdict in ("wait", "done"):
        return Health("ok", f"waiting: {t.summary}")
    # A session that loaded the hook mid-turn has no status yet; the registry knows.
    known = h is not None and h.status in ("busy", "idle")
    busy = h.status == "busy" if known else s.busy
    if busy and s.transcript_mtime is not None and now - s.transcript_mtime > HUNG_AFTER and not w.running:
        return Health("hung", f"busy but silent for {age(now - s.transcript_mtime)}", alert=True)
    idle_since = (h.status_at if known else s.status_at) or now
    quiet_since = latest(idle_since, s.subagent_mtime)
    if not busy and not w.running and now - (quiet_since or now) > STALL_AFTER:
        return Health("stalled", f"idle, nothing running for {age(now - (quiet_since or now))}", alert=True)
    note = "working" if busy else f"waiting on {w.running} worker{'s' if w.running != 1 else ''}" if w.running else "idle"
    return Health("ok", note)


def transitions(previous: dict[str, Health], current: dict[str, Health]) -> list[str]:
    lines = []
    for name, health in current.items():
        before = previous.get(name)
        if before is None or before.state != health.state or (health.alert and not before.alert):
            was = before.state if before else "new"
            flag = "⚠ " if health.alert else ""
            lines.append(f"{flag}{name}: {was} → {health.state} · {health.detail}")
    for name in previous.keys() - current.keys():
        lines.append(f"{name}: {previous[name].state} → gone from scope")
    return lines


def rows(views: list[View], now: float) -> list[tuple[Health, list[str]]]:
    """One row of cells per orchestrator, most urgent first."""
    rated = sorted(((v, classify(v, now)) for v in views), key=lambda vh: (GROUP_ORDER.index(vh[1].state), vh[0].name))
    out = []
    for v, h in rated:
        note = h.detail if v.hooked else f"{h.detail} · no hook data yet"
        out.append((h, [GROUP_TITLES[h.state], v.name, str(v.workers.running), str(v.workers.done), note]))
    return out


def title_line(views: list[View], now: float, title: str) -> str:
    return f"{datetime.fromtimestamp(now).strftime('%H:%M')} · {title} · {len(views)} orchestrators"


def render_markdown(views: list[View], now: float, title: str) -> str:
    out = [f"**{title_line(views, now, title)}**", "", "| " + " | ".join(COLUMNS) + " |", "|---|---|--:|--:|---|"]
    for h, cells in rows(views, now):
        if h.alert:
            cells[0] = f"**{cells[0]}**"
        out.append("| " + " | ".join(c.replace("|", "/") for c in cells) + " |")
    return "\n".join(out)


def render_text(views: list[View], now: float, title: str, width: int = 120) -> str:
    table = [list(COLUMNS)] + [cells for _, cells in rows(views, now)]
    widths = [max(len(r[i]) for r in table) for i in range(len(COLUMNS) - 1)]
    note_width = max(20, width - sum(widths) - 2 * len(widths))
    lines = [title_line(views, now, title), ""]
    for i, r in enumerate(table):
        head = "  ".join(cell.rjust(w) if j in (2, 3) else cell.ljust(w) for j, (cell, w) in enumerate(zip(r, widths)))
        lines.append(f"{head}  {r[-1][:note_width]}")
        if i == 0:
            lines.append("  ".join("-" * w for w in widths) + "  " + "-" * min(note_width, 40))
    return "\n".join(lines)


# ---- boundary: parse local files ----------------------------------------------


def parse_time(value: object) -> float | None:
    if isinstance(value, (int, float)):
        return float(value) / (1000 if value > 1e11 else 1)
    if isinstance(value, str) and value:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    return None


def parse_hooked(data: dict) -> Hooked:
    waiting = data.get("waiting")
    opus = data.get("opus") or {}
    return Hooked(
        session_id=str(data["sessionId"]),
        name=str(data.get("name") or ""),
        cwd=str(data.get("cwd") or ""),
        status=str(data.get("status") or ""),
        status_at=parse_time(data.get("statusAt")),
        waiting=Waiting(str(waiting.get("kind")), str(waiting.get("text") or ""), float(waiting.get("since") or 0)) if waiting else None,
        orchestrator=bool(data.get("orchestrator")),
        codex_dirs=tuple(str(d) for d in (data.get("codex") or {}).values()),
        opus_running=sum(1 for a in opus.values() if a.get("state") == "running"),
        opus_done=sum(1 for a in opus.values() if a.get("state") == "done"),
        updated_at=float(data.get("updatedAt") or 0),
        background_tasks=int(data.get("backgroundTasks") or 0),
        triage=parse_triage(data.get("triage")),
    )


def parse_triage(data: object) -> Triage | None:
    if not isinstance(data, dict) or data.get("verdict") not in ("pending", "you", "wait", "done", "failed"):
        return None
    return Triage(str(data["verdict"]), str(data.get("summary") or ""), float(data.get("since") or 0))


def parse_run(path: Path, data: dict, written_at: float | None = None) -> Run:
    return Run(
        run_id=str(data.get("run") or path.parent.name),
        session_name=str(data["sessionName"]),
        repo_path=str(data.get("repoPath", "")),
        settled=bool(data.get("settled", False)),
        updated_at=latest(parse_time(data.get("updatedAt")), written_at),
    )


def newest_mtime(paths: Iterable[Path]) -> float | None:
    stamps = []
    for p in paths:
        try:
            stamps.append(p.stat().st_mtime)
        except OSError:
            continue
    return max(stamps) if stamps else None


def pid_alive(pid: object) -> bool:
    if not isinstance(pid, int):
        return False
    try:
        os.kill(pid, 0)
    except PermissionError:
        return True
    except OSError:
        return False
    return True


def codex_workers(dirs: Iterable[Path]) -> Workers:
    running = done = 0
    for d in dirs:
        try:
            pid = int((d / "pid").read_text().strip()) if (d / "pid").exists() else None
        except (OSError, ValueError):
            pid = None
        if pid_alive(pid):
            running += 1
        elif (d / "exit_code").exists():
            done += 1
    return Workers(running, done)


def load_sessions(warnings: list[str]) -> dict[str, Session]:
    """Live registry entries keyed by session id."""
    sessions: dict[str, Session] = {}
    for path in sorted(SESSIONS_DIR.glob("*.json")):
        try:
            d = json.loads(path.read_text())
            sid = str(d["sessionId"])
        except (OSError, ValueError, KeyError) as exc:
            warnings.append(f"skipped {path}: {exc}")
            continue
        sessions[sid] = Session(
            name=str(d.get("name") or sid[:8]),
            session_id=sid,
            cwd=str(d.get("cwd", "")),
            alive=pid_alive(d.get("pid")),
            busy=d.get("status") == "busy",
            status_at=parse_time(d.get("statusUpdatedAt")),
            named_by_user=d.get("nameSource") == "user",
            transcript_mtime=newest_mtime(PROJECTS_DIR.glob(f"*/{sid}.jsonl")),
            subagent_mtime=newest_mtime(PROJECTS_DIR.glob(f"*/{sid}/subagents/*.jsonl")),
        )
    return sessions


def load_hooked(warnings: list[str]) -> dict[str, Hooked]:
    hooked: dict[str, Hooked] = {}
    for path in sorted(STATE_DIR.glob("*.json")):
        try:
            h = parse_hooked(json.loads(path.read_text()))
        except (OSError, ValueError, KeyError, TypeError, AttributeError) as exc:
            warnings.append(f"skipped {path}: {exc}")
            continue
        hooked[h.session_id] = h
    return hooked


def load_runs(warnings: list[str]) -> dict[str, Run]:
    """The newest run.json per session name."""
    runs: dict[str, Run] = {}
    for path in sorted(RUNS_DIR.glob("*/run.json")):
        try:
            run = parse_run(path, json.loads(path.read_text()), written_at=path.stat().st_mtime)
        except (OSError, ValueError, KeyError, TypeError) as exc:
            warnings.append(f"skipped {path}: {exc}")
            continue
        current = runs.get(run.session_name)
        if current is None or (run.updated_at or 0) > (current.updated_at or 0):
            runs[run.session_name] = run
    return runs


def repo_root() -> str:
    try:
        return subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return os.getcwd()


def within(path: str, repo: str) -> bool:
    if not path:
        return False
    path, repo = os.path.realpath(path), os.path.realpath(repo)
    return path == repo or path.startswith(repo + os.sep)


def own_session_id() -> str:
    return os.environ.get("CLAUDE_CODE_SESSION_ID", "")


def collect(repo: str, names: list[str], now: float, warnings: list[str]) -> list[View]:
    sessions = load_sessions(warnings)
    hooked = load_hooked(warnings)
    runs = load_runs(warnings)
    by_name: dict[str, View] = {}
    for sid in (set(hooked) | set(sessions)) - {own_session_id()}:
        s, h = sessions.get(sid), hooked.get(sid)
        name = (h.name if h and h.name else None) or (s.name if s else sid[:8])
        run = runs.get(name)
        if names:
            if name not in names:
                continue
        else:
            cwd = (h.cwd if h else "") or (s.cwd if s else "")
            is_orchestrator = (h is not None and h.orchestrator) or run is not None
            if not is_orchestrator or not (within(cwd, repo) or (run is not None and within(run.repo_path, repo))):
                continue
        dirs = {Path(d) for d in (h.codex_dirs if h else ())}
        if run is not None:
            dirs |= {p.parent for p in (RUNS_DIR / run.run_id).glob("*/events.jsonl")}
        codex = codex_workers(dirs)
        workers = Workers(codex.running + (h.opus_running if h else 0), codex.done + (h.opus_done if h else 0))
        last = latest(h.updated_at if h else None, s.status_at if s else None, run.updated_at if run else None) or 0
        gone = s is None or not s.alive or (run is not None and run.settled)
        if gone and not names and now - last > GONE_VISIBLE_FOR:
            continue
        current = by_name.get(name)
        if current is None or (s is not None and s.alive):
            by_name[name] = View(name, s, h, run, workers)
    return [by_name[n] for n in sorted(by_name)]


# ---- commands -------------------------------------------------------------------


def cmd_whoami(_: argparse.Namespace) -> int:
    me = load_sessions([]).get(own_session_id())
    if me is None:
        print("unknown: no session registry entry for CLAUDE_CODE_SESSION_ID")
        return 2
    print(f"{me.name} ({'named by user' if me.named_by_user else 'generated name'})")
    return 0 if me.named_by_user else 2


def cmd_snapshot(args: argparse.Namespace) -> int:
    warnings: list[str] = []
    now = time.time()
    repo = args.repo or repo_root()
    views = collect(repo, args.sessions, now, warnings)
    if args.format == "json":
        print(json.dumps([{"name": v.name, **classify(v, now).__dict__} for v in views], indent=2))
    elif args.format == "text":
        print(render_text(views, now, Path(repo).name, args.width))
    else:
        print(render_markdown(views, now, Path(repo).name))
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    return 0


def watch_state_path(repo: str, sessions: list[str]) -> Path:
    scope = json.dumps([str(Path(repo).resolve()), sorted(sessions)])
    return WATCH_DIR / f"{hashlib.sha256(scope.encode()).hexdigest()[:16]}.json"


def load_seen(path: Path) -> dict[str, Health]:
    """The health the previous watch on this scope last reported, so a re-armed watch repeats nothing."""
    try:
        return {name: Health(**health) for name, health in json.loads(path.read_text()).items()}
    except (OSError, ValueError, TypeError):
        return {}


def save_seen(path: Path, current: dict[str, Health]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps({name: health.__dict__ for name, health in current.items()}))
    tmp.replace(path)


def cmd_watch(args: argparse.Namespace) -> int:
    repo = args.repo or repo_root()
    seen_path = watch_state_path(repo, args.sessions)
    previous = load_seen(seen_path)
    reported: set[str] = set()
    while True:
        warnings: list[str] = []
        try:
            now = time.time()
            current = {v.name: classify(v, now) for v in collect(repo, args.sessions, now, warnings)}
            for line in transitions(previous, current):
                print(line, flush=True)
            if current != previous:
                save_seen(seen_path, current)
            previous = current
        except Exception as exc:  # the watch must outlive one bad read
            print(f"fleet error: {exc}", file=sys.stderr, flush=True)
        for w in warnings:
            if w not in reported:
                reported.add(w)
                print(f"warning: {w}", flush=True)
        time.sleep(args.interval)


def pane_rows(orchestrators: int) -> int:
    """Rows the pane needs: title, blank, header, rule, one per orchestrator, two for borders, one to spare."""
    return orchestrators + 7


def herdr_split_ratio(rows: int, total: int) -> float:
    """The share herdr's --ratio leaves to the current pane, so the new pane gets `rows`."""
    return min(0.9, max(0.5, 1 - rows / max(total, 1)))


def cmd_pane(args: argparse.Namespace) -> int:
    repo = args.repo or repo_root()
    rows = pane_rows(len(collect(repo, args.sessions, time.time(), [])))
    table = [sys.executable, os.path.abspath(__file__), "snapshot", "--format", "text", "--repo", repo]
    if args.sessions:
        table += ["--sessions", *args.sessions]
    command = f"watch -t -n {args.interval} {shlex.quote(shlex.join(table))}"
    if os.environ.get("HERDR_ENV") == "1" and shutil.which("herdr"):
        current = subprocess.run(["herdr", "pane", "current"], capture_output=True, text=True, check=True)
        total = int(json.loads(current.stdout)["result"]["pane"]["scroll"]["viewport_rows"])
        ratio = f"{herdr_split_ratio(rows, total):.2f}"
        split = subprocess.run(["herdr", "pane", "split", "--current", "--direction", "down", "--ratio", ratio, "--no-focus"],
                               capture_output=True, text=True, check=True)
        pane = json.loads(split.stdout)["result"]["pane"]["pane_id"]
        subprocess.run(["herdr", "pane", "run", pane, command], capture_output=True, text=True, check=True)
    elif os.environ.get("TMUX") and shutil.which("tmux"):
        pane = subprocess.run(["tmux", "split-window", "-d", "-v", "-l", str(rows), "-P", "-F", "#{pane_id}", command],
                              capture_output=True, text=True, check=True).stdout.strip()
    else:
        print(f"no herdr or tmux here; run this in a terminal:\n{command}")
        return 3
    print(f"pane {pane}: {command}")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("whoami").set_defaults(func=cmd_whoami)
    for name, func in (("snapshot", cmd_snapshot), ("watch", cmd_watch), ("pane", cmd_pane)):
        p = sub.add_parser(name)
        p.add_argument("--repo", help="repository the orchestrators work on (default: this checkout)")
        p.add_argument("--sessions", nargs="*", default=[], help="explicit orchestrator session names")
        p.set_defaults(func=func)
    snapshot = sub.choices["snapshot"]
    snapshot.add_argument("--format", choices=("markdown", "text", "json"), default="markdown")
    snapshot.add_argument("--width", type=int, default=int(os.environ.get("COLUMNS", "120")), help="text table width")
    sub.choices["watch"].add_argument("--interval", type=int, default=60)
    sub.choices["pane"].add_argument("--interval", type=int, default=60, help="seconds between redraws")
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

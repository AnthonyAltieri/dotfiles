#!/usr/bin/env python3
"""Read-only view of the spawn-orchestrator sessions on this machine.

Sources, all written by the user's own Claude Code sessions:
- ~/.claude/sessions/<pid>.json: live session registry (name, nameSource, status, sessionId).
- ~/.cache/spawn-orchestrator/<run>/run.json: each orchestrator's run state, written on every report.
- Worker activity: <run>/<issue>/{events.jsonl,pid,exit_code} (Codex) and
  ~/.claude/projects/*/<sessionId>/subagents/*.jsonl (Opus subagents).

Subcommands:
  whoami    print this session's name; exit 2 unless the user named it
  snapshot  render the fleet as health groups, a table, or JSON
  watch     print one line per health change, forever
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime
from pathlib import Path
from typing import Iterable

SESSIONS_DIR = Path.home() / ".claude" / "sessions"
PROJECTS_DIR = Path.home() / ".claude" / "projects"
RUNS_DIR = Path.home() / ".cache" / "spawn-orchestrator"

STALL_AFTER = 20 * 60
HUNG_AFTER = 20 * 60
DRIFT_AFTER = 20 * 60
NEEDS_ALERT_AFTER = 30 * 60
SETTLED_VISIBLE_FOR = 12 * 3600

ACTIVE_STATES = ("running", "queued")
DONE_STATES = ("merged", "pr-opened")
GROUP_ORDER = ("dead", "hung", "needs-you", "drift", "stalled", "blocked", "no-ledger", "ok", "settled")
GROUP_TITLES = {
    "dead": "DEAD",
    "hung": "HUNG",
    "needs-you": "NEEDS YOU",
    "drift": "DRIFT",
    "stalled": "STALLED",
    "blocked": "BLOCKED",
    "no-ledger": "NO LEDGER",
    "ok": "OK",
    "settled": "DONE",
}


@dataclass(frozen=True)
class Session:
    name: str
    session_id: str
    cwd: str
    alive: bool
    busy: bool
    named_by_user: bool
    transcript_mtime: float | None
    subagent_mtime: float | None


@dataclass(frozen=True)
class Need:
    n: int
    key: str
    kind: str
    opened_at: float | None
    awaits: str = "user"  # user | external: only "user" needs make an orchestrator need-you


@dataclass(frozen=True)
class Run:
    run_id: str
    session_name: str
    repo_path: str
    settled: bool
    updated_at: float | None
    last_progress_at: float | None
    counts: dict[str, int]
    needs: tuple[Need, ...]
    events_mtime: float | None
    exited: tuple[tuple[str, float], ...] = ()  # (issue, exit time) of Codex workers run.json still calls running


@dataclass(frozen=True)
class View:
    name: str
    run: Run | None
    session: Session | None


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


def count_line(counts: dict[str, int]) -> str:
    done = sum(counts.get(s, 0) for s in DONE_STATES)
    blocked = counts.get("blocked", 0) + counts.get("parked", 0)
    parts = [f"▶{counts.get('running', 0)}", f"✓{done}"]
    if blocked:
        parts.append(f"⚠{blocked}")
    if counts.get("queued", 0):
        parts.append(f"◻{counts['queued']}")
    return " ".join(parts)


def classify(view: View, now: float) -> Health:
    run, session = view.run, view.session
    if run is None:
        return Health("no-ledger", "no run.json names this session")
    if run.settled:
        return Health("settled", f"{count_line(run.counts)} · settled {age(now - (run.updated_at or now))} ago")
    if session is None or not session.alive:
        return Health("dead", f"session gone · last update {age(now - (run.updated_at or now))} ago", alert=True)
    if session.busy and session.transcript_mtime is not None and now - session.transcript_mtime > HUNG_AFTER:
        return Health("hung", f"busy but silent for {age(now - session.transcript_mtime)}", alert=True)
    asks = [n for n in run.needs if n.awaits == "user"]
    if asks:
        oldest = min((n.opened_at for n in asks if n.opened_at is not None), default=now)
        kinds = ", ".join(f"{n.n}. {n.key} {n.kind.lower()}" for n in asks)
        return Health("needs-you", f"{kinds} · open {age(now - oldest)} → answer in {view.name}", alert=now - oldest > NEEDS_ALERT_AFTER)
    drifted = [(key, at) for key, at in run.exited if now - at > DRIFT_AFTER]
    if drifted:
        keys = ", ".join(f"{key} exited {age(now - at)} ago" for key, at in drifted)
        return Health("drift", f"run.json says running: {keys} → refresh in {view.name}", alert=True)
    progress = latest(run.last_progress_at, run.updated_at, run.events_mtime, session.subagent_mtime)
    active = sum(run.counts.get(s, 0) for s in ACTIVE_STATES)
    if active and (progress is None or now - progress > STALL_AFTER):
        quiet = "ever" if progress is None else age(now - progress)
        return Health("stalled", f"{count_line(run.counts)} · nothing moved for {quiet}", alert=True)
    moved = "never" if progress is None else f"{age(now - progress)} ago"
    waiting = [n for n in run.needs if n.awaits != "user"]
    if waiting:
        kinds = ", ".join(f"{n.n}. {n.key} {n.kind.lower()}" for n in waiting)
        return Health("blocked", f"{count_line(run.counts)} · {kinds} · not waiting on you · moved {moved}")
    return Health("ok", f"{count_line(run.counts)} · moved {moved}")


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


def render_groups(views: list[View], now: float, title: str) -> str:
    rated = [(v, classify(v, now)) for v in views]
    out = [f"{datetime.fromtimestamp(now).strftime('%H:%M')} · {title} · {len(views)} orchestrators"]
    width = max((len(v.name) for v in views), default=0)
    run_width = max((len(v.run.run_id) for v in views if v.run), default=1)
    for state in GROUP_ORDER:
        members = [(v, h) for v, h in rated if h.state == state]
        if not members:
            continue
        out.append(GROUP_TITLES[state])
        for v, h in members:
            run_id = v.run.run_id if v.run else "—"
            out.append(f"  {v.name:<{width}}  {run_id:<{run_width}}  {h.detail}")
    return "\n".join(out)


def render_table(views: list[View], now: float) -> str:
    out = [
        "| Orchestrator | Run | ▶ run | ✓ done | ⚠ you | ◻ queued | Last progress | Health |",
        "|---|---|---|---|---|---|---|---|",
    ]
    for v in views:
        h = classify(v, now)
        if v.run is None:
            out.append(f"| {v.name} | — | ? | ? | ? | ? | — | {h.state} |")
            continue
        c = v.run.counts
        progress = latest(v.run.last_progress_at, v.run.updated_at, v.run.events_mtime, v.session.subagent_mtime if v.session else None)
        out.append(
            f"| {v.name} | {v.run.run_id} | {c.get('running', 0)} | {sum(c.get(s, 0) for s in DONE_STATES)} "
            f"| {max(len(v.run.needs), c.get('blocked', 0) + c.get('parked', 0))} | {c.get('queued', 0)} | {age(now - progress) if progress else '—'} "
            f"| {'**' + h.state + '**' if h.alert else h.state} |"
        )
    return "\n".join(out)


# ---- boundary: parse local files ----------------------------------------------


def parse_time(value: object) -> float | None:
    if isinstance(value, (int, float)):
        return float(value) / (1000 if value > 1e11 else 1)
    if isinstance(value, str) and value:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp()
    return None


def awaits_of(need: dict) -> str:
    """Who a need waits on. Older ledgers lack the field: Blocked means an external dependency, the rest are questions."""
    awaits = need.get("awaits")
    if awaits in ("user", "external"):
        return str(awaits)
    return "external" if str(need.get("kind")) == "Blocked" else "user"


def parse_run(path: Path, data: dict, events_mtime: float | None, written_at: float | None = None, exited: dict[str, float] | None = None) -> Run:
    counts: dict[str, int] = {}
    for issue in data.get("issues", []):
        state = str(issue.get("state", "queued"))
        counts[state] = counts.get(state, 0) + 1
    needs = tuple(
        Need(
            int(n.get("n", i + 1)),
            str(n.get("key", "?")),
            str(n.get("kind", "decision")),
            parse_time(n.get("openedAt")),
            awaits_of(n),
        )
        for i, n in enumerate(data.get("needs", []))
    )
    return Run(
        run_id=str(data.get("run") or path.parent.name),
        session_name=str(data["sessionName"]),
        repo_path=str(data.get("repoPath", "")),
        settled=bool(data.get("settled", False)),
        updated_at=latest(parse_time(data.get("updatedAt")), written_at),
        last_progress_at=parse_time(data.get("lastProgressAt")),
        counts=counts,
        needs=needs,
        events_mtime=events_mtime,
        exited=tuple((str(i["key"]), exited[str(i["key"])]) for i in data.get("issues", []) if i.get("state") == "running" and str(i.get("key")) in (exited or {})),
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


def load_sessions(warnings: list[str]) -> dict[str, Session]:
    sessions: dict[str, Session] = {}
    for path in sorted(SESSIONS_DIR.glob("*.json")):
        try:
            d = json.loads(path.read_text())
            sid = str(d["sessionId"])
            name = str(d.get("name") or "")
        except (OSError, ValueError, KeyError) as exc:
            warnings.append(f"skipped {path}: {exc}")
            continue
        if not name:
            continue
        sessions[name] = Session(
            name=name,
            session_id=sid,
            cwd=str(d.get("cwd", "")),
            alive=pid_alive(d.get("pid")),
            busy=d.get("status") == "busy",
            named_by_user=d.get("nameSource") == "user",
            transcript_mtime=newest_mtime(PROJECTS_DIR.glob(f"*/{sid}.jsonl")),
            subagent_mtime=newest_mtime(PROJECTS_DIR.glob(f"*/{sid}/subagents/*.jsonl")),
        )
    return sessions


def exited_workers(run_dir: Path) -> dict[str, float]:
    """Exit time of each Codex worker in the run whose turn has ended."""
    out = {}
    for exit_file in run_dir.glob("*/exit_code"):
        pid_file = exit_file.parent / "pid"
        try:
            live = pid_file.exists() and pid_alive(int(pid_file.read_text().strip()))
            if not live:
                out[exit_file.parent.name] = exit_file.stat().st_mtime
        except (OSError, ValueError):
            continue
    return out


def load_runs(warnings: list[str]) -> dict[str, Run]:
    runs: dict[str, Run] = {}
    for path in sorted(RUNS_DIR.glob("*/run.json")):
        try:
            run = parse_run(
                path,
                json.loads(path.read_text()),
                newest_mtime(path.parent.glob("*/events.jsonl")),
                written_at=path.stat().st_mtime,
                exited=exited_workers(path.parent),
            )
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


def own_session(sessions: dict[str, Session]) -> Session | None:
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    return next((s for s in sessions.values() if s.session_id == sid), None)


def collect(repo: str, names: list[str], now: float, warnings: list[str]) -> list[View]:
    sessions = load_sessions(warnings)
    runs = load_runs(warnings)
    me = own_session(sessions)
    if names:
        chosen = names
    else:
        chosen = [
            name
            for name, run in runs.items()
            if os.path.realpath(run.repo_path) == os.path.realpath(repo)
            and (not run.settled or now - (run.updated_at or 0) < SETTLED_VISIBLE_FOR)
        ]
    if me is not None:
        chosen = [n for n in chosen if n != me.name]
    return [View(name, runs.get(name), sessions.get(name)) for name in sorted(chosen)]


# ---- commands -------------------------------------------------------------------


def cmd_whoami(_: argparse.Namespace) -> int:
    warnings: list[str] = []
    me = own_session(load_sessions(warnings))
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
        print(json.dumps([{"name": v.name, "run": v.run.run_id if v.run else None, **classify(v, now).__dict__} for v in views], indent=2))
    elif args.format == "table":
        print(render_table(views, now))
    else:
        print(render_groups(views, now, Path(repo).name))
    for w in warnings:
        print(f"warning: {w}", file=sys.stderr)
    return 0


def cmd_watch(args: argparse.Namespace) -> int:
    repo = args.repo or repo_root()
    previous: dict[str, Health] = {}
    reported: set[str] = set()
    while True:
        warnings: list[str] = []
        try:
            now = time.time()
            current = {v.name: classify(v, now) for v in collect(repo, args.sessions, now, warnings)}
            if not previous:
                summary = ", ".join(f"{n} {h.state}" for n, h in current.items()) or "none"
                print(f"watching {len(current)} orchestrators: {summary}", flush=True)
                for name, health in current.items():
                    if health.alert:
                        print(f"⚠ {name}: {health.state} · {health.detail}", flush=True)
            else:
                for line in transitions(previous, current):
                    print(line, flush=True)
            previous = current
        except Exception as exc:  # the watch must outlive one bad read
            print(f"fleet error: {exc}", file=sys.stderr, flush=True)
        for w in warnings:
            if w not in reported:
                reported.add(w)
                print(f"warning: {w}", flush=True)
        time.sleep(args.interval)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("whoami").set_defaults(func=cmd_whoami)
    for name, func in (("snapshot", cmd_snapshot), ("watch", cmd_watch)):
        p = sub.add_parser(name)
        p.add_argument("--repo", help="repository the orchestrators work on (default: this checkout)")
        p.add_argument("--sessions", nargs="*", default=[], help="explicit orchestrator session names")
        p.set_defaults(func=func)
    sub.choices["snapshot"].add_argument("--format", choices=("groups", "table", "json"), default="groups")
    sub.choices["watch"].add_argument("--interval", type=int, default=60)
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

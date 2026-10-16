#!/usr/bin/env python3
"""Own a spawn-orchestrator run's run.json.

The orchestrator reports events; this script writes the file. Every write
fills the values an agent would otherwise copy by hand: timestamps, session
name and id, repository path, the dashboard's HH:MM fields, need ages,
`settled`, and `lastProgressAt`. Writes hold a lock and replace the file
atomically, because codex_worker.py writes the same file on dispatch.

  init     create or adopt the run header (safe to repeat after a resume)
  issue    set one issue's state and details
  need     add or close an open decision
  report   record the report's Idle capacity and Next lines
  show     print run.json with the time fields refreshed, without writing

Stored times are ISO 8601 with the local offset (`startedAt`, `startAt`,
`endAt`, `openedAt`, `updatedAt`, `lastProgressAt`). The HH:MM fields count
from midnight of the day the run started, so a run past midnight shows 24:10.
"""

from __future__ import annotations

import argparse
import fcntl
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from typing import Callable

RUNS_DIR = Path.home() / ".cache" / "spawn-orchestrator"
SESSIONS_DIR = Path.home() / ".claude" / "sessions"

STATES = ("running", "queued", "blocked", "parked", "pr-opened", "merged")
TERMINAL = ("pr-opened", "merged")
SETTLED_STATES = (*TERMINAL, "parked")
PROGRESS_STATES = ("running", *TERMINAL)
NEED_KINDS = ("Sandbox denial", "Stalled", "Blocked", "Parked")
NEED_AWAITS = ("user", "external")
HEADER_FIELDS = ("epic", "epicTitle", "epicUrl", "repo", "base", "mode", "tests", "issueUrlBase", "prUrlBase")

Data = dict


class UsageError(Exception):
    pass


# ---- pure logic -------------------------------------------------------------


def iso(moment: datetime) -> str:
    return moment.astimezone().isoformat(timespec="seconds")


def parse(value: object) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).astimezone()
    except ValueError:
        return None


def clock(moment: datetime, origin: datetime) -> str:
    midnight = origin.astimezone().replace(hour=0, minute=0, second=0, microsecond=0)
    minutes = int((moment.astimezone() - midnight).total_seconds() // 60)
    return f"{minutes // 60:02d}:{minutes % 60:02d}"


def duration(seconds: float) -> str:
    minutes = max(0, int(seconds // 60))
    hours, rest = divmod(minutes, 60)
    return f"{hours}h {rest:02d}m" if hours else f"{rest}m"


def age(seconds: float) -> str:
    seconds = max(0, int(seconds))
    if seconds < 3600:
        return f"{seconds // 60}m"
    if seconds < 48 * 3600:
        return f"{seconds // 3600}h"
    return f"{seconds // 86400}d"


def init(data: Data, run: str, header: dict, session_name: str, session_id: str, repo_path: str, now: datetime) -> Data:
    data = {**data, "run": run, "sessionName": session_name, "sessionId": session_id, "repoPath": repo_path}
    data.update({k: v for k, v in header.items() if v is not None})
    data.setdefault("startedAt", iso(now))
    data.setdefault("lastProgressAt", iso(now))
    data.setdefault("issues", [])
    data.setdefault("needs", [])
    return data


def set_issue(data: Data, key: str, state: str, now: datetime, **fields: object) -> Data:
    if state not in STATES:
        raise UsageError(f"state must be one of {', '.join(STATES)}")
    issues = [dict(i) for i in data.get("issues", [])]
    issue = next((i for i in issues if i.get("key") == key), None)
    if issue is None:
        issue = {"key": key}
        issues.append(issue)
    previous = issue.get("state")
    issue.update({k: v for k, v in fields.items() if v is not None})
    issue["state"] = state
    if state == "running" and "startAt" not in issue and "start" not in issue:
        issue["startAt"] = iso(now)
    if state in TERMINAL and previous != state:
        issue["endAt"] = iso(now)
    if state not in TERMINAL:
        issue.pop("endAt", None)
        issue.pop("end", None)
    if state != "queued":
        issue.pop("waits", None)
    data = {**data, "issues": issues}
    if state in PROGRESS_STATES and previous != state:
        data["lastProgressAt"] = iso(now)
    return data


def add_need(
    data: Data, kind: str, key: str, ask: str, rec: str, options: list[str], now: datetime, awaits: str | None = None
) -> tuple[Data, int]:
    if kind not in NEED_KINDS:
        raise UsageError(f"kind must be one of {', '.join(NEED_KINDS)}")
    needs = list(data.get("needs", []))
    n = max((int(d.get("n", 0)) for d in needs), default=0) + 1
    if awaits is None:
        awaits = "external" if kind == "Blocked" else "user"
    if awaits not in NEED_AWAITS:
        raise UsageError(f"awaits must be one of {', '.join(NEED_AWAITS)}")
    needs.append(
        {"n": n, "key": key, "kind": kind, "awaits": awaits, "openedAt": iso(now), "ask": ask, "rec": rec, "options": options}
    )
    return {**data, "needs": needs}, n


def close_need(data: Data, n: int, now: datetime) -> Data:
    needs = [d for d in data.get("needs", []) if int(d.get("n", 0)) != n]
    if len(needs) == len(data.get("needs", [])):
        raise UsageError(f"no open need {n}")
    return {**data, "needs": needs, "lastProgressAt": iso(now)}


def render(data: Data, now: datetime) -> Data:
    """Recompute every derived field from the stored times."""
    started = parse(data.get("startedAt")) or now
    issues = []
    for issue in data.get("issues", []):
        issue = dict(issue)
        for stamp, field in (("startAt", "start"), ("endAt", "end")):
            moment = parse(issue.get(stamp))
            if moment is not None:
                issue[field] = clock(moment, started)
        issues.append(issue)
    needs = []
    for need in data.get("needs", []):
        opened = parse(need.get("openedAt"))
        needs.append({**need, "age": age((now - opened).total_seconds()) if opened else need.get("age", "?")})
    states = [i.get("state") for i in issues]
    return {
        **data,
        "issues": issues,
        "needs": needs,
        "session": str(data.get("sessionId", ""))[:8],
        "settled": bool(states) and all(s in SETTLED_STATES for s in states),
        "updatedAt": iso(now),
        "started": clock(started, started),
        "now": clock(now, started),
        "updated": now.astimezone().strftime("%H:%M %Z"),
        "elapsed": duration((now - started).total_seconds()),
    }


# ---- boundary: files and session registry -----------------------------------------


def run_file(run_dir: Path) -> Path:
    return run_dir / "run.json"


def read(run_dir: Path) -> Data:
    try:
        return json.loads(run_file(run_dir).read_text())
    except FileNotFoundError:
        return {}


def update(run_dir: Path, change: Callable[[Data], Data], now: datetime | None = None) -> Data:
    """Apply `change` under the run's lock and replace run.json atomically."""
    run_dir.mkdir(parents=True, exist_ok=True)
    with open(run_dir / "run.json.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        moment = now or datetime.now().astimezone()
        data = render(change(read(run_dir)), moment)
        fd, tmp = tempfile.mkstemp(dir=run_dir, prefix=".run.json.")
        with os.fdopen(fd, "w") as out:
            json.dump(data, out, indent=2)
            out.write("\n")
        os.replace(tmp, run_file(run_dir))
    return data


def mark_running(run_dir: Path, key: str, model: str) -> None:
    """Record a dispatch for codex_worker.py; skipped when the run has no run.json yet."""
    if run_file(run_dir).exists():
        update(run_dir, lambda d: set_issue(d, key, "running", datetime.now().astimezone(), model=model))


def own_session() -> tuple[str, str]:
    sid = os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    for path in SESSIONS_DIR.glob("*.json"):
        try:
            entry = json.loads(path.read_text())
        except (OSError, ValueError):
            continue
        if entry.get("sessionId") == sid and entry.get("name"):
            return str(entry["name"]), sid
    raise UsageError("no session registry entry for CLAUDE_CODE_SESSION_ID; pass --session-name")


def repo_root() -> str:
    try:
        return subprocess.run(["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return os.getcwd()


# ---- commands -------------------------------------------------------------------


def cmd_init(args: argparse.Namespace, run_dir: Path, now: datetime) -> str:
    if args.session_name:
        name, sid = args.session_name, os.environ.get("CLAUDE_CODE_SESSION_ID", "")
    else:
        name, sid = own_session()
    header = {field: getattr(args, field) for field in HEADER_FIELDS}
    # A run adopted from a hand-written file has no startedAt; its first brief is the best start time.
    briefs = [p.stat().st_mtime for p in run_dir.glob("*/brief.md")]
    started = datetime.fromtimestamp(min(briefs)).astimezone() if briefs else now
    data = update(run_dir, lambda d: init(d, run_dir.name, header, name, sid, args.repo_path or repo_root(), started), now)
    return f"{data['run']} · {name} · {len(data['issues'])} issues"


def cmd_issue(args: argparse.Namespace, run_dir: Path, now: datetime) -> str:
    fields = dict(title=args.title, model=args.model, pr=args.pr, merge=args.merge, waits=args.waits)
    update(run_dir, lambda d: set_issue(d, args.key, args.state, now, **fields), now)
    return f"{args.key} {args.state}"


def cmd_need(args: argparse.Namespace, run_dir: Path, now: datetime) -> str:
    if args.action == "add":
        if not (args.kind and args.key and args.ask and args.rec):
            raise UsageError("need add takes --kind, --key, --ask and --rec")
        opened: list[int] = []

        def change(d: Data) -> Data:
            d, n = add_need(d, args.kind, args.key, args.ask, args.rec, args.option, now, args.awaits)
            opened.append(n)
            return d

        update(run_dir, change, now)
        return f"need {opened[0]} open"
    if args.n is None:
        raise UsageError("need close takes the need number")
    update(run_dir, lambda d: close_need(d, args.n, now), now)
    return f"need {args.n} closed"


def cmd_report(args: argparse.Namespace, run_dir: Path, now: datetime) -> str:
    update(run_dir, lambda d: {**d, "idle": args.idle, "next": args.next}, now)
    return "report recorded"


def cmd_show(_: argparse.Namespace, run_dir: Path, now: datetime) -> str:
    if not run_file(run_dir).exists():
        raise UsageError(f"no run.json in {run_dir}; run init first")
    return json.dumps(render(read(run_dir), now), indent=2)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--run", required=True, help="run id; the file is ~/.cache/spawn-orchestrator/<run>/run.json")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init", help="create or adopt the run header")
    for field in HEADER_FIELDS:
        p.add_argument("--" + "".join("-" + c.lower() if c.isupper() else c for c in field), dest=field)
    p.add_argument("--session-name", help="override the session registry lookup")
    p.add_argument("--repo-path", help="hub checkout (default: git rev-parse --show-toplevel)")
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("issue", help="set one issue's state")
    p.add_argument("key")
    p.add_argument("state", choices=STATES)
    p.add_argument("--title")
    p.add_argument("--model", choices=("codex", "opus"))
    p.add_argument("--pr", type=int)
    p.add_argument("--merge", help="short merge SHA")
    p.add_argument("--waits", help="the issue this queued issue waits on")
    p.set_defaults(func=cmd_issue)

    p = sub.add_parser("need", help="add or close an open decision")
    p.add_argument("action", choices=("add", "close"))
    p.add_argument("n", nargs="?", type=int, help="need number (close)")
    p.add_argument("--kind", choices=NEED_KINDS)
    p.add_argument(
        "--awaits",
        choices=NEED_AWAITS,
        help="who must act: user (shows as NEEDS YOU) or external (BLOCKED); default external for Blocked, else user",
    )
    p.add_argument("--key")
    p.add_argument("--ask", help="the question and its resume condition")
    p.add_argument("--rec", help="the recommendation")
    p.add_argument("--option", action="append", default=[], help="a choice offered in chat, recommended first; repeat")
    p.set_defaults(func=cmd_need)

    p = sub.add_parser("report", help="record the Idle capacity and Next lines")
    p.add_argument("--idle", required=True)
    p.add_argument("--next", required=True)
    p.set_defaults(func=cmd_report)

    sub.add_parser("show", help="print run.json with fresh time fields").set_defaults(func=cmd_show)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        print(args.func(args, RUNS_DIR / args.run, datetime.now().astimezone()))
    except UsageError as exc:
        print(exc, file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

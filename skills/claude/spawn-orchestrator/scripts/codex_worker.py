#!/usr/bin/env python3
"""Drive one headless Codex worker for the spawn-orchestrator skill.

One run directory per issue holds everything the orchestrator needs:

  brief.md      the worker's brief (stdin for the first turn)
  events.jsonl  the `codex exec --json` stream, appended across turns
  stderr.log    Codex stderr, appended across turns
  last.md       the final agent message of the most recent turn
  thread_id     the Codex thread id from the first `thread.started` event
  pid           the live codex process id while a turn is running
  exit_code     the exit code of the most recent turn

Subcommands:
  start    launch the first turn and wait for it to exit
  resume   send a follow-up prompt to the same thread and wait
  status   summarize the run from events.jsonl
  denials  list auto-review denials with the reviewer's reason
  stop     interrupt the live turn (SIGINT, then SIGTERM)
  archive  archive the Codex thread

`start` and `resume` block until the codex process exits, so run them
through a background shell and treat their exit as the completion signal.
Exit codes: 0 turn completed, 1 turn failed or process error, 2 usage,
3 Codex opened a different thread than the one recorded (resume only).
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

DEFAULT_MODEL = "gpt-6-sol"
DEFAULT_EFFORT = "xhigh"
THREAD_MISMATCH_EXIT = 3
WORKER_STATUSES = ("pr-opened", "merged", "blocked", "failed")

FILESYSTEM_MARKERS = ("operation not permitted", "read-only file system", "permission denied")
NETWORK_MARKERS = (
    "could not resolve host",
    "network is unreachable",
    "connection refused",
    "temporary failure in name resolution",
    "network access",
)


# ---------------------------------------------------------------------------
# Event parsing (pure functions; covered by unit tests)
# ---------------------------------------------------------------------------


def read_events(path: Path) -> list[dict]:
    events: list[dict] = []
    if not path.exists():
        return events
    with path.open(encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(event, dict):
                events.append(event)
    return events


def split_turns(events: Iterable[dict]) -> list[list[dict]]:
    """Group events by turn. A `thread.started` preamble joins the turn that follows it."""
    turns: list[list[dict]] = []
    current: list[dict] = []
    for event in events:
        if event.get("type") == "turn.started" and has_turn_start(current):
            turns.append(current)
            current = []
        current.append(event)
    if current:
        turns.append(current)
    return turns


def has_turn_start(events: Iterable[dict]) -> bool:
    return any(event.get("type") == "turn.started" for event in events)


def thread_id_from(events: Iterable[dict]) -> str | None:
    for event in events:
        if event.get("type") == "thread.started":
            return event.get("thread_id")
    return None


def thread_matches(event: dict, expected: str | None) -> bool:
    """True unless a `thread.started` event names a different thread than expected."""
    if event.get("type") != "thread.started" or expected is None:
        return True
    return event.get("thread_id") == expected


def last_agent_message(turn: Iterable[dict]) -> str | None:
    text = None
    for event in turn:
        item = event.get("item") or {}
        if event.get("type") == "item.completed" and item.get("type") == "agent_message":
            text = item.get("text")
    return text


def command_items(turn: Iterable[dict]) -> list[dict]:
    items = []
    for event in turn:
        item = event.get("item") or {}
        if event.get("type") == "item.completed" and item.get("type") == "command_execution":
            items.append(item)
    return items


def strip_shell_wrapper(command: str) -> str:
    match = re.match(r"^/bin/\w+ -lc (['\"])(.*)\1$", command, re.DOTALL)
    return match.group(2) if match else command


def classify_boundary(output: str) -> tuple[str, str]:
    lowered = output.lower()
    for marker in FILESYSTEM_MARKERS:
        if marker in lowered:
            path_match = re.search(r"(?:not permitted|read-only file system|permission denied)[:\s]+(\S+)", lowered)
            detail = f"write outside the worktree: {path_match.group(1)}" if path_match else "write outside the worktree"
            return "filesystem", detail
    for marker in NETWORK_MARKERS:
        if marker in lowered:
            return "network", "outbound network access is disabled in the sandbox"
    return "unknown", output.strip().splitlines()[0] if output.strip() else "no sandbox error captured"


def worker_status_from(text: str | None) -> str | None:
    if not text:
        return None
    for status in WORKER_STATUSES:
        if re.search(rf"\b{re.escape(status)}\b", text):
            return status
    return None


@dataclass
class Status:
    thread_id: str | None
    state: str
    worker_status: str | None
    turns: int
    last_command: str | None
    denials: int
    exit_code: int | None
    pid: int | None

    def as_dict(self) -> dict:
        return self.__dict__.copy()


def compute_status(events: list[dict], exit_code: int | None, pid_alive: bool, pid: int | None) -> Status:
    turns = split_turns(events)
    last_turn = turns[-1] if turns else []
    types = [event.get("type") for event in last_turn]
    commands = command_items(last_turn)
    denials = sum(1 for item in commands if item.get("status") == "declined")

    if pid_alive:
        state = "running"
    elif "turn.failed" in types or "error" in types:
        state = "failed"
    elif "turn.completed" in types:
        state = "failed" if exit_code not in (None, 0) else "completed"
    elif has_turn_start(last_turn):
        state = "stopped"
    else:
        state = "not-started"

    last_command = strip_shell_wrapper(commands[-1]["command"]) if commands else None
    return Status(
        thread_id=thread_id_from(events),
        state=state,
        worker_status=worker_status_from(last_agent_message(last_turn)),
        turns=len(turns),
        last_command=last_command,
        denials=denials,
        exit_code=exit_code,
        pid=pid if pid_alive else None,
    )


@dataclass
class Denial:
    command: str
    boundary: str
    boundary_detail: str
    worker_reason: str | None
    reviewer_reason: str | None
    worker_after: str
    extra: dict = field(default_factory=dict)

    def as_dict(self) -> dict:
        data = self.__dict__.copy()
        data.pop("extra")
        return data


def rollout_rejections(rollout_lines: Iterable[str]) -> list[dict]:
    """Pair each rejected escalation with the justification the worker gave."""
    justifications: dict[str, str] = {}
    rejections: list[dict] = []
    for raw in rollout_lines:
        try:
            record = json.loads(raw)
        except json.JSONDecodeError:
            continue
        payload = record.get("payload") or {}
        kind = payload.get("type")
        if kind == "custom_tool_call":
            text = payload.get("input") or ""
            if "require_escalated" not in text:
                continue
            match = re.search(r"justification:\s*(?:\"((?:[^\"\\]|\\.)*)\"|'((?:[^'\\]|\\.)*)')", text)
            if match:
                justification = match.group(1) if match.group(1) is not None else match.group(2)
                justifications[payload.get("call_id", "")] = justification.replace('\\"', '"')
        elif kind == "custom_tool_call_output":
            texts = [part.get("text", "") for part in payload.get("output") or [] if isinstance(part, dict)]
            joined = "\n".join(texts)
            if "Rejected(" not in joined:
                continue
            # The reviewer text is a Debug-formatted Rust string inside JSON, so a newline
            # arrives as one or more literal backslashes followed by `n`.
            reason = re.search(r"Reason:\s*(.+?)(?:\\+n|\n|\\+\"|\"\)|$)", joined)
            rejections.append(
                {
                    "call_id": payload.get("call_id", ""),
                    "reason": (reason.group(1) if reason else joined).strip().rstrip("\\").strip(),
                }
            )
    for rejection in rejections:
        rejection["justification"] = justifications.get(rejection["call_id"])
    return rejections


def find_denials(events: list[dict], rollout_lines: Iterable[str]) -> list[Denial]:
    rejections = rollout_rejections(rollout_lines)
    denials: list[Denial] = []
    turns = split_turns(events)
    for turn in turns:
        commands = command_items(turn)
        final_message = last_agent_message(turn) or ""
        for index, item in enumerate(commands):
            if item.get("status") != "declined":
                continue
            command = strip_shell_wrapper(item.get("command", ""))
            boundary, detail = "unknown", "no sandbox error captured"
            for earlier in reversed(commands[:index]):
                if strip_shell_wrapper(earlier.get("command", "")) == command and earlier.get("status") == "failed":
                    boundary, detail = classify_boundary(earlier.get("aggregated_output") or "")
                    break
            rejection = rejections[len(denials)] if len(denials) < len(rejections) else {}
            worker_after = worker_status_from(final_message) or ("continued" if "turn.completed" in [e.get("type") for e in turn] else "still running")
            denials.append(
                Denial(
                    command=command,
                    boundary=boundary,
                    boundary_detail=detail,
                    worker_reason=rejection.get("justification"),
                    reviewer_reason=rejection.get("reason"),
                    worker_after=worker_after,
                )
            )
    return denials


def render_denials(denials: list[Denial], thread_id: str | None, run_dir: Path) -> str:
    if not denials:
        return "No auto-review denials recorded."
    blocks = []
    for denial in denials:
        rows = [
            ("Blocked action", f"`{denial.command}`"),
            ("Boundary", f"{denial.boundary.capitalize()}. {denial.boundary_detail[:1].upper()}{denial.boundary_detail[1:]}"),
            ("Worker's reason", f'"{denial.worker_reason}"' if denial.worker_reason else "not recorded"),
            ("Reviewer's reason", f'"{denial.reviewer_reason}"' if denial.reviewer_reason else "not recorded"),
            ("Worker now", denial.worker_after),
            ("Thread", f"`{thread_id or 'unknown'}` in `{run_dir}`"),
        ]
        table = "| | |\n|---|---|\n" + "\n".join(f"| **{key}** | {value} |" for key, value in rows)
        blocks.append(table)
    return "\n\n".join(blocks)


# ---------------------------------------------------------------------------
# Filesystem and process plumbing
# ---------------------------------------------------------------------------


def run_paths(run_dir: Path) -> dict[str, Path]:
    return {
        "brief": run_dir / "brief.md",
        "events": run_dir / "events.jsonl",
        "stderr": run_dir / "stderr.log",
        "last": run_dir / "last.md",
        "thread": run_dir / "thread_id",
        "pid": run_dir / "pid",
        "exit": run_dir / "exit_code",
        "worktree": run_dir / "worktree",
    }


def read_text(path: Path) -> str | None:
    return path.read_text(encoding="utf-8").strip() if path.exists() else None


def read_int(path: Path) -> int | None:
    text = read_text(path)
    return int(text) if text and text.lstrip("-").isdigit() else None


def pid_alive(pid: int | None) -> bool:
    if not pid:
        return False
    try:
        os.kill(pid, 0)
    except OSError:
        return False
    return True


def codex_home() -> Path:
    return Path(os.environ.get("CODEX_HOME") or Path.home() / ".codex")


def rollout_file(thread_id: str | None) -> Path | None:
    if not thread_id:
        return None
    matches: list[Path] = []
    for store in ("sessions", "archived_sessions"):
        root = codex_home() / store
        if root.exists():
            matches.extend(root.rglob(f"rollout-*{thread_id}*.jsonl"))
    return sorted(matches)[-1] if matches else None


def approval_overrides(network: bool) -> list[str]:
    """The `--approve-for-me` triple as -c overrides, valid for both exec and exec resume."""
    return [
        "-c", 'approvals_reviewer="auto_review"',
        "-c", 'approval_policy="on-request"',
        "-c", 'sandbox_mode="workspace-write"',
        "-c", f"sandbox_workspace_write.network_access={'true' if network else 'false'}",
    ]


def model_overrides(model: str, effort: str) -> list[str]:
    return ["-m", model, "-c", f"model_reasoning_effort={effort}"]


def run_turn(command: list[str], stdin_path: Path, worktree: Path, run_dir: Path, expected_thread: str | None) -> int:
    paths = run_paths(run_dir)
    with stdin_path.open("rb") as stdin, paths["events"].open("a", encoding="utf-8") as events, paths["stderr"].open(
        "a", encoding="utf-8"
    ) as stderr:
        process = subprocess.Popen(
            command,
            stdin=stdin,
            stdout=subprocess.PIPE,
            stderr=stderr,
            cwd=str(worktree),
            text=True,
            start_new_session=True,
        )
        paths["pid"].write_text(str(process.pid), encoding="utf-8")
        mismatch = False
        assert process.stdout is not None
        for line in process.stdout:
            events.write(line)
            events.flush()
            try:
                event = json.loads(line)
            except json.JSONDecodeError:
                continue
            if event.get("type") != "thread.started":
                continue
            if not thread_matches(event, expected_thread):
                mismatch = True
                events.write(json.dumps({"type": "error", "message": f"thread mismatch: expected {expected_thread}, got {event.get('thread_id')}"}) + "\n")
                events.flush()
                os.killpg(process.pid, signal.SIGTERM)
                break
            if expected_thread is None:
                paths["thread"].write_text(event.get("thread_id", ""), encoding="utf-8")
        exit_code = process.wait()
    paths["pid"].unlink(missing_ok=True)
    paths["exit"].write_text(str(exit_code), encoding="utf-8")

    all_events = read_events(paths["events"])
    turns = split_turns(all_events)
    final = last_agent_message(turns[-1]) if turns else None
    paths["last"].write_text((final or "") + "\n", encoding="utf-8")

    if mismatch:
        return THREAD_MISMATCH_EXIT
    status = compute_status(all_events, exit_code, False, None)
    print(format_status(status, run_dir))
    return 0 if status.state == "completed" else 1


def format_status(status: Status, run_dir: Path) -> str:
    lines = [
        f"thread: {status.thread_id or 'unknown'}",
        f"state: {status.state}" + (f" ({status.worker_status})" if status.worker_status else ""),
        f"turns: {status.turns}",
        f"denials: {status.denials}",
    ]
    if status.last_command:
        lines.append(f"last command: {status.last_command}")
    if status.exit_code is not None:
        lines.append(f"exit code: {status.exit_code}")
    lines.append(f"run dir: {run_dir}")
    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_start(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).expanduser().resolve()
    worktree = Path(args.worktree).expanduser().resolve()
    if not worktree.is_dir():
        print(f"worktree does not exist: {worktree}", file=sys.stderr)
        return 2
    run_dir.mkdir(parents=True, exist_ok=True)
    paths = run_paths(run_dir)
    if paths["thread"].exists():
        print(f"run dir already has a thread ({read_text(paths['thread'])}); use resume", file=sys.stderr)
        return 2
    shutil.copyfile(Path(args.brief).expanduser(), paths["brief"])
    paths["worktree"].write_text(str(worktree), encoding="utf-8")
    command = [
        "codex", "exec", "--json",
        "-C", str(worktree),
        *model_overrides(args.model, args.effort),
        *approval_overrides(not args.no_network),
        "--thread-source", "subagent",
        "-",
    ]
    return run_turn(command, paths["brief"], worktree, run_dir, expected_thread=None)


def cmd_resume(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).expanduser().resolve()
    paths = run_paths(run_dir)
    thread_id = read_text(paths["thread"])
    worktree_text = read_text(paths["worktree"])
    if not thread_id or not worktree_text:
        print("run dir has no thread_id or worktree; start first", file=sys.stderr)
        return 2
    if pid_alive(read_int(paths["pid"])):
        print("a turn is still running; stop it before resuming", file=sys.stderr)
        return 2
    prompt = Path(args.prompt).expanduser()
    turn_number = len(split_turns(read_events(paths["events"]))) + 1
    saved_prompt = run_dir / f"prompt-{turn_number}.md"
    shutil.copyfile(prompt, saved_prompt)
    command = [
        "codex", "exec", "resume", thread_id, "--json",
        *model_overrides(args.model, args.effort),
        *approval_overrides(not args.no_network),
        "-",
    ]
    return run_turn(command, saved_prompt, Path(worktree_text), run_dir, expected_thread=thread_id)


def cmd_status(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).expanduser().resolve()
    paths = run_paths(run_dir)
    pid = read_int(paths["pid"])
    status = compute_status(read_events(paths["events"]), read_int(paths["exit"]), pid_alive(pid), pid)
    if args.json:
        print(json.dumps(status.as_dict(), indent=2))
    else:
        print(format_status(status, run_dir))
    return 0


def cmd_denials(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).expanduser().resolve()
    paths = run_paths(run_dir)
    events = read_events(paths["events"])
    thread_id = read_text(paths["thread"]) or thread_id_from(events)
    rollout = rollout_file(thread_id)
    rollout_lines = rollout.read_text(encoding="utf-8").splitlines() if rollout else []
    denials = find_denials(events, rollout_lines)
    if args.json:
        print(json.dumps([denial.as_dict() for denial in denials], indent=2))
    else:
        print(render_denials(denials, thread_id, run_dir))
    return 0


def cmd_stop(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).expanduser().resolve()
    paths = run_paths(run_dir)
    pid = read_int(paths["pid"])
    if not pid_alive(pid):
        print("no live turn")
        return 0
    assert pid is not None
    os.killpg(pid, signal.SIGINT)
    deadline = time.monotonic() + args.grace
    while time.monotonic() < deadline and pid_alive(pid):
        time.sleep(0.2)
    if pid_alive(pid):
        os.killpg(pid, signal.SIGTERM)
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline and pid_alive(pid):
            time.sleep(0.2)
    print("stopped" if not pid_alive(pid) else f"still alive: pid {pid}")
    return 0 if not pid_alive(pid) else 1


def cmd_archive(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).expanduser().resolve()
    thread_id = read_text(run_paths(run_dir)["thread"])
    if not thread_id:
        print("run dir has no thread_id", file=sys.stderr)
        return 2
    return subprocess.run(["codex", "archive", thread_id], check=False).returncode


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    def add_common(p: argparse.ArgumentParser) -> None:
        p.add_argument("--run-dir", required=True)

    def add_model(p: argparse.ArgumentParser) -> None:
        p.add_argument("--model", default=DEFAULT_MODEL)
        p.add_argument("--effort", default=DEFAULT_EFFORT)
        p.add_argument("--no-network", action="store_true", help="disable outbound network in the sandbox")

    start = sub.add_parser("start", help="launch the first turn and wait")
    add_common(start)
    add_model(start)
    start.add_argument("--worktree", required=True)
    start.add_argument("--brief", required=True)
    start.set_defaults(func=cmd_start)

    resume = sub.add_parser("resume", help="send a follow-up prompt and wait")
    add_common(resume)
    add_model(resume)
    resume.add_argument("--prompt", required=True)
    resume.set_defaults(func=cmd_resume)

    status = sub.add_parser("status", help="summarize the run")
    add_common(status)
    status.add_argument("--json", action="store_true")
    status.set_defaults(func=cmd_status)

    denials = sub.add_parser("denials", help="list auto-review denials")
    add_common(denials)
    denials.add_argument("--json", action="store_true")
    denials.set_defaults(func=cmd_denials)

    stop = sub.add_parser("stop", help="interrupt the live turn")
    add_common(stop)
    stop.add_argument("--grace", type=float, default=10.0)
    stop.set_defaults(func=cmd_stop)

    archive = sub.add_parser("archive", help="archive the Codex thread")
    add_common(archive)
    archive.set_defaults(func=cmd_archive)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())

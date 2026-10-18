#!/usr/bin/env python3
"""Record each Claude Code session's state for $root-orchestrator.

Claude Code runs this as a command hook on session, prompt, tool, permission,
and stop events, with the event as JSON on stdin. It keeps one small file per
main session, ~/.cache/claude-sessions/<session_id>.json:

  name            the user-set session name (session_title), when set
  status          busy | idle | ended, and statusAt
  waiting         the question or permission prompt the user must answer, or null
  backgroundTasks how many background tasks were running when the last turn ended
  orchestrator    true once the session runs $spawn-orchestrator or dispatches a worker
  codex           issue -> Codex run directory, from codex_worker.py start/resume
  opus            agent id -> {key, state}, for Opus workers launched with the Agent tool
  triage          for an orchestrator parked with nothing running: Haiku's verdict on
                  its last message, {verdict: pending | you | done | failed, summary, since}

It prints nothing, so it adds nothing to any model context, and it always
exits 0 so a failure here never disturbs the session.

Triage runs only when an orchestrator's turn ends with no background task or
scheduled job left, because only then does the session wait for the user. A
detached child (`session_state.py --triage`) asks Haiku about the last message
with no tools, settings, or hooks, so the turn never waits on it.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

STATE_DIR = Path.home() / ".cache" / "claude-sessions"

DISPATCH = re.compile(r"codex_worker\.py\s+(?:start|resume)\b")
RUN_DIR_ARG = re.compile(r"--run-dir[=\s]+([\"']?)(\S+?)\1(?=\s|;|&|$)")
ASSIGNMENT = re.compile(r"(?:^|[\s;&(])([A-Za-z_]\w*)=([\"']?)([^\s;&\"']+)\2")
ISSUE_KEY = re.compile(r"\b[A-Z][A-Z0-9]+-\d+\b")
ORCHESTRATOR_PROMPT = re.compile(r"^\s*(?:/spawn-orchestrator\b|<command-name>/?spawn-orchestrator</command-name>)")
VERDICT = re.compile(r"^(YOU|DONE)\s*:\s*(.+)$")

TRIAGE_GUARD = "SESSION_STATE_TRIAGE"
TRIAGE_TIMEOUT = 90
MESSAGE_LIMIT = 4000
TRIAGE_PROMPT = (
    "You triage the final message of an AI coding orchestrator session that has stopped with nothing running "
    "in the background, so it waits for the user. Reply with exactly one line: \"YOU: <what the user must do, "
    "under 12 words>\" if the message asks the user for a decision, answer, approval, or action, or reports a "
    "failure or blocker only the user can clear; otherwise \"DONE: <what finished, under 12 words>\"."
)


def short(text: object, limit: int = 160) -> str:
    return " ".join(str(text or "").split())[:limit]


def dispatched_run_dir(command: str) -> Path | None:
    """The Codex run directory a codex_worker.py start/resume command names, with simple shell variables expanded."""
    if not DISPATCH.search(command):
        return None
    match = RUN_DIR_ARG.search(command)
    if match is None:
        return None
    variables = {name: value for name, _, value in ASSIGNMENT.findall(command)}
    raw = re.sub(r"\$\{?([A-Za-z_]\w*)\}?", lambda m: variables.get(m.group(1), m.group(0)), match.group(2))
    if "$" in raw:
        return None
    return Path(os.path.expanduser(raw))


def permission_text(event: dict) -> str:
    tool = event.get("tool_name") or "a tool"
    tool_input = event.get("tool_input") or {}
    detail = tool_input.get("command") or tool_input.get("file_path") or tool_input.get("url") or ""
    return short(f"allow {tool}: {detail}" if detail else f"allow {tool}")


def apply(state: dict, event: dict, now: float) -> dict:
    """Fold one hook event into the session's state."""
    state = {**state, "sessionId": event.get("session_id", state.get("sessionId")), "updatedAt": now}
    for field, source in (("cwd", "cwd"), ("transcriptPath", "transcript_path"), ("name", "session_title")):
        if event.get(source):
            state[field] = event[source]
    name = event.get("hook_event_name", "")
    main = not event.get("agent_id")
    waiting = state.get("waiting")

    def status(value: str) -> None:
        if state.get("status") != value:
            state["status"], state["statusAt"] = value, now

    if name == "SessionStart":
        if event.get("source") in ("startup", "resume"):
            status("idle")
            state["waiting"] = None
            state["triage"] = None
    elif name == "UserPromptSubmit":
        status("busy")
        state["waiting"] = None
        state["triage"] = None
        if ORCHESTRATOR_PROMPT.search(str(event.get("prompt", ""))):
            state["orchestrator"] = True
    elif name == "Stop":
        status("idle")
        state["waiting"] = None
        tasks = event.get("background_tasks")
        state["backgroundTasks"] = len(tasks) if isinstance(tasks, (list, dict)) else tasks
        if main and state.get("orchestrator") and parked(event) and event.get("last_assistant_message"):
            state["triage"] = {"verdict": "pending", "since": now}
        else:
            state["triage"] = None
    elif name == "SessionEnd":
        status("ended")
        state["waiting"] = None
        state["endReason"] = event.get("reason")
    elif name == "PreToolUse" and main:
        tool_input = event.get("tool_input") or {}
        if event.get("tool_name") == "AskUserQuestion":
            questions = tool_input.get("questions") or [{}]
            state["waiting"] = {"kind": "question", "text": short(questions[0].get("question")), "since": now,
                                "toolUseId": event.get("tool_use_id")}
        elif event.get("tool_name") == "Skill" and str(tool_input.get("skill", "")).endswith("spawn-orchestrator"):
            state["orchestrator"] = True
    elif name in ("PermissionRequest", "Notification"):
        if name == "PermissionRequest" or event.get("notification_type") == "permission_prompt":
            text = permission_text(event) if name == "PermissionRequest" else short(event.get("message"))
            if not main:
                text = f"worker {event.get('agent_type') or 'subagent'}: {text}"
            if not (waiting and waiting.get("kind") == "permission"):
                state["waiting"] = {"kind": "permission", "text": text, "since": now}
    elif name in ("PostToolUse", "PostToolUseFailure", "PermissionDenied"):
        if waiting and (waiting.get("kind") == "permission" or waiting.get("toolUseId") == event.get("tool_use_id")):
            state["waiting"] = None
        if main:
            # Turns started by a task notification fire no UserPromptSubmit; tool activity shows the session is working.
            status("busy")
            state["triage"] = None
        if name == "PostToolUse" and main:
            tool_input = event.get("tool_input") or {}
            if event.get("tool_name") == "Bash":
                run_dir = dispatched_run_dir(str(tool_input.get("command", "")))
                if run_dir is not None:
                    state["orchestrator"] = True
                    state["codex"] = {**state.get("codex", {}), run_dir.name: str(run_dir)}
            elif event.get("tool_name") == "Agent" and state.get("orchestrator"):
                response = event.get("tool_response") or {}
                agent_id = response.get("agentId") if isinstance(response, dict) else None
                key = ISSUE_KEY.search(f"{tool_input.get('description', '')} {tool_input.get('prompt', '')[:400]}")
                if agent_id and key:
                    done = isinstance(response, dict) and response.get("status") == "completed"
                    state["opus"] = {**state.get("opus", {}), agent_id: {"key": key.group(0), "state": "done" if done else "running"}}
    elif name == "SubagentStop":
        agent_id = event.get("agent_id")
        if agent_id in state.get("opus", {}):
            state["opus"] = {**state["opus"], agent_id: {**state["opus"][agent_id], "state": "done"}}
    return state


def parked(event: dict) -> bool:
    """A turn that ended with no background task or scheduled job left waits for the user."""
    return not event.get("background_tasks") and not event.get("session_crons")


def parse_verdict(reply: str) -> dict:
    line = next((part.strip() for part in reply.splitlines() if part.strip()), "")
    match = VERDICT.match(line)
    if match is None:
        return {"verdict": "failed", "summary": short(line or "no reply", 120)}
    return {"verdict": match.group(1).lower(), "summary": short(match.group(2), 120)}


def update(session_id: str, change) -> dict:
    """Apply `change` to the session's state under its lock and replace the file atomically."""
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / f"{session_id}.json"
    with open(STATE_DIR / f".{session_id}.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            state = json.loads(path.read_text())
        except (OSError, ValueError):
            state = {}
        state = change(state)
        fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=f".{session_id}.")
        with os.fdopen(fd, "w") as out:
            json.dump(state, out)
        os.replace(tmp, path)
    return state


def start_triage(session_id: str, message: str, since: float) -> None:
    """Hand the last message to a detached child so the turn never waits on Haiku."""
    inbox = STATE_DIR / f".{session_id}.message"
    inbox.write_text(message[-MESSAGE_LIMIT:])
    env = {k: v for k, v in os.environ.items() if not k.startswith(("CLAUDE_CODE_", "CLAUDECODE"))}
    env[TRIAGE_GUARD] = "1"
    subprocess.Popen([sys.executable, os.path.abspath(__file__), "--triage", session_id, repr(since)],
                     stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                     start_new_session=True, env=env)


def triage(session_id: str, since: float) -> None:
    """Ask Haiku whether the parked session needs the user, and record the verdict unless the user moved on."""
    inbox = STATE_DIR / f".{session_id}.message"
    message = inbox.read_text()
    inbox.unlink(missing_ok=True)
    command = [shutil.which("claude") or "claude", "-p", "--model", "haiku", "--setting-sources", "",
               "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence", "--tools", "",
               "--system-prompt", TRIAGE_PROMPT]
    try:
        reply = subprocess.run(command, input=message, capture_output=True, text=True, timeout=TRIAGE_TIMEOUT, check=True).stdout
        verdict = parse_verdict(reply)
    except (OSError, subprocess.SubprocessError) as exc:
        verdict = {"verdict": "failed", "summary": short(exc, 120)}

    def change(state: dict) -> dict:
        current = state.get("triage") or {}
        if current.get("verdict") != "pending" or current.get("since") != since:
            return state  # a newer prompt or turn superseded this one
        return {**state, "triage": {**verdict, "since": since, "at": time.time()}}

    update(session_id, change)


def record(event: dict, now: float) -> None:
    session_id = str(event.get("session_id") or "")
    if not re.fullmatch(r"[A-Za-z0-9-]+", session_id):
        return
    state = update(session_id, lambda s: apply(s, event, now))
    pending = state.get("triage") or {}
    if pending.get("verdict") == "pending" and pending.get("since") == now:
        start_triage(session_id, str(event.get("last_assistant_message", "")), now)


def main(argv: list[str]) -> int:
    try:
        if argv[:1] == ["--triage"]:
            triage(argv[1], float(argv[2]))
        elif not os.environ.get(TRIAGE_GUARD):
            record(json.load(sys.stdin), time.time())
    except Exception as exc:  # a broken recorder must never break the session
        print(f"session-state: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

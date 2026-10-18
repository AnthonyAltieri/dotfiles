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

It prints nothing, so it adds nothing to any model context, and it always
exits 0 so a failure here never disturbs the session.
"""

from __future__ import annotations

import fcntl
import json
import os
import re
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
    elif name == "UserPromptSubmit":
        status("busy")
        state["waiting"] = None
        if ORCHESTRATOR_PROMPT.search(str(event.get("prompt", ""))):
            state["orchestrator"] = True
    elif name == "Stop":
        status("idle")
        state["waiting"] = None
        tasks = event.get("background_tasks")
        state["backgroundTasks"] = len(tasks) if isinstance(tasks, (list, dict)) else tasks
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


def record(event: dict, now: float) -> None:
    session_id = str(event.get("session_id") or "")
    if not re.fullmatch(r"[A-Za-z0-9-]+", session_id):
        return
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    path = STATE_DIR / f"{session_id}.json"
    with open(STATE_DIR / f".{session_id}.lock", "w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            state = json.loads(path.read_text())
        except (OSError, ValueError):
            state = {}
        fd, tmp = tempfile.mkstemp(dir=STATE_DIR, prefix=f".{session_id}.")
        with os.fdopen(fd, "w") as out:
            json.dump(apply(state, event, now), out)
        os.replace(tmp, path)


def main() -> int:
    try:
        record(json.load(sys.stdin), time.time())
    except Exception as exc:  # a broken recorder must never break the session
        print(f"session-state: {exc}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""Unit tests for the session-state hook's event reducer."""

import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import session_state
from session_state import apply, parse_verdict

T = 1_800_000_000.0


def ev(name, **fields):
    return {"hook_event_name": name, "session_id": "s1", **fields}


def fold(*events):
    state = {}
    for i, event in enumerate(events):
        state = apply(state, event, T + i)
    return state


class WaitingTests(unittest.TestCase):
    def test_question_waits_until_its_own_tool_call_completes(self):
        ask = ev("PreToolUse", tool_name="AskUserQuestion", tool_use_id="q1", tool_input={"questions": [{"question": "Merge now?"}]})
        other = ev("PostToolUse", tool_name="Bash", tool_use_id="b1", tool_input={"command": "ls"})
        answered = ev("PostToolUse", tool_name="AskUserQuestion", tool_use_id="q1")
        self.assertEqual(fold(ask, other)["waiting"]["text"], "Merge now?")
        self.assertIsNone(fold(ask, other, answered)["waiting"])

    def test_permission_prompt_for_a_question_keeps_the_question_text(self):
        # Regression: the AskUserQuestion permission prompt replaced the question with "allow AskUserQuestion".
        ask = ev("PreToolUse", tool_name="AskUserQuestion", tool_use_id="q1", tool_input={"questions": [{"question": "Merge now?"}]})
        prompt = ev("PermissionRequest", tool_name="AskUserQuestion", tool_input={})
        self.assertEqual(fold(ask, prompt)["waiting"]["text"], "Merge now?")

    def test_worker_permission_prompt_waits_until_the_tool_resolves(self):
        prompt = ev("PermissionRequest", agent_id="a1", agent_type="general-purpose", tool_name="Bash", tool_input={"command": "rm -rf build"})
        state = fold(prompt)
        self.assertEqual(state["waiting"]["text"], "worker general-purpose: allow Bash: rm -rf build")
        self.assertIsNone(fold(prompt, ev("PermissionDenied", agent_id="a1", tool_name="Bash"))["waiting"])


class WorkerTests(unittest.TestCase):
    def test_dispatch_through_a_shell_variable_records_the_run_dir(self):
        cmd = "B=~/.cache/spawn-orchestrator/portfolio-v1; cd ~ && setsid -w python3 codex_worker.py start --run-dir $B/QUANT-519 --brief x"
        state = fold(ev("PostToolUse", tool_name="Bash", tool_input={"command": cmd}))
        self.assertTrue(state["orchestrator"])
        self.assertTrue(state["codex"]["QUANT-519"].endswith(".cache/spawn-orchestrator/portfolio-v1/QUANT-519"))

    def test_opus_worker_runs_until_its_subagent_stops(self):
        launch = ev("PostToolUse", tool_name="Agent", tool_input={"description": "QUANT-7 worker"}, tool_response={"agentId": "a9", "status": "async_launched"})
        start = ev("UserPromptSubmit", prompt="/spawn-orchestrator QUANT-1")
        self.assertEqual(fold(start, launch)["opus"]["a9"], {"key": "QUANT-7", "state": "running", "startedAt": T + 1})
        stopped = fold(start, launch, ev("SubagentStop", agent_id="a9"))["opus"]["a9"]
        self.assertEqual((stopped["state"], stopped["startedAt"], stopped["endedAt"]), ("done", T + 1, T + 2))


class StatusTests(unittest.TestCase):
    def test_turn_end_records_idle_and_background_task_count(self):
        state = fold(ev("UserPromptSubmit", prompt="hi"), ev("Stop", background_tasks=[{"id": "t1"}, {"id": "t2"}]))
        self.assertEqual((state["status"], state["statusAt"], state["backgroundTasks"]), ("idle", T + 1, 2))


class TriageTests(unittest.TestCase):
    ORCH = ev("UserPromptSubmit", prompt="/spawn-orchestrator QUANT-1")

    def test_every_orchestrator_turn_end_is_triaged_even_with_background_tasks(self):
        # Regression: orchestrators keep a Monitor running, so gating on no background task never triaged them.
        monitoring = ev("Stop", last_assistant_message="Merge #12 now?", background_tasks=[{"id": "t1"}])
        self.assertEqual(fold(self.ORCH, monitoring)["triage"], {"verdict": "pending", "since": T + 1})
        self.assertIsNone(fold(ev("UserPromptSubmit", prompt="hi"), monitoring)["triage"])

    def test_orchestrator_footer_decides_the_verdict_without_haiku(self):
        you = "Status above.\n━━━━\n▶ YOU (2)\n  1. Answer: PR (1) or pasted files (2)? I recommend 1.\n  2. Run: the sudo above.\n━━━━"
        clear = "Status.\n━━━━\n✓ Nothing needs you. Next: book 1 decision at 04:00Z\n━━━━"
        finished = "All merged.\n━━━━\n✓ Nothing needs you. Run complete.\n━━━━"
        verdict = lambda m: {k: v for k, v in fold(self.ORCH, ev("Stop", last_assistant_message=m))["triage"].items() if k != "since"}
        self.assertEqual(verdict(you), {"verdict": "you", "summary": "Answer: PR (1) or pasted files (2)? I recommend 1."})
        self.assertEqual(verdict(clear), {"verdict": "wait", "summary": "Next: book 1 decision at 04:00Z"})
        self.assertEqual(verdict(finished)["verdict"], "done")
        self.assertEqual(verdict("Should I merge?"), {"verdict": "pending"})

    def test_tool_activity_after_a_parked_turn_clears_the_verdict(self):
        parked = ev("Stop", last_assistant_message="Dispatch now?", background_tasks=[])
        woke = ev("PostToolUse", tool_name="Bash", tool_use_id="b1", tool_input={"command": "gh pr view 1"})
        state = fold(self.ORCH, parked, woke)
        self.assertEqual((state["status"], state["triage"]), ("busy", None))

    def test_verdict_line_is_parsed_and_anything_else_fails_open(self):
        self.assertEqual(parse_verdict("YOU: Approve merging #2212\n"), {"verdict": "you", "summary": "Approve merging #2212"})
        self.assertEqual(parse_verdict("WAIT: research data at 05:00Z")["verdict"], "wait")
        self.assertEqual(parse_verdict("I think the user should look")["verdict"], "failed")

    def test_session_named_in_a_run_file_is_triaged_without_a_dispatch(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "runs" / "portfolio-ui").mkdir(parents=True)
            (root / "runs" / "portfolio-ui" / "run.json").write_text('{"sessionName": "trading-ui"}')
            stop = ev("Stop", session_title="trading-ui", last_assistant_message="Merge #12?", background_tasks=[])
            with mock.patch.object(session_state, "STATE_DIR", root / "state"), mock.patch.object(session_state, "RUNS_DIR", root / "runs"), \
                    mock.patch.object(session_state, "start_triage") as start:
                session_state.record(stop, T)
            self.assertEqual(start.call_args.args[:2], ("s1", "Merge #12?"))

    def test_verdict_is_dropped_when_the_user_typed_before_haiku_answered(self):
        with tempfile.TemporaryDirectory() as tmp, mock.patch.object(session_state, "STATE_DIR", Path(tmp)):
            stop = ev("Stop", last_assistant_message="Dispatch now?", background_tasks=[])
            session_state.update("s1", lambda s: fold(self.ORCH, stop))
            (Path(tmp) / ".s1.message").write_text("Dispatch now?")
            session_state.update("s1", lambda s: apply(s, ev("UserPromptSubmit", prompt="yes"), T + 5))
            reply = subprocess.CompletedProcess([], 0, stdout="YOU: Decide on dispatch\n")
            with mock.patch.object(session_state.subprocess, "run", return_value=reply):
                session_state.triage("s1", T + 1)
            self.assertIsNone(session_state.update("s1", lambda s: s)["triage"])


if __name__ == "__main__":
    unittest.main()

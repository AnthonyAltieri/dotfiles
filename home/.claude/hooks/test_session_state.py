"""Unit tests for the session-state hook's event reducer."""

import unittest

from session_state import apply

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
        self.assertEqual(fold(start, launch)["opus"]["a9"], {"key": "QUANT-7", "state": "running"})
        self.assertEqual(fold(start, launch, ev("SubagentStop", agent_id="a9"))["opus"]["a9"]["state"], "done")


class StatusTests(unittest.TestCase):
    def test_turn_end_records_idle_and_background_task_count(self):
        state = fold(ev("UserPromptSubmit", prompt="hi"), ev("Stop", background_tasks=[{"id": "t1"}, {"id": "t2"}]))
        self.assertEqual((state["status"], state["statusAt"], state["backgroundTasks"]), ("idle", T + 1, 2))


if __name__ == "__main__":
    unittest.main()

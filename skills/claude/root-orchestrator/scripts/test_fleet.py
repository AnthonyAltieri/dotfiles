"""Unit tests for fleet.py health classification and change detection."""

import json
import os
import tempfile
import unittest
from pathlib import Path

import fleet

NOW = 1_800_000_000.0
MIN = 60


def session(**overrides):
    base = dict(name="trading-ui", session_id="s1", cwd="/repo", alive=True, busy=False, status_at=NOW,
                named_by_user=True, transcript_mtime=NOW, subagent_mtime=None)
    return fleet.Session(**{**base, **overrides})


def hooked(**overrides):
    base = dict(session_id="s1", name="trading-ui", cwd="/repo", status="idle", status_at=NOW, waiting=None,
                orchestrator=True, codex_dirs=(), opus_running=0, opus_done=0, updated_at=NOW)
    return fleet.Hooked(**{**base, **overrides})


def view(s=None, h=None, run=None, running=0):
    return fleet.View("trading-ui", s or session(), h, run, fleet.Workers(running, 0))


class ClassifyTests(unittest.TestCase):
    def test_question_waiting_on_the_user_alerts_after_ten_minutes(self):
        fresh = hooked(waiting=fleet.Waiting("question", "Merge now?", NOW - 5 * MIN))
        old = hooked(waiting=fleet.Waiting("question", "Merge now?", NOW - 15 * MIN))
        self.assertEqual(fleet.classify(view(h=fresh), NOW), fleet.Health("needs-you", "question: Merge now? · 5m"))
        self.assertTrue(fleet.classify(view(h=old), NOW).alert)

    def test_idle_session_waiting_on_live_workers_is_not_stalled(self):
        idle = hooked(status_at=NOW - 60 * MIN)
        self.assertEqual(fleet.classify(view(h=idle, running=2), NOW).state, "ok")
        self.assertEqual(fleet.classify(view(h=idle), NOW).state, "stalled")

    def test_busy_session_with_silent_transcript_and_no_workers_is_hung(self):
        s = session(transcript_mtime=NOW - 25 * MIN)
        self.assertEqual(fleet.classify(view(s=s, h=hooked(status="busy")), NOW).state, "hung")

    def test_hook_without_a_status_yet_falls_back_to_the_registry(self):
        s = session(busy=True, transcript_mtime=NOW - 25 * MIN)
        self.assertEqual(fleet.classify(view(s=s, h=hooked(status="", status_at=None)), NOW).state, "hung")

    def test_ended_session_is_dead_but_settled_run_is_done(self):
        run = fleet.Run("r", "trading-ui", "/repo", True, NOW, {"merged": 3})
        self.assertEqual(fleet.classify(view(h=hooked(status="ended")), NOW).state, "dead")
        self.assertEqual(fleet.classify(view(s=session(alive=False), run=run), NOW).state, "settled")


class PaneTests(unittest.TestCase):
    def test_herdr_ratio_leaves_the_new_pane_just_the_table_rows(self):
        self.assertAlmostEqual(fleet.herdr_split_ratio(fleet.pane_rows(5), 54), 1 - 12 / 54)
        self.assertEqual(fleet.herdr_split_ratio(fleet.pane_rows(40), 54), 0.5)


class TransitionTests(unittest.TestCase):
    def test_reports_only_changed_states_and_new_alerts(self):
        before = {"a": fleet.Health("ok", "x"), "b": fleet.Health("needs-you", "y"), "c": fleet.Health("ok", "z")}
        after = {"a": fleet.Health("ok", "x2"), "b": fleet.Health("needs-you", "y", alert=True), "c": fleet.Health("stalled", "z")}
        lines = fleet.transitions(before, after)
        self.assertEqual([line.split(":")[0].lstrip("⚠ ") for line in lines], ["b", "c"])


class LoadTests(unittest.TestCase):
    def test_codex_workers_count_live_pids_and_finished_turns(self):
        with tempfile.TemporaryDirectory() as tmp:
            live, done = Path(tmp) / "Q-1", Path(tmp) / "Q-2"
            live.mkdir()
            done.mkdir()
            (live / "pid").write_text(str(os.getpid()))
            (done / "exit_code").write_text("0")
            self.assertEqual(fleet.codex_workers([live, done]), fleet.Workers(1, 1))

    def test_malformed_hook_state_is_skipped_and_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "good.json").write_text(json.dumps({"sessionId": "s1", "status": "busy"}))
            (root / "bad.json").write_text("{not json")
            original, fleet.STATE_DIR = fleet.STATE_DIR, root
            try:
                warnings = []
                states = fleet.load_hooked(warnings)
            finally:
                fleet.STATE_DIR = original
        self.assertEqual((list(states), len(warnings)), (["s1"], 1))


if __name__ == "__main__":
    unittest.main()

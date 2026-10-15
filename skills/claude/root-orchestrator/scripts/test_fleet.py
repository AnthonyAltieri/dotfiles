"""Unit tests for fleet.py health classification and change detection."""

import json
import tempfile
import unittest
from pathlib import Path

import fleet

NOW = 1_800_000_000.0
MIN = 60


def session(**overrides):
    base = dict(name="trading-ui", session_id="s1", cwd="/repo", alive=True, busy=False,
                named_by_user=True, transcript_mtime=NOW, subagent_mtime=None)
    return fleet.Session(**{**base, **overrides})


def run(**overrides):
    base = dict(run_id="mobile-web", session_name="trading-ui", repo_path="/repo", settled=False,
                updated_at=NOW, last_progress_at=NOW, counts={"running": 1}, needs=(), events_mtime=None)
    return fleet.Run(**{**base, **overrides})


def view(run_=None, session_=None):
    return fleet.View("trading-ui", run_, session_)


class ClassifyTests(unittest.TestCase):
    def test_open_decision_alerts_only_after_thirty_minutes(self):
        fresh = run(needs=(fleet.Need(1, "AAL-1", "Blocked", NOW - 10 * MIN),))
        old = run(needs=(fleet.Need(1, "AAL-1", "Blocked", NOW - 40 * MIN),))
        self.assertFalse(fleet.classify(view(fresh, session()), NOW).alert)
        self.assertTrue(fleet.classify(view(old, session()), NOW).alert)

    def test_busy_session_with_silent_transcript_is_hung_even_with_open_decisions(self):
        r = run(needs=(fleet.Need(1, "AAL-1", "Blocked", NOW),))
        s = session(busy=True, transcript_mtime=NOW - 25 * MIN)
        self.assertEqual(fleet.classify(view(r, s), NOW).state, "hung")

    def test_opus_subagent_activity_counts_as_progress(self):
        r = run(updated_at=NOW - 60 * MIN, last_progress_at=NOW - 60 * MIN)
        self.assertEqual(fleet.classify(view(r, session(subagent_mtime=NOW - 60 * MIN)), NOW).state, "stalled")
        self.assertEqual(fleet.classify(view(r, session(subagent_mtime=NOW - 2 * MIN)), NOW).state, "ok")

    def test_settled_run_whose_session_closed_is_not_dead(self):
        r = run(settled=True, counts={"merged": 3})
        self.assertEqual(fleet.classify(view(r, None), NOW).state, "settled")


class TransitionTests(unittest.TestCase):
    def test_reports_only_changed_states_and_new_alerts(self):
        before = {"a": fleet.Health("ok", "x"), "b": fleet.Health("needs-you", "y"), "c": fleet.Health("ok", "z")}
        after = {"a": fleet.Health("ok", "x2"), "b": fleet.Health("needs-you", "y", alert=True), "c": fleet.Health("stalled", "z")}
        lines = fleet.transitions(before, after)
        self.assertEqual([line.split(":")[0].lstrip("⚠ ") for line in lines], ["b", "c"])


class LoadTests(unittest.TestCase):
    def test_malformed_run_file_is_skipped_and_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "good").mkdir()
            (root / "good" / "run.json").write_text(json.dumps({"run": "good", "sessionName": "trading-ui", "issues": [{"state": "running"}]}))
            (root / "bad").mkdir()
            (root / "bad" / "run.json").write_text("{not json")
            original, fleet.RUNS_DIR = fleet.RUNS_DIR, root
            try:
                warnings = []
                runs = fleet.load_runs(warnings)
            finally:
                fleet.RUNS_DIR = original
        self.assertEqual(list(runs), ["trading-ui"])
        self.assertEqual(len(warnings), 1)


if __name__ == "__main__":
    unittest.main()

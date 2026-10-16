"""Unit tests for run_state.py: derived fields and the worker's dispatch hook."""

import json
import tempfile
import unittest
from datetime import datetime, timedelta
from pathlib import Path

import run_state as rs

START = datetime(2026, 10, 15, 22, 0).astimezone()


def at(minutes):
    return START + timedelta(minutes=minutes)


def fresh():
    return rs.init({}, "run-1", {"mode": "automerge"}, "trading-ui", "abcdef1234", "/repo", START)


class IssueTests(unittest.TestCase):
    def test_lifecycle_times_count_past_midnight_and_merge_is_progress(self):
        data = rs.set_issue(fresh(), "Q-1", "running", at(30), model="codex")
        data = rs.set_issue(data, "Q-1", "merged", at(150), pr=7, merge="abc1234")
        out = rs.render(data, at(160))
        issue = out["issues"][0]
        self.assertEqual((issue["start"], issue["end"]), ("22:30", "24:30"))
        self.assertEqual((out["now"], out["elapsed"]), ("24:40", "2h 40m"))
        self.assertEqual(rs.parse(out["lastProgressAt"]), at(150))

    def test_adopted_hand_written_start_is_kept(self):
        legacy = {**fresh(), "issues": [{"key": "Q-1", "state": "blocked", "start": "09:12"}]}
        out = rs.render(rs.set_issue(legacy, "Q-1", "running", at(5)), at(5))
        self.assertEqual(out["issues"][0]["start"], "09:12")

    def test_settled_only_when_every_issue_is_terminal_or_parked(self):
        data = rs.set_issue(rs.set_issue(fresh(), "Q-1", "merged", at(1)), "Q-2", "parked", at(1))
        self.assertTrue(rs.render(data, at(2))["settled"])
        self.assertFalse(rs.render(rs.set_issue(data, "Q-3", "queued", at(3)), at(3))["settled"])


class NeedTests(unittest.TestCase):
    def test_numbers_stay_stable_and_closing_counts_as_progress(self):
        data, first = rs.add_need(fresh(), "Blocked", "Q-1", "ask", "rec", [], at(1))
        data, second = rs.add_need(data, "Stalled", "Q-2", "ask", "rec", [], at(2))
        data = rs.close_need(data, first, at(40))
        data, third = rs.add_need(data, "Parked", "Q-3", "ask", "rec", [], at(41))
        out = rs.render(data, at(42))
        self.assertEqual([n["n"] for n in out["needs"]], [second, third])
        self.assertEqual(out["needs"][0]["age"], "40m")
        self.assertEqual(rs.parse(out["lastProgressAt"]), at(40))


class DispatchHookTests(unittest.TestCase):
    def test_worker_dispatch_marks_issue_running_only_once_the_run_exists(self):
        with tempfile.TemporaryDirectory() as tmp:
            run_dir = Path(tmp) / "run-1"
            rs.mark_running(run_dir, "Q-1", "codex")
            self.assertFalse((run_dir / "run.json").exists())
            rs.update(run_dir, lambda d: rs.set_issue(fresh(), "Q-1", "queued", START, waits="Q-0"), START)
            rs.mark_running(run_dir, "Q-1", "codex")
            issue = json.loads((run_dir / "run.json").read_text())["issues"][0]
        self.assertEqual((issue["state"], issue["model"], "waits" in issue), ("running", "codex", False))


if __name__ == "__main__":
    unittest.main()

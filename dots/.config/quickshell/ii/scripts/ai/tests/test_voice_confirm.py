"""Risky spoken commands run only after a fresh, plain "yes", and only as `confirmed` actions."""
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import voice_agent as va  # noqa: E402


class Confirm(unittest.TestCase):
    def setUp(self):
        self.events = []
        patcher = mock.patch.object(va, "emit", self.events.append)
        patcher.start()
        self.addCleanup(patcher.stop)
        self.model = va.Model()

    def ask(self, text, context=""):
        self.events.clear()
        handled = self.model.ask_rules("t", text, context)
        return handled, list(self.events)

    def actions(self, events):
        return [(e["verb"], e.get("confirmed", False)) for e in events if e["event"] == "action"]

    def test_a_risky_command_only_asks(self):
        handled, events = self.ask("lock the screen")
        self.assertTrue(handled)
        self.assertEqual(self.actions(events), [])
        self.assertIn("yes", events[-1]["text"].lower())
        self.assertTrue(events[-1]["confirm"])

    def test_yes_runs_it_as_confirmed(self):
        self.ask("shut down the computer")
        handled, events = self.ask("Yes, please!")
        self.assertTrue(handled)
        self.assertEqual(self.actions(events), [("shutdown", True)])
        self.assertEqual(events[-1]["text"], "Shutting down.")

    def test_no_cancels_and_a_later_yes_does_nothing(self):
        self.ask("restart the computer")
        handled, events = self.ask("no")
        self.assertTrue(handled)
        self.assertEqual(self.actions(events), [])
        handled, events = self.ask("yes")
        self.assertFalse(handled)            # nothing pending any more: it is just "yes" for the model

    def test_anything_else_drops_the_question(self):
        self.ask("close this window")
        handled, events = self.ask("volume 30")
        self.assertEqual(self.actions(events), [("volume", False)])
        handled, events = self.ask("yes")
        self.assertFalse(handled)

    def test_it_expires(self):
        self.ask("go to sleep")
        self.model.pending["until"] -= 60
        handled, events = self.ask("yes")
        self.assertFalse(handled)
        self.assertEqual(self.actions(events), [])

    def test_a_yes_with_nothing_pending_is_not_a_command(self):
        for text in ("yes", "do it", "go ahead"):
            handled, _ = self.ask(text)
            self.assertFalse(handled, text)

    def test_normal_commands_are_never_marked_confirmed(self):
        handled, events = self.ask("turn on night light")
        self.assertEqual(self.actions(events), [("toggle", False)])

    def test_info_is_answered_from_the_context(self):
        handled, events = self.ask("what time is it", "time: Thu 19 Nov 2026, 07:05")
        self.assertTrue(handled)
        self.assertEqual(events[-1]["text"], "It's 7:05 AM.")

    def test_info_without_the_data_goes_to_the_model(self):
        handled, events = self.ask("battery", "time: Thu 19 Nov 2026, 07:05")
        self.assertFalse(handled)


if __name__ == "__main__":
    unittest.main()

"""Offline regressions for the orb helper and its native agent boundary."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import opencode_bridge
import voice_agent
import voice_metrics


class VoiceTurnBoundaries(unittest.TestCase):
    def setUp(self):
        self.model = voice_agent.Model()

    @mock.patch.object(voice_agent, "emit")
    def test_session_change_clears_confirmation(self, emit):
        self.model.scope("first")
        self.model.ask_rules("a", "close this window", via="spoken", target="one")
        self.model.scope("second")
        self.assertFalse(self.model.ask_rules("b", "yes", via="spoken", target="one"))
        self.assertNotIn("action", [call.args[0]["event"] for call in emit.call_args_list])

    @mock.patch.object(voice_agent, "emit")
    def test_close_confirmation_requires_same_surface_and_window(self, emit):
        for via, target in (("typed", "one"), ("spoken", "two")):
            self.model.ask_rules("a", "close this window", via="spoken", target="one")
            self.assertFalse(self.model.ask_rules("b", "yes", via=via, target=target))
        self.assertNotIn("action", [call.args[0]["event"] for call in emit.call_args_list])

    def test_local_context_is_not_serialized_to_model(self):
        with mock.patch.object(self.model, "start"), mock.patch.object(self.model, "send") as send, \
                mock.patch.object(self.model, "turn"):
            self.model.ask("a", "hello", lambda: False, context="focused: private title",
                           remote_context="battery: 40%", via="spoken", session="chat")
        body = send.call_args.args[0]
        self.assertIn("battery: 40%", body)
        self.assertNotIn("private title", body)

    def test_cancelled_queued_turn_does_not_start_or_run_rules(self):
        with mock.patch.object(self.model, "start") as start, mock.patch.object(self.model, "ask_rules") as rules:
            self.model.ask("a", "hello", lambda: True)
        start.assert_not_called()
        rules.assert_not_called()

    @mock.patch.object(voice_agent, "emit")
    def test_stalled_stream_terminates(self, emit):
        with mock.patch.object(self.model, "stop") as stop, mock.patch.object(voice_agent.time, "monotonic", return_value=20):
            self.model.turn("a", 0, lambda: False)
        stop.assert_called_once()
        self.assertEqual(emit.call_args.args[0]["event"], "error")

    def test_signed_in_auto_mode_preserves_sensitive_approvals(self):
        for name in ("browser_call", "desktop_capture", "desktop_input", "speak_text"):
            self.assertEqual(opencode_bridge.tool_effect(name, auto=True, config_writes=True), "ask")

    def test_metrics_scrub_legacy_text_and_bound_storage(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "voice-timings.jsonl"
            row = {"at": "2026-11-25T12:00:00Z", "route": "haiku", "text": "fixture private text"}
            path.write_text((json.dumps(row) + "\n") * (voice_metrics.LIMIT + 20))
            os.chmod(path, 0o644)
            voice_metrics.update(path, "record", {**row, "firstTokenMs": 42})
            records = [json.loads(line) for line in path.read_text().splitlines()]
            self.assertEqual(len(records), voice_metrics.LIMIT)
            self.assertTrue(all("text" not in record for record in records))
            self.assertEqual(records[-1]["firstTokenMs"], 42)
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            archive = path.with_suffix(".legacy-private.jsonl")
            self.assertEqual(archive.stat().st_mode & 0o777, 0o600)
            voice_metrics.update(path, "clear")
            self.assertFalse(path.exists())
            self.assertFalse(archive.exists())


if __name__ == "__main__":
    unittest.main()

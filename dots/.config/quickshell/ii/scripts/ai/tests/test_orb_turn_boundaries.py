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

    def look(self, setting, turn_flag, replies=("look", None), cancelled=lambda: False):
        """Ask a question whose model answers by asking to see the screen."""
        self.model.configure({"screen": setting})
        with mock.patch.object(self.model, "start"), mock.patch.object(self.model, "stop"), \
                mock.patch.object(self.model, "send") as send, \
                mock.patch.object(self.model, "turn", side_effect=list(replies)), \
                mock.patch.object(voice_agent, "capture_screen", return_value="cGljdHVyZQ==") as capture, \
                mock.patch.object(voice_agent, "emit") as emit:
            self.model.ask("a", "what is on my screen", cancelled, screen=turn_flag, session="chat")
        return capture, send, [call.args[0]["event"] for call in emit.call_args_list]

    def test_screen_is_captured_only_when_setting_and_turn_both_allow_it(self):
        for setting, turn_flag in ((False, False), (False, True), (True, False)):
            with self.subTest(setting=setting, turn=turn_flag):
                self.model = voice_agent.Model()
                capture, send, events = self.look(setting, turn_flag)
                capture.assert_not_called()
                self.assertEqual(send.call_count, 1)
                self.assertEqual(events, ["look-required"])

    def test_allowed_look_sends_one_screenshot(self):
        capture, send, events = self.look(True, True)
        capture.assert_called_once()
        self.assertEqual(events, ["looking"])
        self.assertEqual(send.call_args.args[0][0]["source"]["data"], "cGljdHVyZQ==")

    def test_a_second_look_in_one_turn_is_not_followed(self):
        capture, send, events = self.look(True, True, replies=("look", "look"))
        capture.assert_called_once()
        self.assertEqual(events, ["looking", "done"])

    def test_nothing_is_captured_without_being_asked_for(self):
        capture, _, events = self.look(True, True, replies=(None,))
        capture.assert_not_called()
        self.assertEqual(events, [])

    def test_changing_the_screen_setting_drops_the_conversation(self):
        with mock.patch.object(self.model, "stop") as stop:
            self.model.configure({"screen": True})
            self.model.configure({"screen": True})
            self.model.configure({"screen": False})
        self.assertEqual(stop.call_count, 2)

    def test_prompt_follows_the_setting(self):
        self.assertIn("[[LOOK]]", voice_agent.system_prompt("en", True))
        self.assertNotIn("[[LOOK]]", voice_agent.system_prompt("en", False))
        self.assertNotIn("[[LOOK]]", voice_agent.system_prompt("en"))

    def test_switching_the_orb_off_closes_every_way_in(self):
        root = Path(__file__).resolve().parents[3]
        voice = (root / "services/ai/AiCompanionVoiceService.qml").read_text()
        ui = (root / "services/ai/AiCompanionUi.qml").read_text()
        window = (root / "modules/ii/aiCompanion/AiCompanion.qml").read_text()
        source = (root / "modules/ii/dynamicIsland/core/sources/CompanionSource.qml").read_text()
        for entry in ("function start(hold = false) {\n        if (!root.orbEnabled",
                      "if (!root.orbEnabled || root.holdHeld",
                      "function ask(text) {\n        if (!root.orbEnabled) return;",
                      "return root.orbEnabled && settings.typedRouting",
                      "running: root.orbEnabled && Config.options.ai.voice.sessionAlerts",
                      "wakeWanted: root.orbEnabled &&",
                      "(root.orbEnabled && AiCompanionUi.saved.visible)",
                      "voiceAgent.running = false"):
            self.assertIn(entry, voice)
        for name in ("show", "toggle", "undock"):
            self.assertRegex(ui, r"function %s\(\): void \{\s*if \(!root\.orbEnabled\) return;" % name)
        self.assertIn("root.ui.orbEnabled && root.saved.visible", window)
        self.assertIn("if (!root.ui.orbEnabled || GlobalStates.screenLocked) return;", window)
        self.assertIn("AiCompanionUi.orbEnabled &&", source)

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

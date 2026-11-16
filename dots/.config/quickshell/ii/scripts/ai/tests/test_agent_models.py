"""Native model discovery never needs a generation request or credential export."""
import json
from pathlib import Path
import sys
import tempfile
import time
import unittest
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import agent_models as models
import agent_bridge as bridge


class Catalogs(unittest.TestCase):
    def test_codex_uses_actual_ids_default_and_image_capabilities(self):
        rows = models.codex_entries({"data": [
            {"model": "visible", "displayName": "Visible", "isDefault": True, "inputModalities": ["text", "image"]},
            {"model": "text-only", "inputModalities": ["text"]},
            {"model": "hidden", "hidden": True},
        ]})
        self.assertEqual([row["value"] for row in rows], ["default", "visible", "text-only"])
        self.assertEqual(rows[0]["title"], "Default · Visible")
        self.assertTrue(rows[1]["vision"])
        self.assertFalse(rows[2]["vision"])

    def test_claude_preserves_cli_aliases_and_resolved_default(self):
        rows = models.claude_entries({"models": [
            {"value": "default", "description": "Haiku 5.5", "resolvedModel": "claude-haiku-5-5"},
            {"value": "opus", "displayName": "Opus 5.5", "resolvedModel": "claude-opus-5-5"},
        ]})
        self.assertEqual(rows[0]["title"], "Default · Haiku 5.5")
        self.assertEqual(rows[1]["value"], "opus")
        self.assertEqual(rows[1]["resolvedModel"], "claude-opus-5-5")

    def test_explicit_native_model_is_forwarded_without_changing_login(self):
        with tempfile.TemporaryDirectory() as directory:
            for engine, value in (("codex", "gpt-6-luna"), ("claude", "opus")):
                argv = bridge.command(engine, {"model": {"modelID": value}}, Path(directory))
                self.assertEqual(argv[argv.index("--model") + 1], value)
            for engine in ("codex", "claude"):
                argv = bridge.command(engine, {"model": {"modelID": "default"}}, Path(directory))
                self.assertNotIn("--model", argv)

    def test_fresh_cache_does_not_launch_another_cli(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(bridge, "STATE", Path(directory)), mock.patch.object(models.shutil, "which", return_value=sys.executable):
            rows = [{"value": "test"}]
            Path(directory, "codex-models.json").write_text(json.dumps({"updated": time.time(), "binaryMtime": Path(sys.executable).stat().st_mtime, "models": rows}))
            with mock.patch.object(models, "discover") as discover:
                self.assertEqual(models.cached("codex"), rows)
                discover.assert_not_called()

    def test_failed_refresh_retains_previous_model_choices(self):
        with tempfile.TemporaryDirectory() as directory, mock.patch.object(bridge, "STATE", Path(directory)), mock.patch.object(models.shutil, "which", return_value=sys.executable):
            Path(directory, "claude-models.json").write_text(json.dumps({"updated": 0, "models": [{"value": "haiku"}]}))
            with mock.patch.object(models, "discover", side_effect=RuntimeError("offline")):
                self.assertEqual(models.cached("claude"), [{"value": "haiku"}])

    def test_batched_protocol_lines_are_consumed_without_another_read(self):
        code = "import sys,json;sys.stdin.readline();print(json.dumps({'id':1}),flush=True);print(json.dumps({'id':2,'models':['test']}),flush=True);sys.stdin.readline()"
        def consume(row, send):
            if row.get("id") == 2:
                return row["models"]
        self.assertEqual(models.query([sys.executable, "-c", code], {"initialize": True}, consume), ["test"])

    def test_claude_discovery_sends_only_control_initialization(self):
        with mock.patch.object(models, "query", return_value=[]) as query:
            models.discover("claude")
        first = query.call_args.args[1]
        self.assertEqual(first["type"], "control_request")
        self.assertEqual(first["request"]["subtype"], "initialize")
        self.assertNotIn("message", first)


if __name__ == "__main__":
    unittest.main()

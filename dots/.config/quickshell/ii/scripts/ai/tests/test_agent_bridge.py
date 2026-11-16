"""Signed-in backend auth, stream normalization, scoped tools and approvals."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import uuid
from unittest import mock

AI = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(AI))
import agent_bridge as bridge


class Streams(unittest.TestCase):
    def events(self, engine, rows):
        output = io.StringIO()
        stream = bridge.Stream(engine)
        with contextlib.redirect_stdout(output):
            for row in rows: stream.consume(row)
        return stream, [json.loads(line) for line in output.getvalue().splitlines()]

    def test_codex_text_and_usage_share_the_ui_contract(self):
        stream, events = self.events("codex", [
            {"type": "item.completed", "item": {"type": "agent_message", "text": "Checking."}},
            {"type": "item.completed", "item": {"type": "agent_message", "text": "Done."}},
            {"type": "turn.completed", "usage": {"input_tokens": 12, "output_tokens": 5}},
        ])
        self.assertTrue(stream.completed)
        self.assertEqual("".join(e["data"].get("delta", "") for e in events), "Checking.\n\nDone.")
        self.assertEqual(events[-1]["data"]["tokens"]["input"], 12)

    def test_claude_deltas_are_not_duplicated_by_result(self):
        stream, events = self.events("claude", [
            {"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "Hello"}}},
            {"type": "result", "result": "Hello", "is_error": False, "usage": {}},
        ])
        self.assertTrue(stream.completed)
        self.assertEqual([e["data"]["delta"] for e in events if e["type"] == "session.text.delta"], ["Hello"])

    def test_claude_without_deltas_uses_the_final_result(self):
        stream, events = self.events("claude", [{"type": "result", "result": "Hello", "is_error": False}])
        self.assertTrue(stream.completed)
        self.assertEqual(events[0]["data"]["delta"], "Hello")

    def test_provider_errors_do_not_become_success(self):
        codex, _ = self.events("codex", [{"type": "turn.failed", "error": {"message": "Sign in required"}}])
        claude, _ = self.events("claude", [{"type": "result", "is_error": True, "errors": ["Sign in required"]}])
        for stream in (codex, claude):
            self.assertFalse(stream.completed)
            self.assertIn("Sign in", stream.failed)


class Authentication(unittest.TestCase):
    def test_missing_clis_report_not_installed_without_breaking_discovery(self):
        with mock.patch.object(bridge.shutil, "which", return_value=None), mock.patch.object(bridge.oc, "opencode_binary", side_effect=bridge.oc.BridgeError("missing")):
            entries = bridge.status()
        self.assertEqual([entry["id"] for entry in entries], ["codex", "claude", "opencode"])
        self.assertTrue(all(not entry["installed"] and not entry["signedIn"] for entry in entries))

    def test_api_keys_and_nested_cli_markers_are_not_forwarded(self):
        with mock.patch.dict(os.environ, {"OPENAI_API_KEY": "secret", "ANTHROPIC_API_KEY": "secret", "CLAUDECODE": "1"}):
            env = bridge.environment()
            self.assertNotIn("OPENAI_API_KEY", env)
            self.assertNotIn("ANTHROPIC_API_KEY", env)
            self.assertNotIn("CLAUDECODE", env)

    def test_commands_reuse_auth_but_isolate_tools_and_configuration(self):
        with tempfile.TemporaryDirectory() as tmp:
            body = {"tools": ["read_file"], "model": {"modelID": "default"}}
            codex = bridge.command("codex", body, Path(tmp))
            claude = bridge.command("claude", body, Path(tmp))
            self.assertIn("--ignore-user-config", codex)
            self.assertIn("--no-daemon", codex)
            self.assertIn('mcp_servers.ii-shell.default_tools_approval_mode="approve"', codex)
            self.assertIn("--strict-mcp-config", claude)
            self.assertEqual(claude[claude.index("--tools") + 1], "")
            self.assertNotIn("--bare", claude, "bare mode disables subscription OAuth")

    def test_native_mcp_children_keep_the_shell_desktop_connection(self):
        # Codex deliberately does not inherit WAYLAND_DISPLAY into MCP children.
        # Omitting it makes qs report every matching shell instance as dead.
        desktop = {"WAYLAND_DISPLAY": "wayland-test", "DISPLAY": ":9", "XDG_RUNTIME_DIR": "/run/user/9999", "QT_QPA_PLATFORM": "wayland"}
        with tempfile.TemporaryDirectory() as tmp, mock.patch.dict(os.environ, {**desktop, "OPENAI_API_KEY": "must-not-copy"}):
            directory = Path(tmp)
            argv = bridge.command("codex", {"tools": ["system_get_status"]}, directory)
            settings = dict(arg.split("=", 1) for arg in argv if arg.startswith("mcp_servers.ii-shell.env."))
            for key, value in desktop.items():
                self.assertEqual(json.loads(settings["mcp_servers.ii-shell.env." + key]), value)
            bridge.command("claude", {"tools": ["system_get_status"]}, directory)
            env = json.loads((directory / "mcp.json").read_text())["mcpServers"]["ii-shell"]["env"]
            for key, value in desktop.items():
                self.assertEqual(env[key], value)
            self.assertNotIn("OPENAI_API_KEY", env)
            self.assertNotIn("mcp_servers.ii-shell.env.OPENAI_API_KEY", settings)

    def test_attachment_text_and_images_are_preserved_for_claude(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp)/"notes.txt"; path.write_text("My file")
            image = Path(tmp)/"image.png"; image.write_bytes(b"PNG sample")
            message = bridge.prompt({"text": "Read this", "files": [
                {"kind": "text", "name": path.name, "path": str(path)},
                {"kind": "image", "name": image.name, "path": str(image), "mime": "image/png"},
            ]}, "claude")
            content = json.loads(message)["message"]["content"]
            self.assertIn("My file", content[0]["text"])
            self.assertEqual(content[1]["source"]["media_type"], "image/png")

    def test_approval_path_cannot_escape_run_directory(self):
        with self.assertRaises(ValueError): bridge.answer("agent_../../bad", "req_123", "once")


class ScopedTools(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.run = self.root / ("agent_" + uuid.uuid4().hex)
        self.run.mkdir(mode=0o700)
        self.env = os.environ.copy()
        self.env.update({"HOME": str(self.root), "XDG_STATE_HOME": str(self.root / "state"), "II_AGENT_REQUEST": str(self.run / "request.json")})

    def start(self, tools, auto, message):
        (self.run / "request.json").write_text(json.dumps({"tools": tools, "auto": auto}))
        process = subprocess.Popen([sys.executable, str(AI / "agent_tools_mcp.py")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, env=self.env)
        self.addCleanup(self.cleanup_process, process)
        process.stdin.write(json.dumps(message) + "\n"); process.stdin.flush()
        return process

    def cleanup_process(self, process):
        if process.poll() is None: process.terminate()
        process.communicate(timeout=4)

    def wait_for_approval(self):
        deadline = time.monotonic() + 5
        while time.monotonic() < deadline:
            path = self.run / "events.jsonl"
            if path.exists():
                for line in path.read_text().splitlines():
                    event = json.loads(line)
                    if event["type"] == "permission.asked": return event["data"]
            time.sleep(.03)
        self.fail("No approval event arrived")

    def test_unoffered_tools_are_not_listed(self):
        process = self.start(["read_file"], True, {"jsonrpc": "2.0", "id": 1, "method": "tools/list"})
        result = json.loads(process.stdout.readline())
        self.assertEqual([t["name"] for t in result["result"]["tools"]], ["read_file"])

    def test_auto_off_waits_for_the_card_before_writing(self):
        target = self.root / "approved.txt"
        process = self.start(["write_file"], False, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
            "name": "write_file", "arguments": {"path": str(target), "content": "approved"}}})
        approval = self.wait_for_approval()
        self.assertFalse(target.exists())
        with mock.patch.object(bridge, "RUNS", self.root): bridge.answer(self.run.name, approval["id"], "once")
        self.assertFalse(json.loads(process.stdout.readline())["result"]["isError"])
        self.assertEqual(target.read_text(), "approved")

    def test_auto_on_still_requires_approval_for_privileged_commands(self):
        process = self.start(["run_privileged_command"], True, {"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {
            "name": "run_privileged_command", "arguments": {"command": "echo forbidden"}}})
        approval = self.wait_for_approval()
        with mock.patch.object(bridge, "RUNS", self.root): bridge.answer(self.run.name, approval["id"], "reject")
        result = json.loads(process.stdout.readline())["result"]
        self.assertTrue(result["isError"])
        self.assertIn("did not approve", result["content"][0]["text"])


if __name__ == "__main__": unittest.main()

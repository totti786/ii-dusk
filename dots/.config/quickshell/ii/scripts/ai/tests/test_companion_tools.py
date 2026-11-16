"""Boundary and transport checks for the desktop companion (no real input)."""
import base64
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import unittest
from unittest.mock import patch

AI = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, AI / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


c = load("companion_tools")
mcp = load("shell_tools_mcp")


class Companion(unittest.TestCase):
    def test_shortcut_releases_modifiers_in_reverse_order(self):
        self.assertEqual(c.shortcut_codes("CTRL SHIFT, C"), ["29:1", "42:1", "46:1", "46:0", "42:0", "29:0"])
        with self.assertRaises(ValueError):
            c.shortcut_codes("FAKE, C")

    def test_capture_keeps_image_and_coordinate_metadata_through_mcp(self):
        png = b"\x89PNG\r\n\x1a\n" + bytes(8) + (960).to_bytes(4, "big") + (540).to_bytes(4, "big")
        monitor = {"name": "DP-1", "x": -960, "y": 20, "focused": True}
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "monitors", return_value=[monitor]), patch.object(c, "run", return_value=png):
            result = c.capture({})
        info = json.loads(result["text"])
        self.assertEqual(info["origin"], {"x": -960, "y": 20})
        self.assertEqual(info["imageWidth"], 960)
        self.assertEqual(base64.b64decode(result["content"][1]["data"]), png)
        output = io.StringIO()
        with patch.object(mcp.companion, "call_tool", return_value=result), contextlib.redirect_stdout(output):
            mcp.handle({"jsonrpc": "2.0", "id": 1, "method": "tools/call", "params": {"name": "desktop_capture", "arguments": {}}})
        self.assertEqual(json.loads(output.getvalue())["result"]["content"], result["content"])

    def test_capture_refuses_an_unknown_monitor(self):
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "monitors", return_value=[]):
            with self.assertRaises(ValueError):
                c.capture({"monitor": "missing"})

    def test_offscreen_input_never_dispatches(self):
        screen = {"width": 1920, "height": 1080, "scale": 2, "x": 0, "y": 0}
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "monitors", return_value=[screen]), patch.object(c, "run") as run:
            with self.assertRaises(ValueError):
                c.desktop_input({"action": "move", "x": 1000, "y": 100})
            run.assert_not_called()

    def test_negative_global_coordinates_and_scaled_monitor_are_valid(self):
        screen = {"width": 1920, "height": 1080, "scale": 2, "x": -960, "y": 0}
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "monitors", return_value=[screen]), patch.object(c, "run") as run:
            c.desktop_input({"action": "move", "x": -400, "y": 100})
            self.assertEqual(run.call_args.args[0], ["hyprctl", "dispatch", "hl.dsp.cursor.move({ x = -400, y = 100 })"])

    def test_shortcuts_and_unknown_actions_are_validated(self):
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "run") as run:
            for args in ({"action": "key", "key": "CTRL, C; exec bad"}, {"action": "delete"}, {"action": "type", "text": ""}):
                with self.assertRaises(ValueError):
                    c.desktop_input(args)
            run.assert_not_called()

    def test_speech_passes_literal_text_on_stdin_and_cleans_audio(self):
        with patch.object(c, "run", return_value=b"") as run:
            c.speak_edge({"text": "$(touch /tmp/no) `bad`"})
        self.assertEqual(run.call_args_list[0].kwargs["data"], b"$(touch /tmp/no) `bad`")
        self.assertTrue(run.call_args_list[0].args[0][0].endswith("edge-tts"))
        self.assertFalse(Path(run.call_args_list[1].args[0][-1]).exists())

    def test_invalid_speech_never_starts_processes(self):
        with patch.object(c, "run") as run:
            for args in ({"text": ""}, {"text": "a" * 4001}, {"text": "hi", "voice": "../../x"}, {"text": "hi", "rate": 999}):
                with self.assertRaises(ValueError):
                    c.speak(args)
            run.assert_not_called()

    def test_browser_mcp_errors_and_images_are_preserved(self):
        content = [{"type": "image", "mimeType": "image/png", "data": "abc"}]
        with patch.object(c.BROWSER, "start"), patch.object(c.BROWSER, "request", return_value={"content": content, "isError": True}) as request:
            result = c.call_tool("browser_call", {"name": "execute", "arguments": {"code": "return 1"}})
            self.assertTrue(result["isError"])
            self.assertEqual(result["content"][1:], content)
            request.assert_called_once_with("tools/call", {"name": "execute", "arguments": {"code": "return 1"}})

    def test_browser_discovery_omits_large_output_schemas(self):
        listing = {"tools": [{"name": "execute", "description": "Run", "inputSchema": {"type": "object"}, "outputSchema": {"huge": "x" * 100000}}]}
        with patch.object(c.BROWSER, "start"), patch.object(c.BROWSER, "request", return_value=listing):
            result = json.loads(c.call_tool("browser_tools", {})["text"])
        self.assertEqual(result["tools"][0]["inputSchema"], {"type": "object"})
        self.assertNotIn("outputSchema", result["tools"][0])

    def test_focus_rejects_stale_or_injected_window_addresses(self):
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "run", return_value=b'[]') as run:
            for address in ("0xdead", '0x12\"); bad()', None):
                with self.assertRaises(ValueError):
                    c.desktop_input({"action": "focus", "window": address})
            self.assertTrue(all(call.args[0] == ["hyprctl", "-j", "clients"] for call in run.call_args_list))

    def test_scroll_rejects_invalid_steps_before_input(self):
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "run") as run:
            for value in (0, 21, -21, True, "2"):
                with self.assertRaises(ValueError):
                    c.desktop_input({"action": "scroll", "vertical": value})
            run.assert_not_called()

    def test_scroll_uses_private_socket_and_downward_wheel_sign(self):
        with patch.object(c, "desktop_env", return_value={"XDG_RUNTIME_DIR": "/run/user/999"}), patch.object(c, "run") as run:
            c.desktop_input({"action": "scroll", "vertical": 3, "horizontal": 2})
        self.assertEqual(run.call_args.args[0], ["ydotool", "mousemove", "--wheel", "--", "2", "-3"])
        self.assertEqual(run.call_args.kwargs["env"]["YDOTOOL_SOCKET"], "/run/user/999/ii-companion-input.sock")

    def test_unicode_typing_uses_wtype_stdin(self):
        text = "مرحبا بالعالم — hello"
        with patch.object(c, "desktop_env", return_value={}), patch.object(c.shutil, "which", return_value="/usr/bin/wtype"), patch.object(c, "run") as run:
            c.desktop_input({"action": "type", "text": text})
        self.assertEqual(run.call_args.args[0], ["wtype", "-d", "2", "-"])
        self.assertEqual(run.call_args.kwargs["data"], text.encode())

    def test_typing_does_not_retry_after_ambiguous_failure(self):
        with patch.object(c, "desktop_env", return_value={}), patch.object(c.shutil, "which", return_value="/usr/bin/wtype"), patch.object(c, "run", side_effect=RuntimeError("disconnected during typing")) as run:
            with self.assertRaises(RuntimeError):
                c.desktop_input({"action": "type", "text": "hello"})
        self.assertEqual(run.call_count, 1)

    def test_ascii_typing_falls_back_if_protocol_is_unavailable(self):
        with patch.object(c, "desktop_env", return_value={}), patch.object(c.shutil, "which", return_value="/usr/bin/wtype"), patch.object(c, "run", side_effect=[RuntimeError("Compositor does not support the virtual keyboard protocol"), b""]) as run:
            c.desktop_input({"action": "type", "text": "hello"})
        self.assertEqual(run.call_args.args[0][:2], ["ydotool", "type"])

    def test_drag_releases_button_even_when_motion_fails(self):
        screen = {"width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0}
        calls = []
        def run(argv, **kwargs):
            calls.append(argv)
            if argv[:2] == ["ydotool", "mousemove"]:
                raise RuntimeError("motion failed")
            return b""
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "monitors", return_value=[screen]), patch.object(c.Path, "exists", return_value=True), patch.object(c.time, "sleep"), patch.object(c, "run", side_effect=run):
            with self.assertRaisesRegex(RuntimeError, "motion failed"):
                c.desktop_input({"action": "drag", "x": 10, "y": 10, "endX": 100, "endY": 100})
        self.assertIn(["ydotool", "click", "0x40"], calls)
        self.assertEqual(calls[-1], ["ydotool", "click", "0x80"])

    def test_drag_rejects_offscreen_destination_before_press(self):
        screen = {"width": 1920, "height": 1080, "scale": 1, "x": 0, "y": 0}
        with patch.object(c, "desktop_env", return_value={}), patch.object(c, "monitors", return_value=[screen]), patch.object(c, "run") as run:
            with self.assertRaises(ValueError):
                c.desktop_input({"action": "drag", "x": 10, "y": 10, "endX": 2000, "endY": 100})
            run.assert_not_called()


if __name__ == "__main__":
    unittest.main()

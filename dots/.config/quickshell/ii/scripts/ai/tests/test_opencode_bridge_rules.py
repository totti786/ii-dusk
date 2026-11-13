#!/usr/bin/env python3
"""Which of the shell's tools an OpenCode session may run without the user, and how the tool server is kept current."""

import importlib.util
import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

AI = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, AI / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


bridge = load("opencode_bridge")
mcp = load("shell_tools_mcp")


def effects(**modes):
    rules = bridge.session_rules(list(bridge.SHELL_TOOLS), **modes)
    return {rule["action"][len(bridge.SHELL_TOOL_SERVER) + 1:]: rule["effect"] for rule in rules[1:]}


class Rules(unittest.TestCase):
    def test_the_bridge_and_the_tool_server_offer_the_same_tools(self):
        self.assertEqual(set(bridge.SHELL_TOOLS), mcp.TOOL_NAMES)
        self.assertEqual(len(bridge.SHELL_TOOLS), len(set(bridge.SHELL_TOOLS)))

    def test_every_tool_has_a_decided_class(self):
        classes = bridge.READ_TOOLS | bridge.CONFIG_WRITE_TOOLS | bridge.AUTO_TOOLS | bridge.ALWAYS_ASK_TOOLS
        self.assertEqual(classes, set(bridge.SHELL_TOOLS))

    def test_everything_else_is_denied_first(self):
        rules = bridge.session_rules(["read_file"])
        self.assertEqual(rules[0], {"action": "*", "resource": "*", "effect": "deny"})

    def test_default_modes_reads_and_config_run_free_and_the_rest_asks(self):
        found = effects(auto=False, config_writes=True)
        for tool in bridge.READ_TOOLS | {"settings_set"}:
            self.assertEqual(found[tool], "allow", tool)
        for tool in bridge.AUTO_TOOLS | bridge.ALWAYS_ASK_TOOLS:
            self.assertEqual(found[tool], "ask", tool)

    def test_auto_mode_frees_commands_and_edits_but_never_the_privileged_tool(self):
        found = effects(auto=True, config_writes=True)
        for tool in bridge.AUTO_TOOLS:
            self.assertEqual(found[tool], "allow", tool)
        self.assertEqual(found["run_privileged_command"], "ask")

    def test_config_writes_can_be_turned_back_into_a_question(self):
        self.assertEqual(effects(auto=True, config_writes=False)["settings_set"], "ask")

    def test_no_mode_ever_frees_the_privileged_tool(self):
        for auto in (False, True):
            for config in (False, True):
                self.assertEqual(effects(auto=auto, config_writes=config)["run_privileged_command"], "ask")

    def test_an_unknown_tool_asks(self):
        self.assertEqual(bridge.tool_effect("something_new", True, True), "ask")

    def test_every_write_or_command_tool_is_gated(self):
        # a tool the server can run that changes things must not be classed as a read
        for tool in ("write_file", "run_shell_command", "run_privileged_command", "undo_change", "settings_set", "brightness_set"):
            self.assertNotIn(tool, bridge.READ_TOOLS)


class Registry(unittest.TestCase):
    """The shell's registry decides which tool names reach OpenCode; the bridge drops any it does not serve."""

    @staticmethod
    def opencode_tools():
        import re
        registry = (AI.parents[1] / "services" / "ai" / "AiToolRegistry.qml").read_text(encoding="utf-8")
        raw = registry.split("rawDefinitions: [", 1)[1].split("\n    ]\n", 1)[0]
        found = {}
        for block in re.split(r"\n        \{\n", raw):
            ident = re.search(r'id: "([a-z_]+)",', block)
            formats = re.search(r"formats: \[([^\]]*)\]", block)
            if ident and formats and "opencode" in re.findall(r'"(\w+)"', formats.group(1)):
                found[ident.group(1)] = block
        return found

    def test_every_tool_offered_to_opencode_is_served(self):
        offered = set(self.opencode_tools())
        self.assertEqual(offered - set(bridge.SHELL_TOOLS), set(), "offered but the bridge would drop it")
        self.assertEqual(set(bridge.SHELL_TOOLS) - offered, set(), "served but never offered by the registry")

    def test_the_registry_never_marks_a_gated_tool_as_standing_allowed(self):
        import re
        for name in bridge.AUTO_TOOLS | bridge.ALWAYS_ASK_TOOLS:
            block = self.opencode_tools()[name]
            with self.subTest(tool=name):
                self.assertIn('defaultApproval: "ask"', block)
                if name != "brightness_set":
                    self.assertIn("neverAutoApprove: true", block)


class Registration(unittest.TestCase):
    class Server:
        def __init__(self, status):
            self.status = status
            self.calls = []

        def call(self, method, path, body=None, timeout=30):
            self.calls.append((method, path.split("?")[0]))
            if method == "GET":
                return {"data": [{"name": bridge.SHELL_TOOL_SERVER, "status": {"status": self.status}}]}
            return None

    def test_a_current_connected_server_is_left_alone(self):
        server = self.Server("connected")
        state = {bridge.MCP_REVISION_KEY: bridge.script_revision()}
        bridge.ensure_shell_tools(server, "/w", state)
        self.assertFalse([c for c in server.calls if c[0] != "GET"])

    def test_an_older_script_is_registered_again_and_restarted(self):
        server = self.Server("connected")
        state = {bridge.MCP_REVISION_KEY: "old"}
        bridge.ensure_shell_tools(server, "/w", state)
        verbs = [c for c in server.calls if c[0] != "GET"]
        self.assertEqual(verbs[0][0], "PUT")
        self.assertEqual([v[1].rsplit("/", 1)[1] for v in verbs[1:]], ["disconnect", "connect"])
        self.assertEqual(state[bridge.MCP_REVISION_KEY], bridge.script_revision())

    def test_a_missing_server_is_registered(self):
        server = self.Server("connected")
        original = server.call
        seen = {"n": 0}

        def call(method, path, body=None, timeout=30):
            if method == "GET" and seen["n"] == 0:
                seen["n"] += 1
                return {"data": []}
            return original(method, path, body, timeout)

        server.call = call
        bridge.ensure_shell_tools(server, "/w", {})
        self.assertTrue([c for c in server.calls if c[0] == "PUT"])


class Mode(unittest.TestCase):
    def test_the_mode_file_lands_where_the_tool_server_reads_it(self):
        with tempfile.TemporaryDirectory() as home, mock.patch.dict(os.environ, {"XDG_STATE_HOME": home}):
            tools = load("shell_tools_mcp")
            sessions = os.path.join(tools.STATE_DIR, "opencode-sessions.json")
            bridge.write_mode(sessions, True)
            self.assertTrue(os.path.exists(tools.MODE_FILE))
            self.assertTrue(tools.auto_mode_on())
            bridge.write_mode(sessions, False)
            self.assertFalse(tools.auto_mode_on())


if __name__ == "__main__":
    unittest.main()

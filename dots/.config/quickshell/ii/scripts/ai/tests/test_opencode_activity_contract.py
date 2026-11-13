#!/usr/bin/env python3
"""What an OpenCode chat shows for the calls it makes: the wording, and that every piece is wired."""

import json
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
AI = ROOT / "services" / "ai"
ACTIVITY = AI / "OpencodeActivity.js"
STRATEGY = (AI / "OpencodeStrategy.qml").read_text(encoding="utf-8")
MESSAGE = (ROOT / "modules" / "ii" / "sidebarPolicies" / "aiChat" / "AiMessage.qml").read_text(encoding="utf-8")
AI_QML = (ROOT / "services" / "Ai.qml").read_text(encoding="utf-8")


def js(expression: str):
    script = (
        "const fs=require('fs'),vm=require('vm');const c={};vm.createContext(c);"
        f"vm.runInContext(fs.readFileSync({str(ACTIVITY)!r},'utf8').replace('.pragma library',''),c);"
        f"console.log(JSON.stringify({expression}));")
    return json.loads(subprocess.run(["node", "-e", script], capture_output=True, text=True, check=True).stdout)


@unittest.skipUnless(shutil.which("node"), "node is needed to run the helper")
class Wording(unittest.TestCase):
    def test_a_setting_change_shows_old_and_new_and_what_was_refused(self):
        result = js('c.finished("settings_set",{},JSON.stringify({applied:[{key:"bar.x",value:true,previous:false}],'
                    'skipped:[{key:"apps.terminal",reason:"protected"}]}))')
        self.assertEqual(result["title"], "Changed 1 setting")
        self.assertIn("bar.x: false → true", result["detail"])
        self.assertIn("apps.terminal: not changed (protected)", result["detail"])
        self.assertTrue(result["ok"])

    def test_a_refused_change_is_not_shown_as_a_success(self):
        result = js('c.finished("settings_set",{},JSON.stringify({applied:[],skipped:[{key:"a",reason:"protected"}]}))')
        self.assertEqual(result["title"], "Changed nothing")
        self.assertFalse(result["ok"])

    def test_a_failed_call_carries_the_reason(self):
        result = js('c.finished("read_file",{path:"~/.ssh/id_ed25519"},"","refused")')
        self.assertFalse(result["ok"])
        self.assertEqual(result["detail"], "refused")

    def test_a_command_shows_its_first_line_and_exit_code(self):
        result = js('c.finished("run_shell_command",{command:"ls -la\\nrm x"},"Exit code 2\\nboom")')
        self.assertEqual(result["title"], "Running ls -la")
        self.assertEqual(result["detail"], "Exit code 2")
        self.assertFalse(result["ok"])

    def test_a_first_line_does_not_hide_the_rest_of_a_long_command_title(self):
        long = js('c.running("run_shell_command",{command:"x".repeat(500)})')
        self.assertLess(len(long), 100)

    def test_garbage_results_do_not_throw(self):
        for tool in ("settings_set", "settings_search", "write_file", "unknown_tool"):
            with self.subTest(tool=tool):
                self.assertIn("title", js(f'c.finished("{tool}",null,"not json",null)'))

    def test_every_served_tool_has_an_icon_and_a_title(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("bridge", ROOT / "scripts" / "ai" / "opencode_bridge.py")
        bridge = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(bridge)
        icons = js("c.ICONS")
        for tool in bridge.SHELL_TOOLS:
            with self.subTest(tool=tool):
                self.assertIn(tool, icons)
                self.assertFalse(js(f'c.running("{tool}",{{}})').startswith("Using "))


class Wiring(unittest.TestCase):
    def test_the_strategy_draws_calls_that_did_not_ask_and_leaves_asked_ones_to_the_approval_card(self):
        self.assertIn('case "session.tool.called"', STRATEGY)
        self.assertIn("toolCallId", STRATEGY)
        self.assertIn('"merged"', STRATEGY)
        self.assertIn('import "OpencodeActivity.js" as Activity', STRATEGY)

    def test_a_late_result_cannot_bring_back_a_merged_card(self):
        body = STRATEGY.split('case "session.tool.success"', 1)[1].split('case "permission.asked"', 1)[0]
        self.assertIn('card.state === "merged"', body)

    def test_the_card_is_mapped_and_counted_as_a_result_card(self):
        self.assertIn('case "opencodeToolActivity"', MESSAGE)
        self.assertIn("AiToolActivityCard {", MESSAGE)
        self.assertIn('"opencodeToolActivity"]', AI_QML.split("resultCardKinds:", 1)[1].split("\n", 1)[0])

    def test_the_activity_kind_is_not_an_approval_kind(self):
        approval = AI_QML.split("readonly property var approvalCardKinds:", 1)[1].split("\n", 1)[0]
        self.assertNotIn("opencodeToolActivity", approval)

    def test_the_two_modes_travel_in_the_request_body(self):
        self.assertIn('"auto": Config.options?.ai?.tools?.opencodeAuto === true', STRATEGY)
        self.assertIn('"configWrites": Config.options?.ai?.tools?.opencodeConfigWrites !== false', STRATEGY)


class Protected(unittest.TestCase):
    """The shell, not the model, decides which settings an unasked change may touch."""

    def test_the_guard_covers_the_assistants_own_permissions_and_what_the_shell_launches(self):
        self.assertIn("protectedSettingPrefix", AI_QML)
        prefix = AI_QML.split("readonly property var protectedSettingPrefix:", 1)[1].split("\n", 1)[0]
        for owned in ("ai", "policies", "apps"):
            self.assertIn(owned, prefix)
        words = AI_QML.split("readonly property var protectedSettingWords:", 1)[1].split("])", 1)[0]
        for word in ("command", "exec", "script", "url", "token", "password", "proxy", "ssh"):
            self.assertIn(f'"{word}"', words)

    def test_unasked_writes_go_through_the_guard(self):
        body = AI_QML.split("function opencodeSettingsSet", 1)[1].split("function parseJsonField", 1)[0]
        self.assertLess(body.index("protectedSettingReason"), body.index("settingsIntegration.apply"))

    def test_ipc_arguments_are_objects_because_qs_splits_a_leading_bracket(self):
        self.assertIn("function settingsSet(argsJson: string)", AI_QML)
        self.assertIn("function settingsGet(argsJson: string)", AI_QML)


if __name__ == "__main__":
    unittest.main()

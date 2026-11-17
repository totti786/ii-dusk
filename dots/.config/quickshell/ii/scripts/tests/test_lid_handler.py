import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SPEC = importlib.util.spec_from_file_location("lid_handler", os.path.join(HERE, "..", "lid", "lid_handler.py"))
lid = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(lid)

POLICY = {"on_ac": "blank", "on_battery": "suspend", "ignore_inhibitors": []}


def out(name, internal=False, headless=False, enabled=True):
    return {"name": name, "internal": internal, "headless": headless, "enabled": enabled}


PANEL = out("eDP-1", internal=True)
HDMI = out("HDMI-A-1")
PHONE = out("II-PHONE", headless=True)


def plan(lid_closed=True, ac=True, keep=False, inhibited=False, outputs=(PANEL,), policy=POLICY):
    return lid.decide(lid_closed, ac, keep, inhibited, list(outputs), policy)


class Decide(unittest.TestCase):
    def test_open_lid_does_nothing(self):
        self.assertEqual(plan(lid_closed=False)["action"], "none")
        self.assertTrue(plan(lid_closed=False)["wake_inputs"])

    def test_closed_on_ac_blanks(self):
        p = plan(ac=True)
        self.assertEqual(p["action"], "blank")
        self.assertFalse(p["wake_inputs"])

    def test_closed_on_battery_suspends(self):
        self.assertEqual(plan(ac=False)["action"], "suspend")

    def test_keep_awake_blocks_suspend_on_battery(self):
        self.assertEqual(plan(ac=False, keep=True)["action"], "blank")

    def test_other_apps_lid_inhibitor_blocks_suspend(self):
        self.assertEqual(plan(ac=False, inhibited=True)["action"], "blank")

    def test_docked_disables_panel_and_never_suspends(self):
        for ac in (True, False):
            self.assertEqual(plan(ac=ac, outputs=(PANEL, HDMI))["action"], "disable")

    def test_phone_monitor_is_not_docked(self):
        # The phone's headless output must not keep the laptop awake on battery.
        self.assertEqual(plan(ac=False, outputs=(PANEL, PHONE))["action"], "suspend")
        self.assertEqual(plan(ac=True, outputs=(PANEL, PHONE))["action"], "blank")

    def test_disabled_external_is_not_docked(self):
        self.assertEqual(plan(ac=False, outputs=(PANEL, out("HDMI-A-1", enabled=False)))["action"], "suspend")

    def test_policy_overrides(self):
        suspend_on_ac = dict(POLICY, on_ac="suspend")
        self.assertEqual(plan(ac=True, policy=suspend_on_ac)["action"], "suspend")
        stay_on_battery = dict(POLICY, on_battery="nothing")
        self.assertEqual(plan(ac=False, policy=stay_on_battery)["action"], "none")

    def test_desktop_without_panel(self):
        self.assertEqual(plan(ac=True, outputs=(HDMI,))["action"], "none")


class Classify(unittest.TestCase):
    def test_headless_has_no_identity(self):
        mons = [
            {"name": "eDP-1", "make": "AU Optronics", "model": "0xDA91", "description": "AU Optronics 0xDA91"},
            {"name": "II-PHONE", "make": "", "model": "", "description": ""},
            {"name": "HDMI-A-1", "make": "Dell", "model": "U2720Q", "description": "Dell U2720Q", "disabled": True},
        ]
        c = {o["name"]: o for o in lid.classify(mons)}
        self.assertTrue(c["eDP-1"]["internal"] and not c["eDP-1"]["headless"])
        self.assertTrue(c["II-PHONE"]["headless"] and not c["II-PHONE"]["internal"])
        self.assertFalse(c["HDMI-A-1"]["enabled"])

    def test_other_internal_connectors(self):
        for name in ("LVDS-1", "DSI-1"):
            self.assertTrue(lid.classify([{"name": name, "make": "x"}])[0]["internal"])

    def test_lua_string_is_escaped(self):
        self.assertEqual(lid.lua_str("a'b"), "'a\\'b'")


def fake_supply(root, name, **files):
    d = os.path.join(root, name)
    os.makedirs(d)
    for k, v in files.items():
        with open(os.path.join(d, k), "w") as f:
            f.write(v)


class Power(unittest.TestCase):
    def test_various_chargers(self):
        cases = [
            ({"ACAD": {"type": "Mains", "online": "1"}, "BAT1": {"type": "Battery"}}, True),
            ({"AC": {"type": "Mains", "online": "0"}, "BAT0": {"type": "Battery"}}, False),
            # USB-C laptops report the charger as type USB
            ({"ucsi": {"type": "USB", "online": "1"}, "BAT0": {"type": "Battery"}}, True),
            # a charging phone or mouse is not this machine's power
            ({"ucsi": {"type": "USB", "online": "1", "scope": "Device"}, "BAT0": {"type": "Battery"}}, False),
            # no battery at all: a desktop counts as plugged in
            ({"AC": {"type": "Mains", "online": "0"}}, True),
            ({}, True),
        ]
        for tree, expected in cases:
            with tempfile.TemporaryDirectory() as root:
                for name, files in tree.items():
                    fake_supply(root, name, **files)
                self.assertEqual(lid.on_ac_power(root), expected, tree)


class Policy(unittest.TestCase):
    def test_config_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
            json.dump({"on_ac": "suspend", "on_battery": "bogus", "ignore_inhibitors": ["foo"]}, f)
        try:
            p = lid.load_policy(f.name)
        finally:
            os.unlink(f.name)
        self.assertEqual(p["on_ac"], "suspend")
        self.assertEqual(p["on_battery"], "suspend")  # a bad value falls back to the default
        self.assertIn("foo", p["ignore_inhibitors"])
        self.assertIn("powerdevil", p["ignore_inhibitors"])

    def test_missing_file_gives_defaults(self):
        p = lid.load_policy("/nonexistent/ii-lid.json")
        self.assertEqual((p["on_ac"], p["on_battery"]), ("blank", "suspend"))


class Simulate(unittest.TestCase):
    def test_cli(self):
        r = subprocess.run([sys.executable, os.path.join(HERE, "..", "lid", "lid_handler.py"), "--simulate",
                            "lid=closed", "ac=0", "keep=0", "inhibited=0", "outputs=eDP-1,II-PHONE"],
                           capture_output=True, text=True, env=dict(os.environ, HOME="/nonexistent"))
        self.assertEqual(json.loads(r.stdout)["action"], "suspend")


if __name__ == "__main__":
    unittest.main()

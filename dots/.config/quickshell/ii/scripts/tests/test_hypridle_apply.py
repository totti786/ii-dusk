"""hypridle_apply.py: the generated hypridle.conf, and that applying twice changes nothing."""
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "idle" / "hypridle_apply.py"
sys.path.insert(0, str(SCRIPT.parent))
import hypridle_apply as h  # noqa: E402


def timeouts(text):
    return [int(line.split("=")[1]) for line in text.splitlines() if line.strip().startswith("timeout")]


class Build(unittest.TestCase):
    def test_defaults_are_what_the_machine_had(self):
        self.assertEqual(timeouts(h.build({})), [60, 300, 600, 602, 1200])

    def test_listeners_are_sorted_by_time(self):
        text = h.build({"dim": {"enable": True, "seconds": 120}, "suspend": {"seconds": 90}})
        self.assertEqual(timeouts(text), sorted(timeouts(text)))

    def test_disabled_step_is_absent_and_lock_before_sleep_stays(self):
        text = h.build({k: {"enable": False} for k in h.DEFAULTS})
        self.assertEqual(timeouts(text), [])
        self.assertIn("before_sleep_cmd", text)
        self.assertIn("loginctl lock-session", text)
        self.assertIn("quickshell:lockFingerStop", text)

    def test_seconds_are_clamped_and_junk_falls_back(self):
        text = h.build({"lock": {"seconds": 1}, "suspend": {"seconds": "abc"}, "screenOff": {"seconds": 10**9}})
        self.assertIn(10, timeouts(text))
        self.assertIn(1200, timeouts(text))
        self.assertIn(86400, timeouts(text))

    def test_suspend_checks_the_adapter_not_battery_text(self):
        on_battery = h.build({"suspend": {"onlyOnBattery": True}})
        self.assertIn("power_supply/*/online", on_battery)
        self.assertNotIn("Discharging", on_battery)
        always = h.build({"suspend": {"onlyOnBattery": False}})
        self.assertNotIn("power_supply", always)

    def test_dim_uses_the_shells_scrim(self):
        text = h.build({"dim": {"enable": True}})
        self.assertIn("idleDim dim", text)
        self.assertIn("idleDim restore", text)

    def test_nothing_user_supplied_reaches_the_file_as_text(self):
        text = h.build({"lock": {"seconds": 600, "enable": True, "x": "; rm -rf ~"}, "evil": {"enable": True}})
        self.assertNotIn("rm -rf", text)


class Apply(unittest.TestCase):
    def run_apply(self, conf, settings):
        env = dict(os.environ, II_HYPRIDLE_CONF=str(conf), II_HYPRIDLE_NO_RESTART="1")
        return subprocess.run([sys.executable, str(SCRIPT), json.dumps(settings)], env=env,
                              capture_output=True, text=True)

    def test_second_apply_is_unchanged_and_original_is_kept_once(self):
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "hypr" / "hypridle.conf"
            conf.parent.mkdir()
            conf.write_text("# my own file\n")
            first = self.run_apply(conf, {})
            self.assertEqual(first.returncode, 0, first.stderr)
            self.assertIn("applied", first.stdout)
            self.assertEqual((Path(str(conf) + ".before-settings")).read_text(), "# my own file\n")
            second = self.run_apply(conf, {})
            self.assertEqual(second.stdout.strip(), "unchanged")
            # a later change must not overwrite the kept original
            self.run_apply(conf, {"suspend": {"seconds": 900}})
            self.assertEqual((Path(str(conf) + ".before-settings")).read_text(), "# my own file\n")

    def test_bad_json_is_refused_without_touching_the_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            conf = Path(tmp) / "hypridle.conf"
            conf.write_text("keep\n")
            env = dict(os.environ, II_HYPRIDLE_CONF=str(conf), II_HYPRIDLE_NO_RESTART="1")
            bad = subprocess.run([sys.executable, str(SCRIPT), "{not json"], env=env, capture_output=True, text=True)
            self.assertEqual(bad.returncode, 2)
            self.assertEqual(conf.read_text(), "keep\n")


if __name__ == "__main__":
    unittest.main()

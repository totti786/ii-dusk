"""Alacritty is the default terminal and kitty the fallback."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

II_DIR = Path(__file__).resolve().parents[2]
REPO = II_DIR.parents[3]
SETUP = REPO / "setup-ii-dusk.sh"
LAUNCHER = REPO / "dots/.config/hypr/hyprland/scripts/terminal.sh"
BASE_PASSWD = "kitty -1 --hold=yes fish -i -c 'passwd'"


class Sandbox(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()

    def tool(self, name, body='echo "$(basename "$0") $*"'):
        path = self.bin / name
        path.write_text("#!/bin/bash\n" + body + "\n")
        path.chmod(0o755)


@unittest.skipUnless(LAUNCHER.is_file(), "needs the repository checkout")
class Launcher(Sandbox):
    def run_it(self, *args):
        self.tool("basename", 'echo "${1##*/}"')
        return subprocess.run(["/bin/bash", str(LAUNCHER), *args], capture_output=True, text=True,
                              env={"PATH": str(self.bin)})

    def test_alacritty_first_with_arguments_intact(self):
        self.tool("alacritty")
        self.tool("kitty")
        self.assertEqual(self.run_it("--class", "Alacritty-float").stdout, "alacritty --class Alacritty-float\n")

    def test_kitty_when_alacritty_is_missing(self):
        self.tool("kitty")
        self.assertEqual(self.run_it("-e", "yazi").stdout, "kitty -e yazi\n")

    def test_says_so_when_there_is_neither(self):
        self.assertEqual(self.run_it().returncode, 127)


@unittest.skipUnless(SETUP.is_file(), "needs the repository checkout")
class InstallStep(Sandbox):
    def setUp(self):
        super().setUp()
        self.home = self.root / "config"
        self.config = self.home / "illogical-impulse/config.json"
        self.config.parent.mkdir(parents=True)
        # Only what the step needs, so nothing installed here decides the result.
        for name in ("python3", "cat"):
            os.symlink(subprocess.check_output(["/bin/bash", "-c", "command -v " + name], text=True).strip(),
                       self.bin / name)

    def step(self):
        text = SETUP.read_text()
        start = text.index("set_default_terminal() {")
        # The Python inside has braces of its own at the margin.
        end = "\n    return 0\n}\n"
        function = text[start:text.index(end, start) + len(end)]
        script = (f'''set -eu
XDG_CONFIG_HOME="{self.home}"
BASE_CONFIG_FILE="{self.config}"
''' + '''have() { command -v "$1" >/dev/null 2>&1; }
tilde() { printf '%s' "$1"; }
ui_ok() { echo "ok $*"; }
ui_warn() { echo "warn $*"; }
CLI_NAME=ii-dusk G_ARROW='->' LOG_FILE=/dev/stderr
''' + function + 'set_default_terminal "$1"\n')
        env = {"PATH": str(self.bin), "XDG_CONFIG_HOME": str(self.home)}
        return subprocess.run(["/bin/bash", "-c", script, "bash", str(II_DIR)], capture_output=True,
                              text=True, env=env, check=True).stdout

    def apps(self):
        return json.loads(self.config.read_text())["apps"]

    def test_base_install_values_move_to_alacritty(self):
        self.tool("alacritty")
        self.config.write_text(json.dumps({"apps": {"terminal": "kitty -1", "changePassword": BASE_PASSWD}, "x": 1}))
        (self.home / "fuzzel").mkdir()
        (self.home / "fuzzel/fuzzel.ini").write_text("font=a\nterminal=kitty -1\n")
        (self.home / "kdeglobals").write_text("[General]\nTerminalApplication=kitty -1\n")
        self.step()
        self.assertEqual(self.apps(), {"terminal": "alacritty", "changePassword": "alacritty --hold -e passwd"})
        self.assertEqual(json.loads(self.config.read_text())["x"], 1)
        self.assertIn("terminal=alacritty -e\n", (self.home / "fuzzel/fuzzel.ini").read_text())
        self.assertIn("TerminalApplication=alacritty\n", (self.home / "kdeglobals").read_text())

    def test_a_chosen_terminal_stays(self):
        self.tool("alacritty")
        self.config.write_text(json.dumps({"apps": {"terminal": "foot"}}))
        before = self.config.read_text()
        self.step()
        self.assertEqual(self.config.read_text(), before)

    def test_fresh_install_with_alacritty_writes_nothing(self):
        self.tool("alacritty")
        self.step()
        self.assertFalse(self.config.exists())

    def test_fresh_install_falls_back_to_kitty(self):
        self.tool("kitty")
        self.step()
        self.assertEqual(self.apps()["terminal"], "kitty")
        self.assertIn("configVersion", json.loads(self.config.read_text()))

    def test_kitty_fallback_replaces_the_fork_default(self):
        self.tool("kitty")
        self.config.write_text(json.dumps({"apps": {"terminal": "alacritty"}}))
        self.step()
        self.assertEqual(self.apps()["terminal"], "kitty")

    def test_neither_installed(self):
        self.assertIn("warn", self.step())
        self.assertFalse(self.config.exists())


if __name__ == "__main__":
    unittest.main()

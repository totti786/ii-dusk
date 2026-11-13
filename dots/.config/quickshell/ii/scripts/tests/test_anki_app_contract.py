"""Contracts for the built-in Anki app's shell wiring.

These checks are deliberately static: they protect the app registration and the
bridge/QML command boundary without starting Quickshell or opening a collection.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class AnkiAppContractTests(unittest.TestCase):
    def read(self, relative: str) -> str:
        return (ROOT / relative).read_text()

    def test_global_state_and_shell_action_are_registered(self) -> None:
        states = self.read("GlobalStates.qml")
        self.assertIn("property bool ankiOpen", states)
        self.assertIn("property real ankiPendingDeck", states)
        self.assertIn("function openAnkiApp", states)

        service = self.read("services/AnkiService.qml")
        self.assertIn("property real currentDeckId", service)
        sidebar = self.read("modules/ii/anki/DeckSidebar.qml")
        self.assertIn("property real currentDeckId", sidebar)
        self.assertIn("signal deckSelected(var deckId)", sidebar)

        registry = self.read("modules/common/ShellActionRegistry.qml")
        self.assertIn('id: "anki"', registry)
        self.assertIn('"anki"', registry)
        self.assertIn("GlobalStates.openAnkiApp", registry)

    def test_both_panel_families_load_the_app(self) -> None:
        for family in (
            "panelFamilies/IllogicalImpulseFamily.qml",
            "panelFamilies/LiteFamily.qml",
        ):
            body = self.read(family)
            self.assertIn("import qs.modules.ii.anki", body)
            self.assertIn("../modules/ii/anki/AnkiApp.qml", body)

    def test_app_scope_has_shortcut_and_ipc(self) -> None:
        app = self.read("modules/ii/anki/AnkiApp.qml")
        self.assertIn('name: "ankiToggle"', app)
        self.assertIn('target: "anki"', app)
        self.assertIn("function toggle", app)

    def test_window_and_hyprland_rules_match(self) -> None:
        window = self.read("modules/ii/anki/AnkiWindow.qml")
        self.assertIn('title: "ii Anki"', window)
        rules = (Path.home() / ".config/hypr/hyprland/rules.lua").read_text()
        self.assertIn('title = "^(ii Anki)$"', rules)

    def test_keybind_exists(self) -> None:
        keybinds = (Path.home() / ".config/hypr/hyprland/keybinds.lua").read_text()
        self.assertIn("quickshell:ankiToggle", keybinds)
        self.assertIn("SUPER + CTRL + Q", keybinds)
        self.assertIn('description = "Anki: Review flashcards"', keybinds)

    def test_config_and_dependency_entry_exist(self) -> None:
        config = self.read("modules/common/Config.qml")
        self.assertIn("property JsonObject anki", config)
        self.assertIn("property bool autoPlayAudio", config)
        deps = self.read("defaults/dependencies.json")
        self.assertIn('"id": "anki"', deps)
        self.assertIn('"bin": "anki"', deps)

    def test_qml_commands_exist_in_the_backend(self) -> None:
        service = self.read("services/AnkiService.qml")
        backend = self.read("scripts/anki/anki_backend.py")
        daemon = self.read("scripts/anki/anki_daemon.py")
        commands = set(re.findall(r'call\("([A-Za-z]+)"', service))
        for command in ("open", "card", "reveal", "answer", "undo", "close",
                        "login", "logout", "sync", "fullSync", "addNote", "createDeck", "importApkg", "noteTypes"):
            self.assertIn(command, commands)
        passthrough = re.search(r"PASSTHROUGH = \{(.*?)\}", backend, re.S).group(1)
        for command in commands:
            # Either the backend shapes it itself, or it goes straight to the daemon.
            in_backend = f"def cmd_{command}" in backend
            forwarded = f'"{command}"' in passthrough and f"def cmd_{command}" in daemon
            self.assertTrue(in_backend or forwarded, command)

    def test_backend_uses_anki_and_closes_on_eof(self) -> None:
        backend = self.read("scripts/anki/anki_backend.py")
        self.assertIn("for line in sys.stdin", backend)
        self.assertIn("def cmd_close", backend)
        self.assertIn("signal.signal(signal.SIGTERM", backend)

    def test_engine_is_a_private_pinned_venv(self) -> None:
        backend = self.read("scripts/anki/anki_backend.py")
        installer = self.read("scripts/anki/install_engine.sh")
        service = self.read("services/AnkiService.qml")
        # The backend runs on the engine venv and never falls back to the system package.
        self.assertIn("ii-anki-engine", backend)
        self.assertIn('"anki_missing"', backend)
        self.assertNotIn("import anki.collection", backend)
        # Pinned (never "latest": a newer engine can upgrade the collection past desktop).
        self.assertRegex(installer, r'ANKI_VERSION="\$\{II_ANKI_VERSION:-\d+\.\d+\.\d+\}"')
        self.assertIn('"anki==$ANKI_VERSION"', installer)
        self.assertNotIn("--upgrade", installer)
        # Its own folder, apart from upstream's ii-anki one that install.sh may upgrade.
        self.assertNotIn("/ii-anki/", installer)
        self.assertIn("install_engine.sh", service)
        self.assertIn("function installEngine", service)

    def test_backend_leaves_the_upstream_daemon_untouched(self) -> None:
        # The daemon is upstream's file; the app's behaviour lives in the backend wrapper.
        backend = self.read("scripts/anki/anki_backend.py")
        self.assertIn("import anki_daemon as up", backend)
        self.assertIn("up.COLLECTION =", backend)

    def test_answer_only_prefers_anki_answer_rule(self) -> None:
        pane = self.read("modules/ii/anki/ReviewPane.qml")
        self.assertIn("answerOnlyHtml", pane)
        self.assertIn("<hr", pane)
        daemon = self.read("scripts/anki/anki_daemon.py")
        self.assertIn("RE_ANSWER_HR", daemon)


if __name__ == "__main__":
    unittest.main()

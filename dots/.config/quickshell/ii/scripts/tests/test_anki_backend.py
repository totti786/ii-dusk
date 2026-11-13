"""Tests for the Anki backend (scripts/anki/anki_backend.py).

The backend replaced anki_bridge.py, so it must keep every behaviour the bridge's tests
pin down: those run again here against the backend. On top come the things it adds:
finding the user's default Anki profile, creating decks and notes, importing packages and
the error codes. Every test builds temporary collections; the real profile is never opened.
"""

from __future__ import annotations

import os
import pickle
import sqlite3
import tempfile
import unittest
from pathlib import Path

import test_anki_bridge as bridge_tests
from test_anki_bridge import make_fixture

ROOT = Path(__file__).resolve().parents[2]
BACKEND = ROOT / "scripts" / "anki" / "anki_backend.py"


class BridgeBehaviourOnTheBackend(bridge_tests.AnkiBridgeTests):
    """The old bridge's suite, pointed at the backend."""

    def setUp(self) -> None:
        self._bridge = bridge_tests.BRIDGE
        bridge_tests.BRIDGE = BACKEND
        super().setUp()

    def tearDown(self) -> None:
        super().tearDown()
        bridge_tests.BRIDGE = self._bridge


def make_prefs(base: Path, last: str, names: list[str], global_blob: bytes | None = None) -> None:
    """The prefs21.db Anki desktop keeps: one pickled dict per profile plus `_global`.

    The blobs are written here by the test itself; nothing untrusted is ever loaded.
    """
    con = sqlite3.connect(base / "prefs21.db")
    con.execute("create table profiles (name text primary key collate nocase, data blob not null)")
    blob = global_blob if global_blob is not None else pickle.dumps({"last_loaded_profile_name": last})
    con.execute("insert into profiles values ('_global', ?)", (blob,))
    for name in names:
        con.execute("insert into profiles values (?, ?)", (name, pickle.dumps({})))
    con.commit()
    con.close()


class BackendTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="anki-backend-")
        self.root = Path(self.tmp.name)
        self.client: bridge_tests.BridgeClient | None = None
        self._saved_env = {k: os.environ.get(k) for k in ("XDG_DATA_HOME", "HOME", "II_ANKI_COLLECTION", "II_ANKI_ENGINE")}
        self._saved_bridge = bridge_tests.BRIDGE
        bridge_tests.BRIDGE = BACKEND

    def tearDown(self) -> None:
        if self.client is not None:
            self.client.close()
        bridge_tests.BRIDGE = self._saved_bridge
        for key, value in self._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value
        self.tmp.cleanup()

    def start(self, **env: str) -> bridge_tests.BridgeClient:
        for key, value in env.items():
            os.environ[key] = value
        self.client = bridge_tests.BridgeClient()
        return self.client

    def fake_anki_home(self, last: str, names: list[str], global_blob: bytes | None = None) -> Path:
        data = self.root / "data"
        base = data / "Anki2"
        base.mkdir(parents=True)
        for name in names:
            (base / name).mkdir()
            make_fixture(base / name)
        make_prefs(base, last, names, global_blob)
        return data

    # ------------------------------------------------------------ finding the profile

    def test_opens_the_last_used_profile_of_the_default_anki_folder(self) -> None:
        data = self.fake_anki_home("Second", ["First", "Second"])
        client = self.start(XDG_DATA_HOME=str(data))
        session = client.request("open")["data"]
        self.assertEqual(session["profile"], "Second")
        self.assertTrue(session["collectionPath"].endswith("Anki2/Second/collection.anki2"))
        self.assertEqual(sorted(client.request("profiles")["data"]["profiles"]), ["First", "Second"])

    def test_an_explicit_profile_beats_the_last_used_one(self) -> None:
        data = self.fake_anki_home("Second", ["First", "Second"])
        client = self.start(XDG_DATA_HOME=str(data))
        self.assertEqual(client.request("open", profile="First")["data"]["profile"], "First")

    def test_a_tampered_prefs_database_cannot_run_code_and_falls_back(self) -> None:
        marker = self.root / "tampered"

        class Evil:
            def __reduce__(self):
                return (os.system, (f"touch {marker}",))

        data = self.fake_anki_home("", ["Alpha", "Beta"], global_blob=pickle.dumps(Evil()))
        client = self.start(XDG_DATA_HOME=str(data))
        session = client.request("open")["data"]
        self.assertFalse(marker.exists())
        self.assertIn(session["profile"], ("Alpha", "Beta"))

    def test_profiles_are_found_without_a_prefs_database(self) -> None:
        data = self.root / "data"
        (data / "Anki2" / "Only").mkdir(parents=True)
        make_fixture(data / "Anki2" / "Only")
        client = self.start(XDG_DATA_HOME=str(data))
        self.assertEqual(client.request("open")["data"]["profile"], "Only")

    def test_flatpak_install_is_found_when_the_native_folder_is_absent(self) -> None:
        home = self.root / "home"
        base = home / ".var" / "app" / "net.ankiweb.Anki" / "data" / "Anki2"
        (base / "Flat").mkdir(parents=True)
        make_fixture(base / "Flat")
        make_prefs(base, "Flat", ["Flat"])
        client = self.start(HOME=str(home), XDG_DATA_HOME=str(home / "nothing-here"))
        session = client.request("open")["data"]
        self.assertEqual(session["profile"], "Flat")
        self.assertIn("net.ankiweb.Anki", session["collectionPath"])

    def test_no_anki_data_folder_is_reported(self) -> None:
        home = self.root / "empty-home"
        home.mkdir()
        client = self.start(HOME=str(home), XDG_DATA_HOME=str(home / "x"))
        response = client.request("open")
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "no_profiles")

    def test_without_the_engine_the_backend_says_so_and_does_not_fall_back(self) -> None:
        # No private engine: it must not quietly use whatever `anki` the system has.
        data = self.fake_anki_home("Only", ["Only"])
        client = self.start(XDG_DATA_HOME=str(data), II_ANKI_ENGINE=str(self.root / "no-engine"))
        response = client.request("open")
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "anki_missing")
        self.assertIn("install_engine.sh", response["error"]["detail"]["installer"])

    # ----------------------------------------------------- notes, decks and packages

    def open_fixture(self) -> tuple[bridge_tests.BridgeClient, int]:
        folder = self.root / "fx"
        folder.mkdir()
        collection, deck_id = make_fixture(folder)
        client = self.start()
        client.request("open", collectionPath=str(collection))
        return client, deck_id

    def test_add_note_create_deck_and_study_it(self) -> None:
        client, _deck = self.open_fixture()
        types = client.request("noteTypes")["data"]
        basic = next(t for t in types if t["name"] == "Basic")
        self.assertEqual(basic["fields"], ["Front", "Back"])

        deck = client.request("createDeck", name="Words::German")["data"]["id"]
        added = client.request("addNote", deckId=deck, noteTypeId=basic["id"], fields=["Brot", "bread"], tags="food")
        self.assertTrue(added["ok"], added)

        card = client.request("selectDeck", deckId=deck)["data"]["card"]
        self.assertEqual(card["kind"], "new")
        self.assertIn("Brot", card["questionHtml"])
        names = [c["name"] for c in client.request("decks")["data"]["decks"]["children"]]
        self.assertIn("Words", names)

    def test_user_mistakes_get_their_own_error_codes(self) -> None:
        client, deck = self.open_fixture()
        basic = next(t for t in client.request("noteTypes")["data"] if t["name"] == "Basic")
        empty = client.request("addNote", deckId=deck, noteTypeId=basic["id"], fields=["", ""])
        self.assertEqual(empty["error"]["code"], "note_check_1")
        self.assertIn("empty", empty["error"]["message"])
        self.assertEqual(client.request("createDeck", name="  ")["error"]["code"], "empty_name")
        self.assertEqual(client.request("sync")["error"]["code"], "not_logged_in")
        self.assertEqual(client.request("play", path="/etc/passwd")["error"]["code"], "outside_media")

    def test_import_package_round_trip(self) -> None:
        from anki.collection import Collection, DeckIdLimit, ExportAnkiPackageOptions

        source_dir = self.root / "source"
        source_dir.mkdir()
        source, deck_id = make_fixture(source_dir)
        package = self.root / "fixture.apkg"
        col = Collection(str(source))
        col.export_anki_package(
            out_path=str(package),
            options=ExportAnkiPackageOptions(
                with_scheduling=False, with_deck_configs=False, with_media=False, legacy=False
            ),
            limit=DeckIdLimit(deck_id),
        )
        col.close()

        empty_dir = self.root / "empty"
        empty_dir.mkdir()
        empty = empty_dir / "collection.anki2"
        Collection(str(empty)).close()
        client = self.start()
        self.assertEqual(client.request("open", collectionPath=str(empty))["data"]["cards"], 0)
        result = client.request("importApkg", path=str(package))["data"]
        self.assertEqual(result["new"], 1)
        again = client.request("importApkg", path="file://" + str(package))["data"]
        self.assertEqual((again["new"], again["duplicate"]), (0, 1))
        self.assertEqual(client.request("decks")["data"]["cards"], 1)

    def test_suspending_a_whole_note_and_undoing_it(self) -> None:
        client, deck = self.open_fixture()
        first = client.request("selectDeck", deckId=deck)["data"]["card"]["cardId"]
        gone = client.request("cardAction", action="suspendNote")["data"]
        self.assertTrue(gone["done"])
        back = client.request("undo")["data"]
        self.assertEqual(back["card"]["cardId"], first)

    def test_stock_type_in_answer_note_shows_exactly_one_comparison(self) -> None:
        # Anki's own note type has the type box on the answer side too, where the daemon
        # already fills it in: the backend must not add a second comparison.
        client, _deck = self.open_fixture()
        stock = next(t for t in client.request("noteTypes")["data"] if t["name"] == "Basic (type in the answer)")
        deck = client.request("createDeck", name="TypeTest")["data"]["id"]
        self.assertTrue(client.request("addNote", deckId=deck, noteTypeId=stock["id"], fields=["Pferd", "horse"])["ok"])
        card = client.request("selectDeck", deckId=deck)["data"]["card"]
        self.assertEqual(card["typeAnswer"], {"field": "Back"})
        self.assertNotIn("horse", card["questionHtml"])

        right = client.request("reveal", typed="horse")["data"]
        self.assertTrue(right["typedResult"]["correct"])
        self.assertEqual(right["answerHtml"].count("typeans"), 1)
        self.assertNotIn("color:#c62828", right["answerHtml"])

        wrong = client.request("reveal", typed="hors")["data"]
        self.assertFalse(wrong["typedResult"]["correct"])
        self.assertEqual(wrong["answerHtml"].count("typeans"), 1)
        self.assertIn("color:#c62828", wrong["answerHtml"])

    def test_theme_is_accepted(self) -> None:
        client, _deck = self.open_fixture()
        self.assertTrue(client.request("theme", color="#ffffff", fontPx=24, maxWidth=640, dark=True)["data"])


if __name__ == "__main__":
    unittest.main()

"""Integration tests for the Anki JSON bridge.

Every test builds a temporary collection; the real Anki profile is never opened.
"""

from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
BRIDGE = ROOT / "scripts" / "anki" / "anki_bridge.py"


def make_fixture(
    root: Path,
    *,
    type_answer: bool = False,
    front: str = "front",
    back: str = "back",
    with_media: bool = False,
) -> tuple[Path, int]:
    from anki.collection import Collection

    collection_path = root / "collection.anki2"
    col = Collection(str(collection_path))
    model = col.models.new("Anki Shell Test")
    col.models.add_field(model, col.models.new_field("Front"))
    col.models.add_field(model, col.models.new_field("Back"))
    template = col.models.new_template("Card 1")
    template["qfmt"] = "{{Front}}" + ("<br>{{type:Back}}" if type_answer else "")
    template["afmt"] = "{{FrontSide}}<hr id=answer>{{Back}}"
    col.models.add_template(model, template)
    col.models.add(model)
    deck = col.decks.add_normal_deck_with_name("Fixture")
    note = col.new_note(model)
    note["Front"] = front
    note["Back"] = back
    col.add_note(note, deck.id)
    col.close()

    media = root / "collection.media"
    media.mkdir(exist_ok=True)
    if with_media:
        Image.new("RGB", (40, 20), "red").save(media / "test.jpg")
        (media / "test.mp3").write_bytes(b"ID3")
    return collection_path, int(deck.id)


class BridgeClient:
    def __init__(self) -> None:
        self.proc = subprocess.Popen(
            [sys.executable, "-I", str(BRIDGE)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.next_id = 0

    def request(self, cmd: str, **args) -> dict:
        self.next_id += 1
        request_id = str(self.next_id)
        assert self.proc.stdin is not None
        self.proc.stdin.write(
            json.dumps({"id": request_id, "cmd": cmd, "args": args}, ensure_ascii=False) + "\n"
        )
        self.proc.stdin.flush()
        assert self.proc.stdout is not None
        line = self.proc.stdout.readline()
        if not line:
            stderr = self.proc.stderr.read() if self.proc.stderr else ""
            raise AssertionError(f"bridge exited early: {stderr}")
        response = json.loads(line)
        assert response["id"] == request_id, response
        return response

    def close(self) -> None:
        if self.proc.poll() is None:
            try:
                self.request("close")
            except Exception:
                self.proc.terminate()
        self.proc.wait(timeout=5)
        for stream in (self.proc.stdin, self.proc.stdout, self.proc.stderr):
            if stream is not None:
                stream.close()


class AnkiBridgeTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory(prefix="anki-bridge-")
        self.root = Path(self.tmp.name)
        self.client: BridgeClient | None = None

    def tearDown(self) -> None:
        if self.client is not None:
            self.client.close()
        self.tmp.cleanup()

    def open(self, collection: Path, profile: str = "Fixture") -> dict:
        self.client = BridgeClient()
        response = self.client.request(
            "open", collectionPath=str(collection), profile=profile
        )
        self.assertTrue(response["ok"], response)
        return response["data"]

    def test_open_card_reveal_answer_and_undo(self) -> None:
        collection, deck_id = make_fixture(self.root)
        session = self.open(collection)
        self.assertEqual(session["profile"], "Fixture")
        self.assertTrue(session["decks"]["children"])

        card = self.client.request("selectDeck", deckId=deck_id)["data"]
        self.assertFalse(card["done"])
        self.assertEqual(card["card"]["kind"], "new")
        self.assertIn("front", card["card"]["questionHtml"])

        answer = self.client.request("reveal", typed="")["data"]
        self.assertIn("back", answer["answerHtml"])
        self.assertEqual([b["rating"] for b in answer["buttons"]], [0, 1, 2, 3])
        self.assertTrue(all(b["interval"] for b in answer["buttons"]))

        next_card = self.client.request("answer", rating=2)["data"]
        self.assertFalse(next_card["done"])

        undone = self.client.request("undo")["data"]
        self.assertFalse(undone["done"])
        self.assertIn("front", undone["card"]["questionHtml"])

    def test_mark_flag_and_bury_act_on_the_card_on_screen(self) -> None:
        collection, deck_id = make_fixture(self.root)
        self.open(collection)
        card = self.client.request("selectDeck", deckId=deck_id)["data"]["card"]
        self.assertFalse(card["marked"])
        self.assertEqual(card["flag"], 0)

        marked = self.client.request("cardAction", action="mark")["data"]
        self.assertTrue(marked["marked"])
        self.assertFalse(self.client.request("cardAction", action="mark")["data"]["marked"])

        self.assertEqual(self.client.request("cardAction", action="flag", flag=1)["data"]["flag"], 1)
        self.assertEqual(self.client.request("cardAction", action="flag", flag=1)["data"]["flag"], 0)

        # The card is still the one on screen and can still be answered.
        self.assertTrue(self.client.request("reveal", typed="")["ok"])

        buried = self.client.request("cardAction", action="bury")["data"]
        self.assertTrue(buried["done"])
        undone = self.client.request("undo")["data"]
        self.assertFalse(undone["done"])

        suspended = self.client.request("cardAction", action="suspend")["data"]
        self.assertTrue(suspended["done"])

        bad = self.client.request("cardAction", action="explode")
        self.assertFalse(bad["ok"])

    def test_typed_answer_uses_anki_comparison_without_leaking_expected(self) -> None:
        collection, deck_id = make_fixture(self.root, type_answer=True, back="tragen")
        self.open(collection)
        card = self.client.request("selectDeck", deckId=deck_id)["data"]["card"]
        self.assertEqual(card["typeAnswer"]["field"], "Back")
        self.assertNotIn("expected", card["typeAnswer"])

        correct = self.client.request("reveal", typed="tragen")["data"]["typedResult"]
        self.assertTrue(correct["correct"])
        self.assertIn("color:#2e7d32", correct["html"])
        self.assertNotIn("color:#c62828", correct["html"])

        wrong = self.client.request("reveal", typed="tragn")["data"]["typedResult"]
        self.assertFalse(wrong["correct"])
        self.assertIn("color:#c62828", wrong["html"])

    def test_sanitizes_scripts_images_audio_and_unsafe_links(self) -> None:
        collection, deck_id = make_fixture(
            self.root,
            front='<script>alert(1)</script><img src="test.jpg"><br>[sound:test.mp3]<br><a href="javascript:alert(2)">bad</a>',
            with_media=True,
        )
        self.open(collection)
        card = self.client.request("selectDeck", deckId=deck_id)["data"]["card"]
        html = card["questionHtml"]
        self.assertNotIn("<script", html)
        self.assertNotIn("javascript:", html)
        self.assertIn("test.jpg", html)
        self.assertTrue(card["scripted"])
        self.assertEqual(len(card["audio"]), 1)
        self.assertFalse(card["audio"][0]["missing"])
        self.assertEqual(len(card["images"]), 1)
        self.assertFalse(card["hasMissingMedia"])
        self.assertTrue(card["images"][0]["url"].startswith("file://"))

    def test_missing_media_is_marked_not_fatal(self) -> None:
        collection, deck_id = make_fixture(
            self.root,
            front='<img src="missing.jpg">[sound:missing.mp3]',
        )
        self.open(collection)
        card = self.client.request("selectDeck", deckId=deck_id)["data"]["card"]
        self.assertTrue(card["hasMissingMedia"])
        self.assertIn("missing image", card["questionHtml"])
        self.assertTrue(card["audio"][0]["missing"])

    def test_locked_collection_is_reported(self) -> None:
        from anki.collection import Collection

        collection, _deck_id = make_fixture(self.root)
        holder = Collection(str(collection))
        try:
            client = BridgeClient()
            try:
                response = client.request(
                    "open", collectionPath=str(collection), profile="Fixture"
                )
            finally:
                client.close()
        finally:
            holder.close()
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "collection_locked")

    def test_close_releases_the_collection(self) -> None:
        from anki.collection import Collection

        collection, _deck_id = make_fixture(self.root)
        self.open(collection)
        self.client.request("close")
        self.client.close()
        self.client = None
        reopened = Collection(str(collection))
        reopened.close()

    def test_unknown_command_is_a_protocol_error(self) -> None:
        collection, _deck_id = make_fixture(self.root)
        self.open(collection)
        response = self.client.request("notACommand")
        self.assertFalse(response["ok"])
        self.assertEqual(response["error"]["code"], "bad_request")


if __name__ == "__main__":
    unittest.main()

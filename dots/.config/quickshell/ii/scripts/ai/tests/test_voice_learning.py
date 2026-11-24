import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import voice_agent as va  # noqa: E402


class LearnFrom(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        self.addCleanup(self.dir.cleanup)
        self.file = str(Path(self.dir.name) / "voice-learning.json")
        self.events = []
        patches = [
            mock.patch.object(va, "LEARN_FILE", self.file),
            mock.patch.object(va, "emit", self.events.append),
            mock.patch.dict(va.LEARN, {"on": True}),
            mock.patch.object(va, "RULES_CUSTOM", []),
            mock.patch.object(va, "RULES_LEARNED", []),
        ]
        for patch in patches:
            patch.start()
            self.addCleanup(patch.stop)

    def learned(self):
        return [event["rule"] for event in self.events if event["event"] == "learned"]

    def test_the_second_identical_result_is_learned(self):
        va.learn_from("movie mode please", [["theme", ["dark"]], ["brightness", ["set", "30"]]])
        self.assertEqual(self.learned(), [])
        va.learn_from("movie mode please", [["theme", ["dark"]], ["brightness", ["set", "30"]]])
        rules = self.learned()
        self.assertEqual(len(rules), 1)
        self.assertEqual((rules[0]["phrase"], rules[0]["do"]), ("movie mode", "theme dark; brightness set 30"))

    def test_the_count_survives_a_restart(self):
        va.learn_from("movie mode", [["theme", ["dark"]]])
        self.assertTrue(Path(self.file).exists())
        self.assertEqual(json.loads(Path(self.file).read_text())["movie mode"]["seen"], 1)
        va.learn_from("movie mode", [["theme", ["dark"]]])
        self.assertEqual(len(self.learned()), 1)

    def test_nothing_is_learned_when_switched_off(self):
        with mock.patch.dict(va.LEARN, {"on": False}):
            for _ in range(3):
                va.learn_from("movie mode", [["theme", ["dark"]]])
        self.assertEqual(self.learned(), [])
        self.assertFalse(Path(self.file).exists())

    def test_a_sentence_a_rule_already_covers_is_not_learned(self):
        for _ in range(3):
            va.learn_from("pause the music", [["media", ["pause"]]])
        self.assertEqual(self.learned(), [])

    def test_a_phrase_already_learned_is_not_learned_twice(self):
        with mock.patch.object(va, "RULES_LEARNED", [{"phrase": "movie mode", "do": "theme dark", "say": ""}]):
            for _ in range(3):
                va.learn_from("movie mode", [["theme", ["dark"]]])
        self.assertEqual(self.learned(), [])

    def test_malformed_actions_are_ignored(self):
        va.learn_from("movie mode", [["theme"], "oops", None, ["theme", "dark"]])
        va.learn_from("movie mode", [])
        self.assertEqual(self.learned(), [])

    def test_a_damaged_state_file_does_not_break_learning(self):
        Path(self.file).write_text("{not json")
        va.learn_from("movie mode", [["theme", ["dark"]]])
        va.learn_from("movie mode", [["theme", ["dark"]]])
        self.assertEqual(len(self.learned()), 1)


if __name__ == "__main__":
    unittest.main()

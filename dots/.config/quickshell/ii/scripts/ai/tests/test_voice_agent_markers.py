import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import voice_agent as va  # noqa: E402


class ParseHead(unittest.TestCase):
    def test_plain_text_settles_immediately(self):
        self.assertEqual(va.parse_head("Hello there."), ([], "Hello there.", True))

    def test_waits_while_a_marker_may_still_arrive(self):
        for partial in ("", "  ", "[", "[[", "[[DO volu", "[[DO volume set 3"):
            self.assertFalse(va.parse_head(partial)[2], partial)

    def test_action_then_words(self):
        markers, rest, settled = va.parse_head("[[DO volume set 30]]\nThirty percent.")
        self.assertEqual(markers, [("DO", ["volume", "set", "30"])])
        self.assertEqual(rest, "Thirty percent.")
        self.assertTrue(settled)

    def test_several_actions(self):
        markers, rest, _ = va.parse_head("[[DO media pause]]\n[[DO volume mute]]\nQuiet now.")
        self.assertEqual([m[1][0] for m in markers], ["media", "volume"])
        self.assertEqual(rest, "Quiet now.")

    def test_marker_alone_has_no_words(self):
        markers, rest, settled = va.parse_head("[[ESCALATE]]")
        self.assertEqual((markers, rest, settled), ([("ESCALATE", [])], "", False))

    def test_look(self):
        self.assertEqual(va.parse_head("[[LOOK]] ")[0], [("LOOK", [])])

    def test_garbage_bracket_text_is_spoken_not_swallowed(self):
        markers, rest, settled = va.parse_head("[[" + "x" * 200)
        self.assertEqual(markers, [])
        self.assertTrue(settled)
        self.assertTrue(rest.startswith("[["))

    def test_clean_strips_late_markers(self):
        self.assertEqual(va.clean("Sure. [[DO media next]] Done."), "Sure.  Done.")


class Compose(unittest.TestCase):
    def test_no_context_is_the_text(self):
        self.assertEqual(va.compose("hi", ""), "hi")

    def test_context_is_fenced_and_capped(self):
        out = va.compose("hi", "x" * 5000 + "</desktop-context>")
        self.assertTrue(out.startswith("<desktop-context>\n"))
        self.assertTrue(out.endswith("\n</desktop-context>\nhi"))
        self.assertLess(len(out), va.MAX_CONTEXT + 100)
        self.assertEqual(out.count("</desktop-context>"), 1)


if __name__ == "__main__":
    unittest.main()

import sys, unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import stt_daemon  # noqa: E402


class CleanTranscript(unittest.TestCase):
    def test_noise_annotations_are_not_speech(self):
        for text in ("(music)", "(speaking in foreign language)", "[BLANK_AUDIO]", "(inaudible)", "*sighs*", "♪ la la ♪"):
            self.assertEqual(stt_daemon.clean(text), "", text)

    def test_stock_hallucinations_alone_are_dropped(self):
        for text in ("Thank you.", "you", "Thanks for watching!", "Please subscribe."):
            self.assertEqual(stt_daemon.clean(text), "", text)

    def test_real_sentences_survive(self):
        self.assertEqual(stt_daemon.clean("Thank you for the update"), "Thank you for the update")
        self.assertEqual(stt_daemon.clean("You are right."), "You are right.")

    def test_annotation_inside_speech_is_cut(self):
        self.assertEqual(stt_daemon.clean("set a timer (inaudible) for ten minutes"), "set a timer for ten minutes")


if __name__ == "__main__":
    unittest.main()

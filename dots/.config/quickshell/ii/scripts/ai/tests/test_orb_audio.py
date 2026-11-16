"""Speech activity boundaries and local transcription isolation."""
import array
import importlib.util
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("orb_audio", Path(__file__).resolve().parents[1] / "orb_audio.py")
audio = importlib.util.module_from_spec(spec)
spec.loader.exec_module(audio)


class Audio(unittest.TestCase):
    def test_silence_never_becomes_a_voice_command(self):
        detector = audio.PauseDetector()
        results = [detector.feed(0) for _ in range(81)]
        self.assertEqual(results[-1], "no-speech")
        self.assertEqual(detector.speech, 0)

    def test_speech_ends_after_a_pause(self):
        detector = audio.PauseDetector()
        self.assertTrue(all(not detector.feed(.08) for _ in range(10)))
        self.assertTrue(all(not detector.feed(.001) for _ in range(9)))
        results = [detector.feed(.001) for _ in range(2)]
        self.assertIn("pause", results)

    def test_long_utterance_ends_with_less_than_a_second_of_silence(self):
        detector = audio.PauseDetector()
        for _ in range(20): detector.feed(.08)
        self.assertTrue(all(not detector.feed(.001) for _ in range(7)))
        self.assertEqual(detector.feed(.001), "pause")

    def test_a_mid_sentence_pause_does_not_cut_off_speech(self):
        detector = audio.PauseDetector()
        for _ in range(10): detector.feed(.08)
        self.assertTrue(all(not detector.feed(.001) for _ in range(6)))
        self.assertEqual(detector.feed(.08), "")
        self.assertEqual(detector.quiet, 0)

    def test_short_noise_does_not_send_a_command(self):
        detector = audio.PauseDetector()
        detector.feed(.1)
        result = ""
        for _ in range(81): result = detector.feed(.002)
        self.assertEqual(result, "no-speech")

    def test_a_continuous_sound_is_bounded(self):
        detector = audio.PauseDetector()
        result = ""
        for _ in range(601): result = detector.feed(.1)
        self.assertEqual(result, "limit")

    def test_pcm_level_matches_known_samples(self):
        self.assertEqual(audio.rms(bytes(3200)), 0)
        self.assertAlmostEqual(audio.rms(array.array("h", [16384] * 1600).tobytes()), .5)

    def test_transcription_uses_local_model_without_user_hooks(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(audio.subprocess, "run") as run:
            run.return_value.returncode = 0
            run.return_value.stdout = 'Loading audio file: "sample.wav"\nProcessing...\n\nHello companion.\n'
            output = str(Path(directory) / "text.txt")
            audio.transcribe("sample.wav", output)
            self.assertEqual(Path(output).read_text(), "Hello companion.")
            args = run.call_args.args[0]
            self.assertEqual(args[args.index("--config") + 1], "/dev/null")
            self.assertIn("whisper", args)
            self.assertIn("auto", args)

    def test_transcription_failure_does_not_create_a_transcript(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(audio.subprocess, "run") as run:
            run.return_value.returncode = 1
            run.return_value.stderr = "no model"
            output = str(Path(directory) / "text.txt")
            with self.assertRaises(RuntimeError): audio.transcribe("sample.wav", output)
            self.assertFalse(Path(output).exists())


if __name__ == "__main__": unittest.main()

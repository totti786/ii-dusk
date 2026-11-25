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
        for _ in range(10): detector.feed(.002)  # the room, while the floor is learned
        self.assertTrue(all(not detector.feed(.08) for _ in range(10)))
        self.assertTrue(all(not detector.feed(.001) for _ in range(9)))
        results = [detector.feed(.001) for _ in range(2)]
        self.assertIn("pause", results)

    def test_long_utterance_ends_with_less_than_a_second_of_silence(self):
        detector = audio.PauseDetector()
        for _ in range(10): detector.feed(.002)
        for _ in range(20): detector.feed(.08)
        self.assertTrue(all(not detector.feed(.001) for _ in range(7)))
        self.assertEqual(detector.feed(.001), "pause")

    def test_a_mid_sentence_pause_does_not_cut_off_speech(self):
        detector = audio.PauseDetector()
        for _ in range(10): detector.feed(.08)
        self.assertTrue(all(not detector.feed(.001) for _ in range(6)))
        self.assertEqual(detector.feed(.08), "")
        self.assertEqual(detector.quiet, 0)

    def test_push_to_talk_keeps_listening_through_long_pauses(self):
        for vad in (None, type("SilentVAD", (), {"feed": lambda self, pcm: [0.0]})()):
            with self.subTest(vad=vad):
                detector = audio.PauseDetector(vad, push_to_talk=True)
                self.assertTrue(all(detector.feed(.04, pcm=b"fixture") == "" for _ in range(85)))
                self.assertTrue(all(detector.feed(0, pcm=b"fixture") == "" for _ in range(100)))

    def test_push_to_talk_detects_short_speech_and_keeps_the_recording_limit(self):
        detector = audio.PauseDetector(push_to_talk=True)
        for _ in range(4):
            self.assertEqual(detector.feed(.04), "")
        self.assertGreaterEqual(detector.speech, .2)
        self.assertIn("limit", (detector.feed(0) for _ in range(601)))

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


class Speculation(unittest.TestCase):
    RULE = {"actions": [("volume", ["set", "30"])], "say": "Volume 30."}

    def test_complete_command_after_a_real_pause_ends_the_turn(self):
        self.assertEqual(audio.speculation_verdict(True, "volume 30", .6, self.RULE), "end")

    def test_a_short_pause_waits(self):
        self.assertEqual(audio.speculation_verdict(True, "volume 30", .45, self.RULE), "keep")

    def test_chat_is_kept_for_the_normal_end_not_cut_short(self):
        self.assertEqual(audio.speculation_verdict(True, "what is the weather like", .9, None), "keep")

    def test_resumed_speech_or_nothing_heard_is_dropped(self):
        self.assertEqual(audio.speculation_verdict(False, "volume 30", .9, self.RULE), "drop")
        self.assertEqual(audio.speculation_verdict(True, "  ", .9, None), "drop")

    def test_alarm_is_never_ended_early(self):
        alarm = {"actions": [("alarm", ["07:00"])], "say": "x"}
        self.assertEqual(audio.speculation_verdict(True, "alarm at 7", 1.5, alarm), "keep")


class SpeculationFlow(unittest.TestCase):
    def test_validity_follows_speech_heard_since_the_snapshot(self):
        with tempfile.TemporaryDirectory() as folder:
            spec = audio.Speculation(Path(folder) / "x.wav")
            self.assertFalse(spec.valid(1.0))           # nothing started
            spec.thread, spec.speech_at = object(), 1.0
            self.assertTrue(spec.valid(1.0))
            self.assertFalse(spec.valid(1.3))           # the user spoke again


class FakeVad:
    """Stands in for Silero: speech while `voiced` is true."""
    def __init__(self):
        self.voiced = False

    def feed(self, pcm):
        return [.9 if self.voiced else .02] * 3


class VoiceModel(unittest.TestCase):
    def detector(self, end="0.6"):
        import os
        os.environ["II_ORB_END_SILENCE"] = end
        self.vad = FakeVad()
        return audio.PauseDetector(self.vad)

    def run_turn(self, detector, speech_s, quiet_s):
        reasons = []
        for _ in range(3):
            reasons.append(detector.feed(.0, pcm=b"\0" * 3200))   # the room first
        self.vad.voiced = True
        for _ in range(int(speech_s * 10)):
            reasons.append(detector.feed(.0, pcm=b"\0" * 3200))
        self.vad.voiced = False
        for index in range(int(quiet_s * 10)):
            reason = detector.feed(.0, pcm=b"\0" * 3200)
            if reason:
                return reason, (index + 1) / 10
        return "", quiet_s

    def test_a_long_turn_ends_after_the_configured_quiet_without_any_volume(self):
        reason, waited = self.run_turn(self.detector(), 3.5, 2)
        self.assertEqual(reason, "pause")
        self.assertLessEqual(waited, .55)

    def test_a_short_phrase_waits_a_little_longer(self):
        reason, waited = self.run_turn(self.detector(), .6, 2)
        self.assertEqual(reason, "pause")
        self.assertGreater(waited, .75)
        self.assertLessEqual(waited, .9)

    def test_an_unfinished_transcript_extends_the_wait(self):
        detector = self.detector()
        detector.extra = .3
        reason, waited = self.run_turn(detector, 3.5, 2)
        self.assertGreater(waited, .7)

    def test_the_first_speech_time_is_recorded_for_trimming(self):
        detector = self.detector()
        for _ in range(12):
            detector.feed(.0, pcm=b"\0" * 3200)      # 1.2 s of reaching for the shortcut
        self.run_turn(detector, 1, .2)
        self.assertAlmostEqual(detector.first_speech_at, 1.5, delta=.11)
        pcm = bytes(range(256)) * 400
        self.assertLess(len(audio.speech_slice(pcm, detector)), len(pcm))

    def test_noise_without_a_voice_is_not_speech(self):
        detector = self.detector()
        results = [detector.feed(.3, pcm=b"\0" * 3200) for _ in range(81)]
        self.assertEqual(results[-1], "no-speech")
        self.assertEqual(detector.speech, 0)

    def test_sentences_that_look_finished(self):
        self.assertTrue(audio.looks_finished("Set a timer for ten minutes."))
        self.assertTrue(audio.looks_finished('He said "go." '))
        self.assertTrue(audio.looks_finished("What time is it?"))
        self.assertFalse(audio.looks_finished("Set a timer for"))

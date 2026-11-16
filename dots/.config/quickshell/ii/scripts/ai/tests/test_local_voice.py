"""Streaming IPC, cancellation, backend selection and short first chunks."""
import importlib.util
import json
import os
from pathlib import Path
import socket
import tempfile
import threading
import unittest
from unittest import mock

AI = Path(__file__).resolve().parents[1]


def load(name):
    spec = importlib.util.spec_from_file_location(name, AI / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


worker = load("local_voice")
client = load("companion_tools")


class Segments(unittest.TestCase):
    def test_sentences_can_start_playing_independently(self):
        self.assertEqual(worker.segments("Hello there. Here is another sentence!"), ["Hello there.", "Here is another sentence!"])

    def test_a_long_paragraph_has_a_short_first_chunk_without_losing_words(self):
        text = " ".join(["companion"] * 150)
        parts = worker.segments(text)
        self.assertLessEqual(len(parts[0]), 150)
        self.assertEqual(" ".join(parts), text)

    def test_a_long_unbroken_string_is_bounded(self):
        parts = worker.segments("x" * 1000)
        self.assertTrue(all(len(part) <= 150 for part in parts))


class Selection(unittest.TestCase):
    def test_arabic_uses_the_multilingual_fallback(self):
        with mock.patch.object(client, "speech_settings", return_value={"backend": "kokoro"}), mock.patch.object(client, "speak_edge", return_value={"isError": False}) as edge:
            client.speak({"text": "مرحبا"})
            self.assertEqual(edge.call_args.args[0]["voice"], "en-US-EmmaMultilingualNeural")

    def test_an_explicit_edge_voice_still_works(self):
        with mock.patch.object(client, "speech_settings", return_value={"backend": "kokoro"}), mock.patch.object(client, "speak_edge", return_value={}) as edge:
            client.speak({"text": "Hello", "voice": "en-US-AriaNeural"})
            edge.assert_called_once()

    def test_unsupported_backend_never_opens_a_socket(self):
        with mock.patch.object(client.socket, "socket") as connect:
            with self.assertRaises(ValueError): client.speak({"text": "Hi", "backend": "unknown"})
            connect.assert_not_called()


class Transport(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.path = Path(self.tmp.name) / "ii-companion-voice.sock"
        patch = mock.patch.object(worker, "SOCKET", self.path)
        patch.start(); self.addCleanup(patch.stop)

    def serve(self, engine):
        server = worker.Server(engine)
        threading.Thread(target=server.serve_forever, daemon=True).start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return server

    def test_client_forwards_phase_and_level_events_and_waits_for_done(self):
        requests = []
        class Engine:
            def speak(self, request, send, cancelled):
                requests.append(request)
                send({"event": "phase", "phase": "speaking", "firstAudioMs": 125})
                send({"event": "level", "level": .6})
                send({"event": "done", "isError": False})
        self.serve(Engine())
        events = []
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.tmp.name}), mock.patch.object(client, "speech_settings", return_value={"backend": "kokoro", "voice": "af_heart", "speed": 1.05}):
            result = client.speak({"text": "Hello."}, events.append)
        self.assertFalse(result["isError"])
        self.assertEqual([e["event"] for e in events], ["phase", "level", "done"])
        self.assertEqual(requests[0]["voice"], "af_heart")
        self.assertEqual(self.path.stat().st_mode & 0o777, 0o600)

    def test_closing_client_cancels_playback_in_worker(self):
        stopped = threading.Event()
        class Engine:
            def speak(self, request, send, cancelled):
                send({"event": "phase", "phase": "speaking"})
                if cancelled.wait(2): stopped.set()
        self.serve(Engine())
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
            connection.connect(str(self.path))
            connection.sendall(b'{"text":"Hi"}\n')
            self.assertIn(b'speaking', connection.recv(2048))
        self.assertTrue(stopped.wait(2))

    def test_worker_errors_are_reported_without_network_fallback(self):
        class Engine:
            def speak(self, request, send, cancelled): raise ValueError("Unknown voice")
        self.serve(Engine())
        with mock.patch.dict(os.environ, {"XDG_RUNTIME_DIR": self.tmp.name}), mock.patch.object(client, "speech_settings", return_value={"backend": "kokoro"}), mock.patch.object(client, "speak_edge") as edge:
            with self.assertRaisesRegex(RuntimeError, "Unknown voice"): client.speak({"text": "Hi"})
            edge.assert_not_called()


if __name__ == "__main__": unittest.main()

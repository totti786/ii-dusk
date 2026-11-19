#!/usr/bin/env python3
"""Resident speech-to-text for the desktop orb.

Keeps whisper.cpp's base model loaded and answers one request per connection on
$XDG_RUNTIME_DIR/ii-orb-stt.sock, so a spoken turn does not pay for a cold
`voxtype transcribe` process (model load, then a fixed 30 s window of audio).

  request   {"path": "/path/to.wav", "language": "auto"|"en"|"ar"|...}\n
  response  {"text": "..."}\n   or   {"error": "..."}\n

The audio window is sized to the clip instead of the usual fixed 30 seconds, which is
most of Whisper's cost on short utterances. The process exits after a quiet spell; the
orb starts it again when it next listens. Must run in the voice venv (pywhispercpp).
"""
import json
import os
import socket
import sys
import threading
import time
import wave
from pathlib import Path

RUNTIME = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
SOCKET = RUNTIME / "ii-orb-stt.sock"
MODELS = Path.home() / ".local/share/voxtype/models"
# Best first. "auto" takes the first installed; a name from the settings picks that one.
PREFERRED = ("small", "base")
IDLE_EXIT = 1500.0
# Whisper hears "brightness set fifty" as "brightest at 50" and "alarm at seven thirty" as nonsense
# without a hint. A prompt of the commands the orb understands biases the decoder towards them. Used
# only for English or auto-detected speech; the language is chosen from the audio before it is read.
PROMPT = ("Voice commands for a desktop assistant: volume 30, brightness 50 percent, next song, pause, play, "
          "mute, set a timer for 10 minutes, alarm at 7:30 am, dark mode, light mode, workspace 3, "
          "open Firefox, remind me to call mum.")
NOISE = {"[BLANK_AUDIO]", "[ Silence ]", "(silence)", "[MUSIC]", "[Music]"}


def duration(path):
    with wave.open(path, "rb") as audio:
        return audio.getnframes() / float(audio.getframerate())


def window(seconds):
    """Encoder context for a clip: whisper uses 1500 frames for 30 s. Generous margin,
    because too small a window loses words at the end."""
    wanted = int(seconds / 30 * 1500 * 1.5) + 128
    # Buckets, so the few (language, window) models built are reused, not one per clip length.
    return next((size for size in (512, 768, 1024) if wanted <= size), 1500)


def model_file(name, language="auto"):
    """The ggml file for a settings name ("auto", "small", "base", ...), or None. For English the
    English-only build of the same size is used when installed: smaller and more accurate."""
    name = (name or "auto").strip().lower()
    english = language == "en"
    names = []
    if name != "auto" and name.replace(".", "").replace("-", "").isalnum():
        names.append(name)
    names += list(PREFERRED)
    for wanted in names:
        base = wanted[:-3] if wanted.endswith(".en") else wanted
        for candidate in ((f"{base}.en", wanted) if english else (wanted,)):
            path = MODELS / f"ggml-{candidate}.bin"
            if path.is_file():
                return path
    return None


class Transcriber:
    def __init__(self):
        from pywhispercpp.model import Model
        self.Model = Model
        self.lock = threading.Lock()
        self.models = {}
        self.threads = max(2, min(6, (os.cpu_count() or 4) // 2))

    def load(self, path):
        """One loaded model per file, kept for the next request. Language and audio window are set
        on each call, so the weights are not loaded again for every clip length."""
        model = self.models.get(path)
        if model is None:
            if len(self.models) >= 2:
                self.models.pop(next(iter(self.models)))
            model = self.Model(str(path), n_threads=self.threads, print_progress=False,
                               print_realtime=False, print_timestamps=False)
            self.models[path] = model
        return model

    def warm(self, name="auto", language="auto"):
        """Load the model before the first request, so the first spoken turn does not pay for it."""
        path = model_file(name, language)
        if path is not None:
            with self.lock:
                self.load(path)

    def run(self, path, language, name="auto"):
        seconds = duration(path)
        context = window(seconds)
        lang = "" if language in ("", "auto") else language
        file = model_file(name, lang)
        if file is None:
            raise RuntimeError("No whisper model is installed.")
        with self.lock:
            model = self.load(file)
            params = {"audio_ctx": context, "language": lang}
            if lang in ("", "en"):
                params["initial_prompt"] = PROMPT
            segments = model.transcribe(path, **params)
        text = " ".join(s.text.strip() for s in segments).strip()
        return "" if text in NOISE else text


def main():
    if model_file("auto") is None:
        print("whisper model missing", file=sys.stderr)
        return 2
    # whisper.cpp prints model details to stderr/stdout while loading; keep stdout clean.
    transcriber = Transcriber()
    threading.Thread(target=transcriber.warm, args=("auto", os.environ.get("II_ORB_LANGUAGE", "auto")), daemon=True).start()
    if SOCKET.exists():
        try:
            probe = socket.socket(socket.AF_UNIX)
            probe.settimeout(1)
            probe.connect(str(SOCKET))
            probe.close()
            return 0  # another instance is serving
        except OSError:
            SOCKET.unlink(missing_ok=True)
    server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    server.bind(str(SOCKET))
    os.chmod(SOCKET, 0o600)
    server.listen(4)
    server.settimeout(5)
    last = time.monotonic()
    try:
        while time.monotonic() - last < IDLE_EXIT:
            try:
                client, _ = server.accept()
            except socket.timeout:
                continue
            last = time.monotonic()
            with client:
                try:
                    client.settimeout(120)
                    data = b""
                    while not data.endswith(b"\n"):
                        chunk = client.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                    request = json.loads(data)
                    path = str(request["path"])
                    if not path.endswith(".wav") or not os.path.isfile(path):
                        raise ValueError("A WAV file is required.")
                    text = transcriber.run(path, str(request.get("language", "auto")), str(request.get("model", "auto")))
                    client.sendall(json.dumps({"text": text}, ensure_ascii=False).encode() + b"\n")
                except Exception as error:
                    try:
                        client.sendall(json.dumps({"error": str(error)}).encode() + b"\n")
                    except OSError:
                        pass
            last = time.monotonic()
    finally:
        server.close()
        SOCKET.unlink(missing_ok=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())

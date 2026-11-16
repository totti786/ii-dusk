#!/usr/bin/env python3
"""Warm local Kokoro speech worker on a private Unix socket; no network listener."""
import argparse
import json
import os
from pathlib import Path
import queue
import re
import socket
import socketserver
import subprocess
import threading
import time


ROOT = Path.home() / ".local/share/quickshell-ii/kokoro"
SOCKET = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "ii-companion-voice.sock"


def segments(text, limit=150):
    """Keep the first clause short, so long replies do not delay first audio."""
    parts = []
    for sentence in re.split(r"(?<=[.!?;])\s+", text.strip()):
        while len(sentence) > limit:
            cut = sentence.rfind(" ", 35, limit)
            if cut < 0: cut = limit
            parts.append(sentence[:cut].strip())
            sentence = sentence[cut:].strip()
        if sentence: parts.append(sentence)
    return parts


class Engine:
    def __init__(self):
        import numpy as np
        import onnxruntime as ort
        from kokoro_onnx import Kokoro
        self.np = np
        options = ort.SessionOptions()
        options.intra_op_num_threads = 2
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        session = ort.InferenceSession(str(ROOT / "kokoro-v1.0.onnx"), sess_options=options,
                                       providers=["CPUExecutionProvider"])
        self.model = Kokoro.from_session(session, str(ROOT / "voices-v1.0.bin"))
        self.lock = threading.Lock()
        self.model.create("Ready.", voice="af_heart", speed=1.05, lang="en-us")

    def speak(self, request, send, cancelled):
        text = request.get("text", "")
        voice = request.get("voice", "af_heart")
        speed = float(request.get("speed", 1.05))
        if not isinstance(text, str) or not text.strip() or len(text) > 4000:
            raise ValueError("Provide 1–4000 characters.")
        if not isinstance(voice, str) or voice not in self.model.get_voices() or not voice.startswith(("af_", "am_", "bf_", "bm_")):
            raise ValueError("Choose an installed English Kokoro voice.")
        if not .5 <= speed <= 2:
            raise ValueError("Speech speed must be between 0.5 and 2.")
        if not self.lock.acquire(blocking=False):
            raise RuntimeError("Local voice is still stopping its previous utterance. Try again.")
        started = time.monotonic()
        player = None
        chunks = queue.Queue(maxsize=1)
        producer = None
        try:
            def produce():
                try:
                    for part in segments(text):
                        if cancelled.is_set(): break
                        samples, rate = self.model.create(part, voice=voice, speed=speed, lang="en-gb" if voice.startswith("b") else "en-us")
                        while not cancelled.is_set():
                            try: chunks.put((samples, rate), timeout=.1); break
                            except queue.Full: pass
                except Exception as error:
                    while not cancelled.is_set():
                        try: chunks.put(error, timeout=.1); break
                        except queue.Full: pass
                finally:
                    while not cancelled.is_set():
                        try: chunks.put(None, timeout=.1); break
                        except queue.Full: pass
            producer = threading.Thread(target=produce, daemon=True)
            producer.start()
            first = True
            # A disconnect must stop playback immediately, even during inference.
            def stop_on_cancel():
                cancelled.wait()
                if player is not None and player.poll() is None:
                    player.terminate()
            threading.Thread(target=stop_on_cancel, daemon=True).start()
            while not cancelled.is_set():
                try: item = chunks.get(timeout=.1)
                except queue.Empty: continue
                if item is None: break
                if isinstance(item, Exception): raise item
                samples, rate = item
                if first:
                    if request.get("dryRun"):
                        send({"event": "phase", "phase": "speaking", "firstAudioMs": round((time.monotonic()-started)*1000), "backend": "kokoro"})
                    else:
                        player = subprocess.Popen(["pw-play", "--raw", "--format", "f32", "--rate", str(rate), "--channels", "1", "--latency", "40ms", "-"],
                                                  stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, bufsize=0)
                        send({"event": "phase", "phase": "speaking", "firstAudioMs": round((time.monotonic()-started)*1000), "backend": "kokoro"})
                    first = False
                frame_size = rate // 10
                for offset in range(0, len(samples), frame_size):
                    if cancelled.is_set(): break
                    frame = self.np.asarray(samples[offset:offset+frame_size], dtype="<f4")
                    if player is not None:
                        player.stdin.write(frame.tobytes())
                    level = min(1, float(self.np.sqrt(self.np.mean(frame*frame))) * 7)
                    send({"event": "level", "level": level})
            if player is not None:
                player.stdin.close()
                player.wait(timeout=10)
                if player.returncode and not cancelled.is_set(): raise RuntimeError("Local audio playback failed.")
            if not cancelled.is_set(): send({"event": "done", "isError": False, "text": "Finished speaking with local Kokoro."})
        finally:
            cancelled.set()
            if player is not None and player.poll() is None:
                player.terminate()
                player.wait(timeout=3)
            # The bounded in-flight inference finishes before another request can use the model.
            if producer is not None: producer.join()
            self.lock.release()


class Handler(socketserver.BaseRequestHandler):
    def handle(self):
        cancelled = threading.Event()
        def send(event):
            try: self.request.sendall(json.dumps(event).encode() + b"\n")
            except OSError: cancelled.set()
        try:
            self.request.settimeout(10)
            body = bytearray()
            while not body.endswith(b"\n"):
                chunk = self.request.recv(1)
                if not chunk: return
                body.extend(chunk)
                if len(body) > 24000: raise ValueError("Speech request too large.")
            request = json.loads(body)
            self.request.settimeout(None)
            if request.get("action") == "status":
                send({"backend": "kokoro", "ready": True, "voices": [v for v in self.server.engine.model.get_voices() if v.startswith(("af_", "am_", "bf_", "bm_"))]})
                return
            def disconnected():
                try: self.request.recv(1)
                except OSError: pass
                cancelled.set()
            threading.Thread(target=disconnected, daemon=True).start()
            self.server.engine.speak(request, send, cancelled)
        except Exception as error:
            send({"event": "error", "isError": True, "text": str(error)})
        finally:
            cancelled.set()


class Server(socketserver.ThreadingUnixStreamServer):
    daemon_threads = True
    def __init__(self, engine):
        self.engine = engine
        SOCKET.unlink(missing_ok=True)
        super().__init__(str(SOCKET), Handler)
        os.chmod(SOCKET, 0o600)


if __name__ == "__main__":
    engine = Engine()
    print("Kokoro ready", flush=True)
    with Server(engine) as server:
        server.serve_forever()

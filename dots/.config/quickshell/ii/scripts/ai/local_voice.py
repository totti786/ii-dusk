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


def segments(text, limit=150, head=70):
    """Keep the first clause short, so long replies do not delay first audio."""
    parts = []
    for sentence in re.split(r"(?<=[.!?;])\s+", text.strip()):
        while len(sentence) > limit:
            cut = sentence.rfind(" ", 35, limit)
            if cut < 0: cut = limit
            parts.append(sentence[:cut].strip())
            sentence = sentence[cut:].strip()
        if sentence: parts.append(sentence)
    # The first piece decides when audio starts, and synthesis time grows with its length.
    if parts and len(parts[0]) > head:
        first = parts[0]
        low = min(20, head - 8)
        cut = max(first.rfind(", ", low, head), first.rfind("; ", low, head), first.rfind(": ", low, head))
        cut = cut + 1 if cut >= 0 else first.rfind(" ", low, head)
        if cut > 0: parts[0:1] = [first[:cut].strip(), first[cut:].strip()]
    return parts


SILENCE = .008          # amplitude under which the start and end of a sentence count as silence
KEEP_MS = 12            # a sliver of the original edge is kept so nothing is clipped
FIRST_HEAD = 36           # characters in the first piece of a reply: first audio grows with it
DEFAULT_GAP_MS = 130    # the pause after a full sentence; clauses get half, a bare phrase a quarter


def trim_edges(np, samples, rate):
    """Kokoro pads every sentence with ~50 ms of silence in front and ~290 ms behind. Played back to
    back that is the long pause between sentences, so the padding is cut and the pause is put back
    on purpose (see gap_for)."""
    loud = np.flatnonzero(np.abs(samples) > SILENCE)
    if loud.size == 0:
        return samples[:0]
    keep = int(rate * KEEP_MS / 1000)
    return samples[max(0, loud[0] - keep): loud[-1] + keep + 1]


def gap_for(text, gap_ms):
    """Silence to play after this piece of speech, by how it ended."""
    tail = text.rstrip().rstrip("\"')]\u201d")
    if tail.endswith((".", "!", "?", "\u2026")):
        return gap_ms
    if tail.endswith((",", ";", ":", "\u2014", "-")):
        return gap_ms // 2
    return gap_ms // 4


class Engine:
    def __init__(self):
        import numpy as np
        import onnxruntime as ort
        from kokoro_onnx import Kokoro
        self.np = np
        options = ort.SessionOptions()
        options.intra_op_num_threads = 6
        options.inter_op_num_threads = 1
        options.execution_mode = ort.ExecutionMode.ORT_SEQUENTIAL
        session = ort.InferenceSession(str(ROOT / "kokoro-v1.0.onnx"), sess_options=options,
                                       providers=["CPUExecutionProvider"])
        self.model = Kokoro.from_session(session, str(ROOT / "voices-v1.0.bin"))
        self.lock = threading.Lock()
        self.model.create("Ready.", voice="af_heart", speed=1.05, lang="en-us")

    def speak(self, request, send, cancelled, feed=None):
        """Speak `request["text"]`, or with `feed` (a queue of sentences ending in None) a whole reply
        as it is written: one player for all of it, the next sentence synthesised while the current
        one plays, so there is no gap but the one chosen on purpose."""
        text = request.get("text", "")
        voice = request.get("voice", "af_heart")
        speed = float(request.get("speed", 1.05))
        try:
            gap_ms = max(0, min(600, int(request.get("gapMs", DEFAULT_GAP_MS))))
        except (TypeError, ValueError):
            gap_ms = DEFAULT_GAP_MS
        if feed is None and (not isinstance(text, str) or not text.strip() or len(text) > 4000):
            raise ValueError("Provide 1–4000 characters.")
        if not isinstance(voice, str) or voice not in self.model.get_voices() or not voice.startswith(("af_", "am_", "bf_", "bm_")):
            raise ValueError("Choose an installed English Kokoro voice.")
        if not .5 <= speed <= 2:
            raise ValueError("Speech speed must be between 0.5 and 2.")
        # The previous sentence's `done` goes out just before its lock is released, so a
        # sentence queued behind it can arrive first: wait a moment rather than refuse.
        if not self.lock.acquire(timeout=2.0):
            raise RuntimeError("Local voice is still stopping its previous utterance. Try again.")
        started = time.monotonic()
        player = None
        chunks = queue.Queue(maxsize=1)
        producer = None
        try:
            def pieces():
                if feed is None:
                    yield from segments(text, head=FIRST_HEAD)
                    return
                spoken = 0
                while not cancelled.is_set():
                    try: item = feed.get(timeout=.1)
                    except queue.Empty: continue
                    if item is None: return
                    # Only the start of the reply is latency: its first piece is kept short.
                    yield from segments(item, head=FIRST_HEAD if spoken == 0 else 150)
                    spoken += len(item)
                    if spoken > 20000: return

            def produce():
                try:
                    for part in pieces():
                        if cancelled.is_set(): break
                        samples, rate = self.model.create(part, voice=voice, speed=speed, lang="en-gb" if voice.startswith("b") else "en-us")
                        samples = trim_edges(self.np, samples, rate)
                        pause = int(rate * gap_for(part, gap_ms) / 1000)
                        if pause: samples = self.np.concatenate([samples, self.np.zeros(pause, dtype=samples.dtype)])
                        if not len(samples): continue
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
            feed = None
            if request.get("stream"):
                feed = queue.Queue()
                def reader():
                    # More sentences follow on the same connection; {"end": true} or a closed
                    # connection finishes the reply.
                    try:
                        with self.request.makefile("rb") as lines:
                            for line in lines:
                                message = json.loads(line)
                                if message.get("end"): break
                                piece = message.get("text")
                                if isinstance(piece, str) and piece.strip(): feed.put(piece)
                            else:
                                cancelled.set()
                    except (OSError, ValueError):
                        cancelled.set()
                    feed.put(None)
                threading.Thread(target=reader, daemon=True).start()
            else:
                def disconnected():
                    try: self.request.recv(1)
                    except OSError: pass
                    cancelled.set()
                threading.Thread(target=disconnected, daemon=True).start()
            if feed is None:
                self.server.engine.speak(request, send, cancelled)
            else:
                self.server.engine.speak(request, send, cancelled, feed)
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

#!/usr/bin/env python3
"""Private microphone capture with level events and pause detection; local Voxtype STT."""
import array
import json
import math
import os
from pathlib import Path
import selectors
import signal
import subprocess
import sys
import time
import wave


def emit(event):
    print(json.dumps(event), flush=True)


def rms(pcm):
    samples = array.array("h", pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    return math.sqrt(sum(v * v for v in samples) / max(1, len(samples))) / 32768


class PauseDetector:
    def __init__(self):
        self.speech = 0
        self.quiet = 0
        self.total = 0
        self.noise = .003

    def feed(self, level, seconds=.1):
        self.total += seconds
        threshold = max(.012, self.noise * 3)
        if level > threshold:
            self.speech += seconds
            self.quiet = 0
        else:
            self.quiet += seconds
            if self.speech < .2:
                self.noise = self.noise * .95 + min(level, .02) * .05
        if self.total >= 60:
            return "limit"
        # Longer utterances have enough context to end confidently; short
        # phrases keep a little extra space for a natural mid-sentence pause.
        end_silence = .75 if self.speech >= 1.5 else 1.0
        if self.speech >= .3 and self.quiet + 1e-9 >= end_silence:
            return "pause"
        if self.speech < .3 and self.total >= 8:
            return "no-speech"
        return ""


def capture(path):
    stopped = {"stop": False, "cancel": False}
    signal.signal(signal.SIGUSR1, lambda *_: stopped.update(stop=True))
    signal.signal(signal.SIGTERM, lambda *_: stopped.update(stop=True, cancel=True))
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    process = subprocess.Popen(["pw-record", "--raw", "--format", "s16", "--rate", "16000", "--channels", "1", "-"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    detector = PauseDetector()
    buffer = b""
    reason = "stopped"
    try:
        with wave.open(str(target), "wb") as audio:
            os.chmod(target, 0o600)
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(16000)
            emit({"event": "recording"})
            deadline = time.monotonic() + 65
            while not stopped["stop"] and time.monotonic() < deadline:
                if not selector.select(.1):
                    if process.poll() is not None:
                        raise RuntimeError("Microphone capture stopped unexpectedly.")
                    continue
                chunk = os.read(process.stdout.fileno(), 3200)
                if not chunk:
                    raise RuntimeError("The microphone returned no audio.")
                buffer += chunk
                while len(buffer) >= 3200:
                    frame, buffer = buffer[:3200], buffer[3200:]
                    audio.writeframesraw(frame)
                    level = rms(frame)
                    emit({"event": "level", "level": min(1, level * 9)})
                    reason = detector.feed(level)
                    if reason:
                        stopped["stop"] = True
                        break
        if stopped["cancel"] or reason == "no-speech" or detector.speech < .2:
            target.unlink(missing_ok=True)
            emit({"event": "cancelled" if stopped["cancel"] else "no-speech"})
        else:
            emit({"event": "captured", "path": str(target)})
    except Exception:
        target.unlink(missing_ok=True)
        raise
    finally:
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()


def transcribe(path, output):
    # Isolate from the user's dictation config and post-processing hooks.
    result = subprocess.run(["voxtype", "--quiet", "--config", "/dev/null", "--engine", "whisper",
                             "--model", "base", "--language", "auto", "transcribe", path],
                            capture_output=True, text=True, timeout=100)
    if result.returncode:
        raise RuntimeError(result.stderr[-1200:] or "Voxtype transcription failed.")
    text = result.stdout.strip().rsplit("\n\n", 1)[-1].strip()
    Path(output).write_text(text)
    os.chmod(output, 0o600)


if __name__ == "__main__":
    try:
        if sys.argv[1] == "capture":
            capture(sys.argv[2])
        elif sys.argv[1] == "transcribe":
            # Cancelling transcription also stops Voxtype's inference process.
            os.setpgrp()
            def cancel(*_):
                signal.signal(signal.SIGTERM, signal.SIG_IGN)
                os.killpg(os.getpgrp(), signal.SIGTERM)
                sys.exit(0)
            signal.signal(signal.SIGTERM, cancel)
            transcribe(sys.argv[2], sys.argv[3])
        else:
            raise ValueError("Unknown audio operation.")
    except Exception as error:
        emit({"event": "error", "message": str(error)})
        sys.exit(1)

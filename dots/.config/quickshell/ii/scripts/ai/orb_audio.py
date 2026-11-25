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
import threading
import time
import wave
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # sibling modules, also when loaded by path
import aec  # noqa: E402


def emit(event):
    print(json.dumps(event), flush=True)


def rms(pcm):
    samples = array.array("h", pcm)
    if sys.byteorder != "little":
        samples.byteswap()
    return math.sqrt(sum(v * v for v in samples) / max(1, len(samples))) / 32768


class PauseDetector:
    """Ends an utterance after a pause. The silence threshold follows the room: a laptop
    mic with steady background noise sits well above any fixed level, and a fixed
    threshold then never hears a pause, so the turn only ends when you click."""

    def __init__(self, vad=None, push_to_talk=False):
        self.speech = 0
        self.quiet = 0
        self.total = 0
        self.recent = []
        self.floor = None
        self.floor_start = None
        self.warm = []
        # With a voice-activity model each window is judged on how speech-like it is, not how
        # loud, so the end of a turn is heard in a noisy room too, and sooner.
        self.vad = vad
        self.push_to_talk = push_to_talk
        self.voiced = False
        self.first_speech_at = None
        self.extra = 0.0   # seconds added to the wait while the transcript so far looks unfinished
        try:
            self.end_base = max(.3, min(2.0, float(os.environ.get("II_ORB_END_SILENCE", ".6"))))
        except ValueError:
            self.end_base = .6

    def end_silence(self):
        """How long a pause ends the turn. Short phrases get a little more room for a mid-sentence
        breath; a long utterance has enough context to end confidently."""
        if self.speech < 1.0:
            wait = self.end_base + .25
        elif self.speech >= 3.0:
            wait = max(.4, self.end_base - .1)
        else:
            wait = self.end_base
        return wait + self.extra

    def feed_vad(self, seconds, pcm):
        self.total += seconds
        probs = self.vad.feed(pcm)
        if probs:
            self.prob = max(probs)
        prob = getattr(self, "prob", 0.0)
        # Hysteresis: starting needs a clear voice, staying only needs the voice not to be gone.
        self.voiced = self.total >= .15 and prob > (.35 if self.voiced else .5)
        if self.voiced:
            if self.first_speech_at is None:
                self.first_speech_at = max(0.0, self.total - seconds)
            self.speech += seconds
            self.quiet = 0
        else:
            self.quiet += seconds
        if self.total >= 60:
            return "limit"
        if self.push_to_talk:
            return ""
        if self.speech >= .3 and self.quiet + 1e-9 >= self.end_silence():
            return "pause"
        if self.speech < .3 and self.total >= 8:
            return "no-speech"
        return ""

    def threshold(self):
        # Speech has to clear the learned floor by a margin; the floor itself is never
        # trusted above .04, so speech that began before it was learned still counts.
        return max(.012, min(.04, self.floor or 0) * 1.8)

    def feed(self, level, seconds=.1, pcm=None):
        if self.vad is not None and pcm is not None:
            return self.feed_vad(seconds, pcm)
        reason = self.feed_rms(level, seconds)
        if self.speech > 0 and self.first_speech_at is None:
            self.first_speech_at = max(0.0, self.total - seconds)
        return reason

    def feed_rms(self, level, seconds=.1):
        self.total += seconds
        self.recent = (self.recent + [level])[-3:]
        average = sum(self.recent) / len(self.recent)
        # The first moments of a capture are the device waking up (often digital
        # silence), then the room. Learn the floor from .4-1.0 s before judging
        # speech; only a clearly loud sound counts as speech in the meantime.
        if .4 <= self.total < 1.0:
            self.warm.append(level)
        if self.total < 1.0:
            if level > (.025 if self.push_to_talk else .1):
                self.speech += seconds
                self.quiet = 0
            return ""
        if self.floor is None:
            ordered = sorted(self.warm) or [0]
            self.floor = ordered[len(ordered) // 5]
            self.floor_start = self.floor
        else:
            # Falls to any quieter stretch at once, creeps up slowly so a floor
            # learned from a dip does not stay too low as the noise changes.
            self.floor = min(self.floor * 1.01 + .0002, average, self.floor_start * 2 + .01)
        # In a noisy room judge a short average, so one spike of noise does not restart
        # the wait; in a quiet one the raw level ends the turn a couple of frames sooner.
        measured = average if self.threshold() > .02 else level
        if measured > self.threshold():
            self.speech += seconds
            self.quiet = 0
        else:
            self.quiet += seconds
        if self.total >= 60:
            return "limit"
        if self.push_to_talk:
            return ""
        # Longer utterances have enough context to end confidently; short
        # phrases keep a little extra space for a natural mid-sentence pause.
        end_silence = (.75 if self.speech >= 1.5 else 1.0) + self.extra
        if self.speech >= .3 and self.quiet + 1e-9 >= end_silence:
            return "pause"
        if self.speech < .3 and self.total >= 8:
            return "no-speech"
        return ""


SPECULATE_AFTER = .3   # seconds of quiet before transcribing what has been said so far
EARLY_END_AFTER = .55  # quiet needed to end the turn on a speculative command match


def speculation_verdict(valid, text, quiet, rule):
    """What to do with a speculative transcript. `valid` means no speech has been heard since the
    snapshot, so the snapshot is exactly what the final one would be (only silence was added).
      end   it is a complete rule command and the pause has lasted: stop listening now
      keep  use it as the final transcript when the normal pause ends
      drop  speech resumed or nothing was recognised
    `rule` is the match from voice_rules, or None. An alarm is never ended early: "alarm at 7"
    is often followed by "30"."""
    if not valid or not text.strip():
        return "drop"
    if rule is not None and quiet >= EARLY_END_AFTER and all(verb != "alarm" for verb, _ in rule["actions"]):
        return "end"
    return "keep"


class Speculation:
    """Transcribes the audio so far while the pause detector is still waiting, in a thread, so the
    microphone keeps being read. One at a time: the resident transcriber serves one request at a time."""

    def __init__(self, target):
        self.path = Path(str(target) + ".spec.wav")
        self.thread = None
        self.text = None
        self.speech_at = -1.0

    def alive(self):
        return self.thread is not None and self.thread.is_alive()

    def start(self, frames, speech):
        if self.alive() or not (ENGINE == "hex" or STT_SOCKET.exists()):
            return
        self.text, self.speech_at = None, speech
        snapshot = bytes(frames)
        path = self.path

        def work():
            try:
                with wave.open(str(path), "wb") as audio:
                    os.chmod(path, 0o600)
                    audio.setnchannels(1)
                    audio.setsampwidth(2)
                    audio.setframerate(16000)
                    audio.writeframes(snapshot)
                self.text = transcribe_clip(path)
            except Exception:
                self.text = ""
            finally:
                path.unlink(missing_ok=True)
        self.thread = threading.Thread(target=work, daemon=True)
        self.thread.start()

    def valid(self, speech):
        return self.thread is not None and abs(speech - self.speech_at) < 1e-9

    def finish(self, timeout=3):
        if self.thread is not None:
            self.thread.join(timeout)
        return self.text


PRE_ROLL = .4          # seconds kept before the first detected speech, so a soft first word survives
TERMINAL = ("." , "!", "?", "\u061f", "\u3002", "\u2026")


def speech_slice(everything, detector):
    """The audio from just before the first speech: the silence the user spent reaching for the
    shortcut is not sent to the transcriber (shorter clips are faster and Whisper invents words
    in long silences)."""
    if detector.first_speech_at is None:
        return bytes(everything)
    start = int(max(0.0, detector.first_speech_at - PRE_ROLL) * 16000) * 2
    return bytes(everything[start:])


def trim_wav(target, pcm):
    with wave.open(str(target), "wb") as audio:
        os.chmod(target, 0o600)
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16000)
        audio.writeframes(pcm)


def looks_finished(text):
    """Whisper punctuates what it hears: a full stop or question mark after the last word means
    the sentence is done, none usually means the speaker only paused to think."""
    text = text.strip().rstrip("\"')]\u201d")
    return text.endswith(TERMINAL)


def capture(path):
    stopped = {"stop": False, "cancel": False}
    signal.signal(signal.SIGUSR1, lambda *_: stopped.update(stop=True))
    signal.signal(signal.SIGTERM, lambda *_: stopped.update(stop=True, cancel=True))
    target = Path(path)
    target.parent.mkdir(parents=True, exist_ok=True)
    if ENGINE != "hex":
        start_resident_stt()
    process = subprocess.Popen(["pw-record", *aec.source_args(), "--raw", "--format", "s16", "--rate", "16000", "--channels", "1", "-"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    import vad as vad_module
    push_to_talk = os.environ.get("II_ORB_PUSH_TO_TALK") == "1"
    detector = PauseDetector(vad_module.load(), push_to_talk=push_to_talk)
    buffer = b""
    reason = "stopped"
    everything = bytearray()
    speculation = Speculation(target)
    early = ""
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
                    everything += frame
                    level = rms(frame)
                    emit({"event": "level", "level": min(1, level * 9)})
                    reason = detector.feed(level, pcm=frame)
                    if not push_to_talk and not reason and os.environ.get("II_ORB_SPECULATE", "1") != "0" and detector.speech >= .3:
                        if detector.quiet >= SPECULATE_AFTER and not speculation.alive() \
                                and not speculation.valid(detector.speech):
                            speculation.start(speech_slice(everything, detector), detector.speech)
                        elif speculation.thread is not None and not speculation.alive() \
                                and speculation.valid(detector.speech):
                            import voice_rules
                            heard = speculation.text or ""
                            rule = voice_rules.match(heard)
                            if speculation_verdict(True, heard, detector.quiet, rule) == "end":
                                reason, early = "pause", "rule"
                            elif heard.strip():
                                if looks_finished(heard):
                                    detector.extra = 0.0
                                    # A finished sentence needs less of a pause to be believed.
                                    if detector.quiet >= EARLY_END_AFTER and detector.speech >= .8:
                                        reason, early = "pause", "sentence"
                                else:
                                    # Probably only a breath: give the next word a little longer.
                                    detector.extra = .3
                    if reason:
                        stopped["stop"] = True
                        break
        if stopped["cancel"] or reason == "no-speech" or detector.speech < .2:
            target.unlink(missing_ok=True)
            emit({"event": "cancelled" if stopped["cancel"] else "no-speech"})
        elif push_to_talk and (reason == "limit" or not stopped["stop"]):
            target.unlink(missing_ok=True)
            emit({"event": "error", "message": "Push-to-talk reached its 60-second limit. Hold the shortcut again to retry."})
        else:
            ended_at = int(time.time() * 1000)
            text = ""
            if reason == "pause" and speculation.thread is not None and speculation.valid(detector.speech):
                # A speculative transcript still running is the one the real transcription would queue behind.
                text = (speculation.finish() or "").strip()
                early = early or ("reuse" if text else "")
            if text:
                target.unlink(missing_ok=True)   # the audio is not needed, and is not kept
                emit({"event": "captured", "text": text, "early": early, "endedAt": ended_at})
            else:
                trim_wav(target, speech_slice(everything, detector))
                emit({"event": "captured", "path": str(target), "endedAt": ended_at})
    except Exception:
        target.unlink(missing_ok=True)
        raise
    finally:
        speculation.path.unlink(missing_ok=True)
        selector.close()
        process.terminate()
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()
        process.stdout.close()


STT_SOCKET = Path(os.environ.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}")) / "ii-orb-stt.sock"
STT_PYTHON = Path(os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV") or Path.home() / ".local/state/quickshell/.venv") / "bin/python"
STT_DAEMON = Path(__file__).resolve().parent / "stt_daemon.py"


def _stt_socket_alive():
    import socket
    probe = socket.socket(socket.AF_UNIX)
    probe.settimeout(1)
    try:
        probe.connect(str(STT_SOCKET))
        return True
    except OSError:
        return False
    finally:
        probe.close()


def start_resident_stt(wait=0.0):
    """Warm the resident transcriber. During capture `wait` is 0, so it loads while the user is
    still talking. After a failed Hex clip it waits for the socket: connecting before the daemon
    was listening used to drop the turn to a cold Voxtype process, model load included."""
    if not STT_PYTHON.exists():
        return False
    if STT_SOCKET.exists():
        if _stt_socket_alive():
            return True
        STT_SOCKET.unlink(missing_ok=True)  # left behind by a process that died
    try:
        subprocess.Popen([str(STT_PYTHON), str(STT_DAEMON)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
    except OSError:
        return False
    deadline = time.monotonic() + max(0.0, wait)
    while True:
        if STT_SOCKET.exists() and _stt_socket_alive():
            return True
        if time.monotonic() >= deadline:
            return False
        time.sleep(0.05)


# Which engine reads the clip: "hex" (the dictation engine, `hex transcribe`) or "whisper" (the resident
# daemon, then Voxtype). The shell resolves the setting and passes it in.
ENGINE = os.environ.get("II_ORB_STT_ENGINE", "whisper")


class EngineUnavailable(RuntimeError):
    """The chosen engine cannot read this clip (not running, a feature off); the next engine may."""


def hex_transcribe(path):
    """Hex's own model (Parakeet) reads the clip: the same engine as the dictation keys. Prints nothing and
    exits 1 for a clip with no speech, which is an empty transcript, not a failure."""
    try:
        done = subprocess.run(["hex", "transcribe", "--json", str(path)], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired) as error:
        raise EngineUnavailable(f"Hex: {error}") from error
    if done.returncode == 0:
        try:
            return str(json.loads(done.stdout).get("text", "")).strip()
        except ValueError as error:
            raise EngineUnavailable("Hex gave an answer that is not JSON.") from error
    said = (done.stderr + done.stdout).lower()
    if "no speech" in said:
        return ""
    raise EngineUnavailable((done.stderr or done.stdout).strip()[-300:] or f"Hex exited {done.returncode}")


def transcribe_clip(path):
    """The transcript from the chosen engine, falling back to the resident Whisper daemon."""
    if ENGINE == "hex":
        try:
            return hex_transcribe(path)
        except EngineUnavailable:
            start_resident_stt(wait=5.0)
    return resident_transcribe(path)


def resident_transcribe(path):
    import socket
    with socket.socket(socket.AF_UNIX) as client:
        client.settimeout(60)
        client.connect(str(STT_SOCKET))
        client.sendall(json.dumps({"path": str(path), "language": os.environ.get("II_ORB_LANGUAGE", "auto"),
                                   "model": os.environ.get("II_ORB_STT_MODEL", "auto")}).encode() + b"\n")
        data = b""
        while not data.endswith(b"\n"):
            chunk = client.recv(65536)
            if not chunk:
                break
            data += chunk
    reply = json.loads(data)
    if "error" in reply:
        raise RuntimeError(reply["error"])
    return str(reply.get("text", "")).strip()


def transcribe(path, output):
    try:
        text = transcribe_clip(path)
        Path(output).write_text(text)
        os.chmod(output, 0o600)
        return
    except (OSError, ValueError, RuntimeError):
        pass  # no resident transcriber yet: the cold Voxtype path below still works
    # Isolate from the user's dictation config and post-processing hooks.
    result = subprocess.run(["voxtype", "--quiet", "--config", "/dev/null", "--engine", "whisper",
                             "--model", os.environ.get("II_ORB_STT_MODEL", "auto").replace("auto", "base"),
                             "--language", os.environ.get("II_ORB_LANGUAGE", "auto"), "transcribe", path],
                            capture_output=True, text=True, timeout=100)
    if result.returncode:
        raise RuntimeError(result.stderr[-1200:] or "Voxtype transcription failed.")
    text = result.stdout.strip().rsplit("\n\n", 1)[-1].strip()
    from stt_daemon import clean
    text = clean(text)
    Path(output).write_text(text)
    os.chmod(output, 0o600)


def reexec_in_voice_venv():
    """The voice-activity model needs onnxruntime and numpy, which live in the voice venv, not in
    the system Python the shell launches this with."""
    if os.environ.get("II_ORB_VAD", "1") == "0" or not STT_PYTHON.exists():
        return
    if Path(sys.prefix).resolve() == STT_PYTHON.parent.parent.resolve():
        return
    os.execv(str(STT_PYTHON), [str(STT_PYTHON)] + sys.argv)


if __name__ == "__main__":
    try:
        if sys.argv[1] == "capture":
            reexec_in_voice_venv()
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

#!/usr/bin/env python3
"""Resident wake-word listener for the voice orb.

Reads 16 kHz mono from PipeWire, runs openWakeWord (ONNX) on 80 ms frames and prints
one JSON line per event on stdout:

  {"event": "ready"}
  {"event": "wake", "word": "hey_jarvis", "score": 0.93}
  {"event": "error", "message": "..."}

No audio is stored or sent anywhere. The QML service stops this process while a voice
session owns the microphone and starts it again afterwards.

Env: II_WAKE_WORD (model name, default hey_jarvis), II_WAKE_THRESHOLD (default 0.5),
II_WAKE_COOLDOWN (seconds between wakes, default 2).
"""
import json
import os
import signal
import subprocess
import sys
import time
from pathlib import Path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))  # sibling modules, also when loaded by path
import aec  # noqa: E402

# The shell's one Python environment (the same one every other helper uses).
VENV_PYTHON = Path(os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV") or Path.home() / ".local/state/quickshell/.venv") / "bin/python"
FRAME = 1280  # samples, 80 ms: what openWakeWord expects per predict call


def emit(event):
    print(json.dumps(event), flush=True)


def reexec_in_voice_venv():
    if VENV_PYTHON.exists() and Path(sys.prefix).resolve() != VENV_PYTHON.parent.parent.resolve():
        os.execv(str(VENV_PYTHON), [str(VENV_PYTHON), *sys.argv])


def main():
    reexec_in_voice_venv()
    import numpy as np
    from openwakeword.model import Model

    word = os.environ.get("II_WAKE_WORD", "hey_jarvis")
    threshold = float(os.environ.get("II_WAKE_THRESHOLD", "0.5"))
    cooldown = float(os.environ.get("II_WAKE_COOLDOWN", "2"))
    try:
        import openwakeword
        if word in openwakeword.MODELS:
            # A pretrained word: fetched once, then kept in the package's resources folder.
            if not Path(openwakeword.MODELS[word]["model_path"]).with_suffix(".onnx").exists():
                from openwakeword.utils import download_models
                download_models([word])
            word = str(Path(openwakeword.MODELS[word]["model_path"]).with_suffix(".onnx"))
        elif "/" not in word:
            # A word we trained ourselves: ~/.local/share/quickshell-ii/wake/<word>.onnx
            custom = Path.home() / ".local/share/quickshell-ii/wake" / (word + ".onnx")
            if custom.exists():
                word = str(custom)
        # Otherwise `word` is the path of a custom .onnx model.
        model = Model(wakeword_models=[word], inference_framework="onnx")
    except Exception as error:
        emit({"event": "error", "message": f"wake word model '{word}' failed to load: {error}"})
        return 1
    name = next(iter(model.models))

    process = subprocess.Popen(["pw-record", *aec.source_args(), "--raw", "--format", "s16", "--rate", "16000", "--channels", "1", "-"],
                               stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
    # The shell stops the detector with SIGTERM: exit through the finally below so pw-record goes with it.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    emit({"event": "ready"})
    last = 0.0
    need = FRAME * 2
    try:
        while True:
            data = b""
            while len(data) < need:
                chunk = process.stdout.read(need - len(data))
                if not chunk:
                    emit({"event": "error", "message": "The microphone stopped."})
                    return 1
                data += chunk
            score = model.predict(np.frombuffer(data, dtype=np.int16))[name]
            now = time.monotonic()
            if score >= threshold and now - last >= cooldown:
                last = now
                model.reset()
                emit({"event": "wake", "word": name, "score": round(float(score), 3)})
    finally:
        process.terminate()


if __name__ == "__main__":
    sys.exit(main() or 0)

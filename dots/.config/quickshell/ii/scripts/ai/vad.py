"""Silero voice-activity detection for the orb's microphone.

An RMS threshold cannot tell speech from a fan, a keyboard or a TV in the next room, so it
either never hears the end of a turn or ends it on a breath. Silero is a 2 MB model that says
how likely each 32 ms window is speech, in about 0.1 ms of CPU. Used by orb_audio.py; when the
model or onnxruntime is missing, `load()` returns None and the RMS detector is used instead.
"""
import os
from pathlib import Path

MODEL = Path(os.environ.get("II_ORB_VAD_MODEL", Path.home() / ".local/share/quickshell-ii/vad/silero_vad.onnx"))
WINDOW = 512      # samples per decision at 16 kHz (32 ms)
CONTEXT = 64      # samples of the previous window the model wants in front of each one


class SileroVad:
    def __init__(self, path=MODEL):
        import numpy as np
        import onnxruntime as ort
        self.np = np
        options = ort.SessionOptions()
        options.intra_op_num_threads = 1
        options.inter_op_num_threads = 1
        self.session = ort.InferenceSession(str(path), sess_options=options, providers=["CPUExecutionProvider"])
        self.reset()

    def reset(self):
        np = self.np
        self.state = np.zeros((2, 1, 128), dtype=np.float32)
        self.context = np.zeros((1, CONTEXT), dtype=np.float32)
        self.pending = np.zeros(0, dtype=np.float32)
        self.sr = np.array(16000, dtype=np.int64)

    def window(self, samples):
        np = self.np
        data = np.concatenate([self.context, samples.reshape(1, -1)], axis=1)
        out, self.state = self.session.run(None, {"input": data, "state": self.state, "sr": self.sr})
        self.context = data[:, -CONTEXT:]
        return float(out[0][0])

    def feed(self, pcm):
        """Probabilities for every complete 32 ms window in this s16le chunk (the remainder waits
        for the next chunk). Empty list until a window is complete."""
        np = self.np
        samples = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768.0
        self.pending = np.concatenate([self.pending, samples])
        probs = []
        while len(self.pending) >= WINDOW:
            probs.append(self.window(self.pending[:WINDOW]))
            self.pending = self.pending[WINDOW:]
        return probs


def load():
    """A ready SileroVad, or None when it cannot run here."""
    if os.environ.get("II_ORB_VAD", "1") == "0" or not MODEL.is_file():
        return None
    try:
        return SileroVad()
    except Exception:
        return None

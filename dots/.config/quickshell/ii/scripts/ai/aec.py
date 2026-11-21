"""Echo cancellation for the voice orb.

Loads PipeWire's WebRTC echo canceller once (a virtual source and sink that follow the default
devices) so the orb can hear "stop" or "hey borb" while it is talking through the speakers.
The orb plays its speech into the sink and listens on the source; the canceller subtracts what it
played from what the microphone hears. If it cannot be loaded everything falls back to the plain
default devices. OFF by default: on laptop speakers it removed the orb's echo but also mangled the
user's voice while the orb was talking (measured 2026-11-21), so interrupting by voice did not work.
Set II_AEC=1 in the environment to switch it on.
"""
import os
import subprocess
import time

SOURCE = "orb_aec_source"
SINK = "orb_aec_sink"
ARGS = "extended_filter=1 delay_agnostic=1 high_pass_filter=1 noise_suppression=0 analog_gain_control=0 digital_gain_control=0"


def _pactl(*args):
    try:
        return subprocess.run(["pactl", *args], capture_output=True, text=True, timeout=5)
    except Exception:
        return None


def _listed(kind, name):
    out = _pactl("list", "short", kind)
    return out is not None and any(line.split("\t")[1:2] == [name] for line in out.stdout.splitlines())


_ready = False


def ensure():
    """True when the echo-cancelling source and sink exist (loading them if needed)."""
    global _ready
    if _ready:
        return True
    if os.environ.get("II_AEC", "0") != "1":
        return False
    _ready = _load()
    return _ready


def _load():
    if _listed("sources", SOURCE) and _listed("sinks", SINK):
        return True
    done = _pactl("load-module", "module-echo-cancel", "aec_method=webrtc", f"source_name={SOURCE}",
                  f"sink_name={SINK}", f"aec_args={ARGS}")
    if done is None or done.returncode != 0:
        return False
    for _ in range(10):
        if _listed("sources", SOURCE) and _listed("sinks", SINK):
            return True
        time.sleep(0.2)
    return False


def source_args():
    return ["--target", SOURCE] if ensure() else []


def sink_args():
    return ["--target", SINK] if ensure() else []


def mpv_args():
    return ["--ao=pipewire", f"--audio-device=pipewire/{SINK}"] if ensure() else []

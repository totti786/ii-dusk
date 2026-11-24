#!/usr/bin/env python3
"""What the voice orb needs to listen and speak, and the one-step ways to get what is missing.

  speech_setup.py status          JSON: engines found, models present, downloads in progress
  speech_setup.py get whisper     download ggml-base.en.bin into Voxtype's model folder
  speech_setup.py get kokoro      download the Kokoro voice model and voices, then start the voice daemon
  speech_setup.py hex-on          switch on Hex's "Transcribe files" lab, which the orb needs to use Hex

Downloads go to `<name>.part` and are renamed when complete, so a cut-off one is never mistaken for a
model. `status` reports the partial size so the settings page can show progress.
"""
import json
import os
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

HOME = Path.home()
WHISPER_DIR = HOME / ".local/share/voxtype/models"
KOKORO_DIR = HOME / ".local/share/quickshell-ii/kokoro"
HERE = Path(__file__).resolve().parent
FILES = {
    "whisper": [(WHISPER_DIR / "ggml-base.en.bin", "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin", 147_964_211)],
    "kokoro": [(KOKORO_DIR / "kokoro-v1.0.onnx", "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/kokoro-v1.0.onnx", 325_532_387),
               (KOKORO_DIR / "voices-v1.0.bin", "https://github.com/thewh1teagle/kokoro-onnx/releases/download/model-files-v1.0/voices-v1.0.bin", 28_214_398)],
}


def run(*cmd, timeout=10):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.TimeoutExpired):
        return None


def hex_transcribe_on():
    done = run("hex", "labs")
    if done is None or done.returncode != 0:
        return False
    return any(line.split()[:2] == ["transcribe-files", "on"] for line in done.stdout.splitlines())


def venv_bin(name):
    base = Path(os.environ.get("ILLOGICAL_IMPULSE_VIRTUAL_ENV") or HOME / ".local/state/quickshell/.venv")
    return (base / "bin" / name).is_file() or bool(shutil.which(name))


def partial(kind):
    return sum(path.with_name(path.name + ".part").stat().st_size
               for path, _, _ in FILES[kind] if path.with_name(path.name + ".part").exists())


def status():
    whisper = [p.name for p in WHISPER_DIR.glob("ggml-*.bin")] if WHISPER_DIR.is_dir() else []
    return {
        "hex": bool(shutil.which("hex")),
        "hexTranscribe": bool(shutil.which("hex")) and hex_transcribe_on(),
        "voxtype": bool(shutil.which("voxtype")),
        "whisperModels": sorted(whisper),
        "whisperEnglish": any(n in whisper for n in ("ggml-base.en.bin", "ggml-small.en.bin")),
        "kokoro": all(p.is_file() for p, _, _ in FILES["kokoro"]),
        "edgeTts": venv_bin("edge-tts"),
        "espeak": bool(shutil.which("espeak-ng")),
        "downloading": {kind: {"bytes": partial(kind), "total": sum(t for _, _, t in FILES[kind])}
                        for kind in FILES if partial(kind) > 0 and (HOME / ".local/state/quickshell/user/ai/speech-setup" / f"{kind}.lock").exists()},
    }


def get(kind):
    state = HOME / ".local/state/quickshell/user/ai/speech-setup"
    state.mkdir(parents=True, exist_ok=True)
    lock = state / f"{kind}.lock"
    if lock.exists():
        try:
            os.kill(int(lock.read_text() or 0), 0)
            return 0   # already downloading
        except (OSError, ValueError):
            pass
    lock.write_text(str(os.getpid()))
    try:
        for path, url, _ in FILES[kind]:
            if path.is_file():
                continue
            path.parent.mkdir(parents=True, exist_ok=True)
            part = path.with_name(path.name + ".part")
            request = urllib.request.Request(url, headers={"User-Agent": "ii-shell"})
            with urllib.request.urlopen(request, timeout=30) as reply, open(part, "wb") as out:
                shutil.copyfileobj(reply, out, 1 << 20)
            os.replace(part, path)
        if kind == "kokoro":
            subprocess.Popen(["bash", str(HERE / "ensure_daemons.sh")], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                             start_new_session=True)
        (state / f"{kind}.failed").unlink(missing_ok=True)
        return 0
    except Exception as error:
        (state / f"{kind}.failed").write_text(str(error))
        return 1
    finally:
        lock.unlink(missing_ok=True)


def main():
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    if command == "status":
        print(json.dumps(status()))
        return 0
    if command == "get" and len(sys.argv) > 2 and sys.argv[2] in FILES:
        return get(sys.argv[2])
    if command == "hex-on":
        done = run("hex", "labs", "on", "transcribe-files")
        return 0 if done is not None and done.returncode == 0 else 1
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

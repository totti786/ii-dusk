"""Exercise AudioRecorderService's native transport with a synthetic WAV.

The fixture copies the production service into a temporary, minimal Quickshell
module. It uses a generated silent file whose name contains spaces, ``#`` and
Unicode, keeps the output muted, and never touches the user's recordings or
microphone.
"""

from pathlib import Path
import json
import os
import subprocess
import tempfile
import wave


ROOT = Path(__file__).resolve().parents[2]
SERVICE = (ROOT / "services/AudioRecorderService.qml").read_text()


def write_fixture(root: Path, wav_path: Path) -> Path:
    modules = root / "qmlmodules" / "qs" / "services"
    modules.mkdir(parents=True)

    # The production imports are supplied by Quickshell's config-root resolver.
    # The isolated module only needs the service and an identity translator.
    service = SERVICE.replace("import qs\n", "").replace("import qs.modules.common\n", "")
    (modules / "AudioRecorderService.qml").write_text(service)
    (modules / "Translation.qml").write_text(
        "pragma Singleton\n"
        "import QtQuick\n"
        "QtObject { function tr(value) { return value; } }\n"
    )
    (modules / "qmldir").write_text(
        "module qs.services\n"
        "singleton AudioRecorderService 1.0 AudioRecorderService.qml\n"
        "singleton Translation 1.0 Translation.qml\n"
    )

    config = root / "transport_smoke.qml"
    config.write_text(
        f'''import QtQuick
import Quickshell
import qs.services

Scope {{
    id: root
    property int phase: 0
    property int ticks: 0
    property real pausedPosition: -1
    property real resumedPosition: -1

    Timer {{
        interval: 100
        repeat: true
        running: true

        onTriggered: {{
            root.ticks++;

            if (root.phase === 0 && !AudioRecorderService.listLoading
                    && AudioRecorderService.recordings.length > 0) {{
                AudioRecorderService.volume = 0;
                AudioRecorderService.play(AudioRecorderService.recordings[0]);
                root.phase = 1;
            }} else if (root.phase === 1 && AudioRecorderService.playing
                    && AudioRecorderService.playbackPosition > 0) {{
                root.pausedPosition = AudioRecorderService.playbackPosition;
                AudioRecorderService.pausePlayback();
                console.log("AUDIO_SMOKE_PAUSED", JSON.stringify({{
                    position: root.pausedPosition,
                    duration: AudioRecorderService.playbackDuration
                }}));
                root.phase = 2;
            }} else if (root.phase === 2 && AudioRecorderService.playbackPaused) {{
                AudioRecorderService.resumePlayback();
                root.phase = 3;
            }} else if (root.phase === 3 && AudioRecorderService.playing) {{
                root.resumedPosition = AudioRecorderService.playbackPosition;
                AudioRecorderService.seek(999);
                console.log("AUDIO_SMOKE_RESUMED", JSON.stringify({{
                    position: root.resumedPosition,
                    duration: AudioRecorderService.playbackDuration
                }}));
                console.log("AUDIO_SMOKE_SEEK", JSON.stringify({{
                    position: AudioRecorderService.playbackPosition,
                    duration: AudioRecorderService.playbackDuration
                }}));
                AudioRecorderService.stopPlayback();
                root.phase = 4;
            }} else if (root.phase === 4) {{
                console.log("AUDIO_SMOKE_DONE");
                Qt.quit();
            }} else if (root.ticks > 120) {{
                console.log("AUDIO_SMOKE_TIMEOUT", JSON.stringify({{
                    phase: root.phase,
                    error: AudioRecorderService.playbackError
                }}));
                Qt.quit();
            }}
        }}
    }}
}}
'''
    )
    return config


with tempfile.TemporaryDirectory(prefix="ii-audio-recorder-transport-smoke-") as temp_name:
    temp = Path(temp_name)
    recordings = temp / "Music" / "Recordings"
    recordings.mkdir(parents=True)
    wav_path = recordings / "voice note #1 – café.wav"
    with wave.open(str(wav_path), "wb") as output:
        output.setnchannels(2)
        output.setsampwidth(2)
        output.setframerate(48000)
        output.writeframes(b"\x00\x00\x00\x00" * (48000 * 12))

    config = write_fixture(temp, wav_path)
    env = {
        **os.environ,
        "QT_QPA_PLATFORM": "offscreen",
        "QT_MULTIMEDIA_PREFERRED_PLUGINS": "ffmpeg",
        "NO_COLOR": "1",
        "QML2_IMPORT_PATH": str(temp / "qmlmodules"),
        "HOME": str(temp),
        "XDG_CONFIG_HOME": str(temp / "config"),
        "XDG_CACHE_HOME": str(temp / "cache"),
        "XDG_DATA_HOME": str(temp / "data"),
    }
    for directory in ("config", "cache", "data"):
        (temp / directory).mkdir()

    result = subprocess.run(
        ["/usr/bin/qs", "--no-duplicate", "--path", str(config)],
        cwd=temp,
        env=env,
        timeout=20,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(result.stdout, end="")
    if result.returncode != 0:
        raise SystemExit(result.returncode)

    lines = result.stdout.splitlines()

    def marker_payload(name: str) -> dict:
        prefix = f"DEBUG qml: {name} "
        for line in lines:
            normalized = line.strip()
            if normalized.startswith(prefix):
                return json.loads(normalized[len(prefix):])
        raise AssertionError(f"missing {name} marker")

    paused = marker_payload("AUDIO_SMOKE_PAUSED")
    resumed = marker_payload("AUDIO_SMOKE_RESUMED")
    seek = marker_payload("AUDIO_SMOKE_SEEK")
    assert any(line.strip() == "DEBUG qml: AUDIO_SMOKE_DONE" for line in lines), result.stdout
    assert paused["position"] > 0, paused
    assert resumed["position"] >= paused["position"], (paused, resumed)
    assert seek["position"] == seek["duration"], seek

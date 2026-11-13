"""Offline Qt smoke tests for the Discordo Voice service.

The fake helper never authenticates or opens a network connection. It exercises
the service's ready queue, connect/browse/select/join/mute/leave/disconnect
flow, stderr diagnostics, typed errors, process failure, cancellation before
startup, and a missing-helper failure.
"""

from pathlib import Path
import json
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
FAKE_HELPER = """#!/usr/bin/python3
import json
import os
import sys

rosters, rosters_plan = [], [["1", "2", "3"], ["1", "3"]]  # ids must be snowflakes; "1" is us


def roster(ids):
    print(json.dumps({"type": "participants", "guild_id": "123", "channel_id": "456",
                      "participants": [{"id": i, "name": i, "self": i == "1"} for i in ids]}),
          flush=True)


print("null", flush=True)
print("[]", flush=True)
print(json.dumps({"type": "ready"}), flush=True)
for line in sys.stdin:
    message = json.loads(line)
    command = message["cmd"]
    ok = True
    if command == "connect":
        print("ordinary dependency diagnostic", file=sys.stderr, flush=True)
        if os.environ.get("FAKE_TYPED_CRASH") == "1":
            print(json.dumps({"type": "error", "message": "Voice device failed."}),
                  flush=True)
            sys.exit(23)
        elif os.environ.get("FAKE_TYPED_ERROR") == "1":
            print(json.dumps({"type": "error", "message": "Voice device failed."}),
                  flush=True)
            ok = False
        elif os.environ.get("FAKE_CRASH") == "1":
            sys.exit(23)
        print(json.dumps({"type": "connection", "state": "connected"}), flush=True)
    elif command == "guilds":
        print(json.dumps({"type": "guilds", "guilds": [
            {"id": "not-a-snowflake", "name": "Discarded"},
            {"id": "123", "name": "Fixture server"}
        ]}), flush=True)
    elif command == "channels":
        print(json.dumps({"type": "channels", "guild_id": "123", "channels": [
            {"id": "bad", "guild_id": "123", "name": "Discarded", "can_join": True},
            {"id": "456", "guild_id": "123", "name": "Fixture voice", "can_join": True}
        ]}), flush=True)
    elif command == "join":
        print(json.dumps({"type": "channel", "guild_id": "123", "channel_id": "456",
                          "name": "Fixture voice", "joined": True}), flush=True)
        print(json.dumps({"type": "voice_settings", "muted": True, "deafened": False}), flush=True)
        if os.environ.get("FAKE_PARTICIPANTS") == "1":
            roster(["1", "2"])
    elif command == "mute":
        print(json.dumps({"type": "voice_settings", "muted": message["muted"],
                          "deafened": False}), flush=True)
        if os.environ.get("FAKE_PARTICIPANTS") == "1":
            rosters.append(None)
            roster(rosters_plan[min(len(rosters) - 1, len(rosters_plan) - 1)])
    elif command == "leave":
        print(json.dumps({"type": "channel", "guild_id": "", "channel_id": "",
                          "joined": False}), flush=True)
    print(json.dumps({"type": "ack", "cmd": command, "ok": ok}), flush=True)
    if command in ("disconnect", "shutdown"):
        break
"""


def run_case(case: str) -> str:
    path = Path(tempfile.mkdtemp(prefix=f"ii-discordo-service-{case}-"))
    for directory in ("services", "modules/common/functions",
                      "home/.local/share/quickshell-ii/bin"):
        (path / directory).mkdir(parents=True, exist_ok=True)

    (path / "services/DiscordoVoiceService.qml").write_text(
        (ROOT / "services/DiscordoVoiceService.qml").read_text())
    (path / "services/HealthService.qml").write_text(
        "pragma Singleton\nimport Quickshell\nSingleton { function openTerminal(args) {} }\n")
    (path / "modules/common/functions/FileUtils.qml").write_text(
        (ROOT / "modules/common/functions/FileUtils.qml").read_text())
    (path / "modules/common/Directories.qml").write_text(
        "pragma Singleton\nimport Quickshell\nSingleton { property string home: "
        + json.dumps((path / "home").as_uri()) + " }\n")
    (path / "modules/common/Config.qml").write_text(
        "pragma Singleton\nimport Quickshell\nSingleton { property var options: ({ discordoVoice: {"
        " pushToTalk: " + ("true" if case == "ptt" else "false") + ", idleDisconnectMinutes: 0,"
        # unmuted_join relies on the default
        + ("" if case == "unmuted_join" else " joinMuted: true,")
        + " joinLeaveSounds: true } }) }\n")
    if case == "ptt":
        # Push to talk lives in Persistent, not Config; the other cases leave it unresolved (not ready)
        (path / "modules/common/Persistent.qml").write_text(
            "pragma Singleton\nimport Quickshell\nSingleton { property bool ready: true;"
            " property var states: ({ discordoVoice: { input: \"\", output: \"\", micGain: 100,"
            " sensitivityDb: -40, videoSyncMs: 80, joinSounds: true, userVolumes: \"{}\","
            " pushToTalk: true } }) }\n")
    (path / "services/SoundService.qml").write_text(
        "pragma Singleton\nimport Quickshell\nSingleton { property int count: 0; property string last: \"\";"
        " function playEvent(category, event) { count++; last = event } }\n")
    (path / "GlobalStates.qml").write_text(
        "pragma Singleton\nimport Quickshell\nSingleton {}\n")

    # The service runs the helper through the broker, resolved against the config root
    (path / "scripts/discordoVoice").mkdir(parents=True, exist_ok=True)
    (path / "scripts/discordoVoice/broker.py").write_text(
        (ROOT / "scripts/discordoVoice/broker.py").read_text())

    if case != "missing":
        helper = path / "home/.local/share/quickshell-ii/bin/discordo-voice-rs"
        helper.write_text(FAKE_HELPER)
        helper.chmod(0o755)

    flow = """if (step === 0 && service.connected && service.guilds.length === 1
        && service.errorMessage.length === 0 && !service.operationBusy) {
        service.requestChannels("123"); step = 1; }
    else if (step === 1 && service.channels.length === 1 && !service.operationBusy) {
        service.join("123", "456"); step = 2; }
    else if (step === 2 && service.joined && !service.operationBusy) {
        service.setMuted(false); step = 3; }
    else if (step === 3 && !service.muted && !service.operationBusy) {
        service.leave(); step = 4; }
    else if (step === 4 && !service.joined && !service.operationBusy) {
        service.disconnect(); step = 5; }
    else if (step === 5 && !service.helperRunning && !service.operationBusy) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "cancel":
        flow = """if (!service.helperRunning && !service.operationBusy
        && !service._startRequested && service._pendingCommands.length === 0) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "missing":
        flow = """if (!service.helperChecking && !service.helperAvailable
        && !service.operationBusy && service._pendingCommands.length === 0) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "typed_error":
        flow = """if (step === 0 && service.connected && !service.operationBusy
        && service.errorMessage === "Voice device failed.") {
        service.disconnect(); step = 1; }
    else if (step === 1 && !service.helperRunning && !service.operationBusy) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "crash":
        flow = """if (!service.helperRunning && service.connectionState === "error"
        && service.errorMessage.indexOf("stopped") >= 0) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "typed_crash":
        flow = """if (!service.helperRunning && service.connectionState === "error"
        && service.errorMessage === "Voice device failed.") {
        console.log("SMOKE_PASS"); Qt.quit(); }"""

    if case == "ptt":
        # Joining mutes the mic (nothing held); holding the key opens it, releasing closes it
        flow = """if (step === 0 && service.connected && service.guilds.length === 1 && !service.operationBusy) {
        service.requestChannels("123"); step = 1; }
    else if (step === 1 && service.channels.length === 1 && !service.operationBusy) {
        service.join("123", "456"); step = 2; }
    else if (step === 2 && service.joined && service.muted) { service.pttHeld = true; step = 3; }
    else if (step === 3 && !service.muted) { service.pttHeld = false; step = 4; }
    else if (step === 4 && service.muted && !service.operationBusy) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "unmuted_join":
        # by default a join we made unmutes once it has settled
        flow = """if (step === 0 && service.connected && service.guilds.length === 1 && !service.operationBusy) {
        service.requestChannels("123"); step = 1; }
    else if (step === 1 && service.channels.length === 1 && !service.operationBusy) {
        service.join("123", "456"); step = 2; }
    else if (step === 2 && service.joined && !service.muted && !service.operationBusy) {
        console.log("SMOKE_PASS"); Qt.quit(); }"""
    if case == "stays_muted":
        flow = """if (step === 0 && service.connected && service.guilds.length === 1 && !service.operationBusy) {
        service.requestChannels("123"); step = 1; }
    else if (step === 1 && service.channels.length === 1 && !service.operationBusy) {
        service.join("123", "456"); step = 2; }
    else if (step === 2 && service.joined && !service.operationBusy) { step = 3; stay.start(); }
    else if (step === 3 && !service.muted) { console.log("SMOKE_FAIL unmuted itself"); Qt.quit(); }"""
    if case == "cues":
        flow = """if (step === 0 && service.connected && service.guilds.length === 1 && !service.operationBusy) {
        service.requestChannels("123"); step = 1; }
    else if (step === 1 && service.channels.length === 1 && !service.operationBusy) {
        service.join("123", "456"); step = 2; }
    else if (step === 2 && service.joined && service.participants.length === 2 && !service.operationBusy) {
        if (SoundService.count !== 0) { console.log("SMOKE_FAIL baseline made a sound"); Qt.quit(); }
        service.setMuted(true); step = 3; }
    else if (step === 3 && service.participants.length === 3 && !service.operationBusy) {
        if (SoundService.count !== 1 || SoundService.last !== "device-added") {
            console.log("SMOKE_FAIL arrival", SoundService.count, SoundService.last); Qt.quit(); }
        service.setMuted(false); step = 4; }
    else if (step === 4 && service.participants.length === 2 && !service.operationBusy) {
        if (SoundService.count !== 2 || SoundService.last !== "device-removed") {
            console.log("SMOKE_FAIL departure", SoundService.count, SoundService.last); Qt.quit(); }
        console.log("SMOKE_PASS"); Qt.quit(); }"""

    action = 'service.connect();' + ('service.disconnect();' if case == "cancel" else "")
    shell = f"""import QtQuick
import Quickshell
import qs.services
ShellRoot {{
    id: root
    readonly property var service: DiscordoVoiceService
    property int step: 0
    Timer {{ interval: 20; running: true; onTriggered: {{ {action} }} }}
    Timer {{ interval: 100; running: true; repeat: true; onTriggered: {{ {flow} }} }}
    Timer {{ id: stay; interval: 1500; onTriggered: {{ if (service.muted) {{ console.log("SMOKE_PASS"); Qt.quit(); }} }} }}
    Timer {{ interval: 5000; running: true; onTriggered: {{
        console.log("SMOKE_FAIL", step, service.connectionState,
                    service.pendingCommand, service.operationBusy);
        service.disconnect(); Qt.quit();
    }} }}
}}"""
    (path / "shell.qml").write_text(shell)

    # Own runtime dir: the broker's socket lives in $XDG_RUNTIME_DIR, and the real one
    # would attach this test to a running helper (and `disconnect` it)
    (path / "run").mkdir(mode=0o700, exist_ok=True)
    test_env = {**os.environ, "QT_QPA_PLATFORM": "offscreen",
                "QT_QUICK_BACKEND": "software", "XDG_CONFIG_HOME": str(path / "config"),
                "XDG_RUNTIME_DIR": str(path / "run")}
    if case == "typed_error":
        test_env["FAKE_TYPED_ERROR"] = "1"
    if case == "typed_crash":
        test_env["FAKE_TYPED_CRASH"] = "1"
    if case == "crash":
        test_env["FAKE_CRASH"] = "1"
    if case == "cues":
        test_env["FAKE_PARTICIPANTS"] = "1"

    result = subprocess.run(
        ["qs", "-p", str(path / "shell.qml")],
        env=test_env,
        capture_output=True, text=True, timeout=8)
    output = result.stdout + result.stderr
    # The broker daemon outlives the shell on purpose; end this case's own one (its socket is
    # in the private runtime dir) so nothing accumulates
    subprocess.run(["python3", "-I", str(path / "scripts/discordoVoice/broker.py"), "stop"],
                   env=test_env, capture_output=True, timeout=10)
    assert "SMOKE_PASS" in output, output
    return output


if __name__ == "__main__":
    for case_name in ("flow", "typed_error", "typed_crash", "crash", "cancel", "missing", "ptt", "cues",
                      "unmuted_join", "stays_muted"):
        run_case(case_name)
    print("ALL_SERVICE_SMOKES_PASS")

"""Run the real Config singleton with isolated files and stub services.

Run with: python3 scripts/tests/run_config_recovery_tests.py
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path


SOURCE = Path(__file__).resolve().parents[2]
ORIGINAL = b'{ "configVersion": 35, "panelFamily": 42, "language": {"ui": "ar"} }\n'


def check(mode):
    with tempfile.TemporaryDirectory(prefix="ii-config-recovery-") as work:
        base = Path(work)
        config = base / "settings" / "config.json"
        config.parent.mkdir()
        shell = base / "shell"
        runtime = base / "runtime"
        runtime.mkdir(mode=0o700)

        def write(path, text):
            target = shell / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)

        def singleton(path, body):
            write(path + ".qml", "pragma Singleton\nimport QtQuick\nQtObject {\n" + body + "\n}")

        singleton("services/Directories", f'''
            property string shellConfigPath: {json.dumps(str(config))}
            property string scriptPath: {json.dumps(str(shell / "scripts"))}
            property string home: "/tmp"
            property string videos: "/tmp"
            property string pictures: "/tmp"
            property string localSendDownloadPath: "/tmp"
            property string userProfileImagePath: "/tmp"
        ''')
        singleton("GlobalStates", "property bool presetWorkDeferred: false; property bool presetHoldMotion: false")
        singleton("modules/common/PanelSchedule", "property bool hold: false")
        singleton("modules/common/Appearance", "property var font: ({ pixelSize: { smaller: 12, larger: 16 } })")
        singleton("modules/common/Persistent", "property bool ready: false")
        singleton("services/HyprlandSettings", "function updateAppLaunchAnimation(value) {}")
        singleton("services/LocalPreferences", "function reconcile() {}\nfunction syncFromConfig() {}")
        singleton("modules/common/functions/FileUtils", "function trimFileProtocol(value) { return value; }")
        for rel in [
            "modules/common/Config.qml",
            "modules/common/quickToggles/androidStyle/QuickToggleCatalog.js",
            "scripts/backup/config_snapshot.py",
        ]:
            (shell / rel).parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(SOURCE / rel, shell / rel)
        write("shell.qml", """
    import QtQuick
    import Quickshell
    import Quickshell.Io
    import qs.modules.common
    ShellRoot {
        Component.onCompleted: {
            Config.missingFileGracePeriod = 250;
            Config.missingFileRetryInterval = 60;
            Config.writeGuardDelay = 50;
        }
        IpcHandler {
            target: "fixture"
            function state(): string {
                return JSON.stringify({ ready: Config.ready, language: Config.options.language.ui, health: Config.configHealthState });
            }
            function save(): void { Config.saveOptionsNow(); }
        }
    }
    """)
        env = dict(
            os.environ, QT_QPA_PLATFORM="offscreen", XDG_RUNTIME_DIR=str(runtime),
            XDG_CONFIG_HOME=work, XDG_STATE_HOME=work, XDG_CACHE_HOME=work,
            NOTIFY_SOCKET="",
        )
        fake_bin = base / "bin"
        fake_bin.mkdir()
        notify = fake_bin / "notify-send"
        notify.write_text("#!/bin/sh\nexit 0\n")
        notify.chmod(0o755)
        env["PATH"] = str(fake_bin) + ":" + env["PATH"]
        env.pop("WAYLAND_DISPLAY", None)
        qs = ["qs", "--log-rules", "quickshell.io.fileview.debug=true", "-p", str(shell)]
        backup = config.with_suffix(".json.bak")
        if mode in ("backup-failure", "success"):
            config.write_bytes(ORIGINAL)
            config.chmod(0o600)
        if mode == "backup-failure":
            backup.mkdir()
        if mode in ("missing", "incoming"):
            config.write_text('{"configVersion":35,"language":{"ui":"ar"}}')
        log = base / "output"
        with log.open("w") as output:
            proc = subprocess.Popen(qs, env=env, stdout=output, stderr=output)
            try:
                def rpc(action):
                    reply = subprocess.run(
                        [*qs, "ipc", "call", "fixture", action], env=env,
                        capture_output=True, text=True, timeout=3,
                    )
                    if action == "state" and reply.returncode == 0 and reply.stdout.lstrip().startswith("{"):
                        return json.loads(reply.stdout)
                    return None
                deadline = time.monotonic() + 8
                while time.monotonic() < deadline:
                    if proc.poll() is not None:
                        raise AssertionError("fixture shell exited")
                    state = rpc("state")
                    if state and state["ready"]:
                        break
                    time.sleep(0.05)
                else:
                    raise AssertionError("fixture did not become ready")
                time.sleep(0.4)
                if mode == "backup-failure":
                    assert config.read_bytes() == ORIGINAL, "repair rewrote config after backup failed"
                    rpc("save")
                    time.sleep(0.15)
                    assert config.read_bytes() == ORIGINAL, "forced save rewrote the unbacked config"
                if mode == "incoming":
                    backup.mkdir()
                    config.write_bytes(ORIGINAL)
                    time.sleep(0.25)
                    assert rpc("state")["health"] == "backupFailed"
                    rpc("save")
                    assert config.read_bytes() == ORIGINAL
                    backup.rmdir()
                    config.write_bytes(ORIGINAL + b" ")
                    time.sleep(0.35)
                    assert backup.read_bytes() == ORIGINAL + b" "
                    assert json.loads(config.read_bytes())["panelFamily"] == "ii"
                if mode == "success":
                    assert backup.read_bytes() == ORIGINAL
                    assert backup.stat().st_mode & 0o777 == 0o600
                    assert json.loads(config.read_bytes())["panelFamily"] == "ii"
                if mode == "missing":
                    config.unlink()
                    time.sleep(0.7)
                    before = log.read_text().count(f'Reader started for "{config}"')
                    time.sleep(0.35)
                    after = log.read_text().count(f'Reader started for "{config}"')
                    assert after == before, f"missing-file retries continued ({before} -> {after})"
                    assert rpc("state")["language"] == "ar"
                    rpc("save")
                    assert not config.exists()
                    config.write_text('{"configVersion":35,"language":{"ui":"pt_BR"}}')
                    time.sleep(0.35)
                    assert rpc("state")["language"] == "pt_BR"
                if mode == "first-run":
                    assert json.loads(config.read_bytes())["configVersion"] == 35
                print(f"{mode} passed")
            except Exception:
                print(log.read_text()[-4000:], file=sys.stderr)
                raise
            finally:
                proc.terminate()
                proc.wait(timeout=5)


if __name__ == "__main__":
    for scenario in ("backup-failure", "success", "missing", "first-run", "incoming"):
        check(scenario)

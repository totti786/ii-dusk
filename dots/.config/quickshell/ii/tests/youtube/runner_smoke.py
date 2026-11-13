"""Exercise the production YouTube Process runner in isolated offscreen Quickshell.

The fixture extracts the runner component verbatim, then drives success, failed-start,
and timeout cases with synthetic commands. It never calls yt-dlp, mpv, or a network URL.
"""

from collections import Counter
from pathlib import Path
import json
import os
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[2]
SERVICE = (ROOT / "services/YouTubeService.qml").read_text()


def extract_runner_component(source: str) -> str:
    start = source.index("    Component {\n        id: runnerComponent")
    open_brace = source.index("{", start)
    depth = 0
    in_string = False
    quote = ""
    escaped = False
    for index in range(open_brace, len(source)):
        char = source[index]
        if in_string:
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == quote:
                in_string = False
            continue
        if char in "'\"":
            in_string = True
            quote = char
        elif char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return source[start:index + 1]
    raise AssertionError("runnerComponent is not closed")


runner_component = extract_runner_component(SERVICE)
CONFIG_TEMPLATE = """import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property int caseIndex: 0
    property var _activeRunners: []
    property var cases: [
        { label: "success", command: ["sh", "-c", "printf synthetic-output"], timeout: 1000 },
        { label: "failed-start", command: ["/definitely/missing/yt-dlp"], timeout: 100 },
        { label: "timeout", command: ["sh", "-c", "sleep 2"], timeout: 100 }
    ]

    function _forgetRunner(runner): void {
        root._activeRunners = root._activeRunners.filter(item => item !== runner);
    }

    Component.onCompleted: Qt.callLater(() => root.runCase())

    function runCase(): void {
        if (root.caseIndex >= root.cases.length) {
            Qt.quit();
            return;
        }
        const entry = root.cases[root.caseIndex];
        const runner = runnerComponent.createObject(root, {
            "command": entry.command,
            "handler": (out, errText, code, timedOut) => {
                const result = {
                    label: entry.label,
                    code: code,
                    timedOut: timedOut,
                    output: String(out ?? ""),
                    handlerCleared: runner.handler === null,
                    removed: root._activeRunners.indexOf(runner) === -1,
                    retired: runner.retired
                };
                console.log("YOUTUBE_RUNNER_RESULT", JSON.stringify(result));
                root.caseIndex++;
                Qt.callLater(() => root.runCase());
            },
            "kind": entry.label,
            "timeoutMs": entry.timeout,
            "requestToken": root.caseIndex
        });
        const runners = root._activeRunners.slice();
        runners.push(runner);
        root._activeRunners = runners;
        runner.running = true;
    }

""" + runner_component + "\n}\n"


with tempfile.TemporaryDirectory(prefix="ii-youtube-runner-smoke-") as temp_name:
    out = Path(temp_name)
    config = out / "runner.qml"
    config.write_text(CONFIG_TEMPLATE)
    result = subprocess.run(
        ["/usr/bin/quickshell", "--no-duplicate", "--path", str(config)],
        cwd=out,
        env={**os.environ, "QT_QPA_PLATFORM": "offscreen", "NO_COLOR": "1"},
        timeout=10,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )
    print(result.stdout, end="")
    if result.returncode != 0:
        raise SystemExit(result.returncode)

    marker = "YOUTUBE_RUNNER_RESULT "
    results = [
        json.loads(line.split(marker, 1)[1])
        for line in result.stdout.splitlines()
        if marker in line
    ]
    assert len(results) == 3, results
    assert Counter(item["label"] for item in results) == {
        "success": 1,
        "failed-start": 1,
        "timeout": 1,
    }, results
    by_label = {item["label"]: item for item in results}
    assert (by_label["success"]["code"], by_label["success"]["timedOut"], by_label["success"]["output"]) == (
        0,
        False,
        "synthetic-output",
    ), by_label["success"]
    for label in ("failed-start", "timeout"):
        item = by_label[label]
        assert item["code"] == -1 and item["timedOut"] is True, item
    for item in results:
        assert item["handlerCleared"] is True, item
        assert item["removed"] is True, item
        assert item["retired"] is True, item

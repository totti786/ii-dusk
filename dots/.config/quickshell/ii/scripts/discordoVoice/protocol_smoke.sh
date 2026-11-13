#!/usr/bin/env bash
set -euo pipefail

helper="${1:-${HOME}/.local/share/quickshell-ii/bin/discordo-voice}"
if [[ ! -x "${helper}" ]]; then
    printf 'Discordo Voice helper is missing: %s\n' "${helper}" >&2
    exit 2
fi

python3 - "${helper}" <<'PY'
import json
import subprocess
import sys

helper = sys.argv[1]
process = subprocess.Popen(
    [helper],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)

events = []

def read_until(predicate):
    while True:
        line = process.stdout.readline()
        if not line:
            raise AssertionError(f"helper exited before expected event: {events}")
        event = json.loads(line)
        events.append(event)
        if predicate(event):
            return

read_until(lambda event: event.get("type") == "ready")
process.stdin.write('{"cmd":"guilds"}\n')
process.stdin.flush()
read_until(lambda event: event.get("type") == "ack" and event.get("cmd") == "guilds")
process.stdin.write('{"cmd":"shutdown"}\n')
process.stdin.flush()
read_until(lambda event: event.get("type") == "ack" and event.get("cmd") == "shutdown")
process.stdin.close()
process.wait(timeout=5)
if process.returncode != 0:
    raise AssertionError(f"helper exited with {process.returncode}: {events}")

raw = "\n".join(json.dumps(event) for event in events)
types = [event.get("type") for event in events]
assert types[0] == "ready", types
assert any(event.get("type") == "ack" and event.get("cmd") == "guilds" and not event.get("ok") for event in events), events
assert any(event.get("type") == "ack" and event.get("cmd") == "shutdown" and event.get("ok") for event in events), events
assert "token" not in raw.lower(), "credential text on stdout"
PY
printf 'Discordo Voice protocol smoke passed\n'

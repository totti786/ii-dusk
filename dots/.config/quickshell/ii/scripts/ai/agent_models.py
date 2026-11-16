#!/usr/bin/env python3
"""Discover subscription model pickers through the CLIs, without inference."""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import selectors
import shutil
import signal
import subprocess
import tempfile
import time

import agent_bridge as bridge


def query(argv, first, consume, cwd=None):
    """Read JSONL without TextIO buffering hiding a second ready response."""
    process = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.DEVNULL, env=bridge.environment(),
                               cwd=cwd, start_new_session=True)
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    def send(row):
        process.stdin.write((json.dumps(row) + "\n").encode())
        process.stdin.flush()
    try:
        send(first)
        pending = b""
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            if not selector.select(.2):
                continue
            chunk = os.read(process.stdout.fileno(), 65536)
            if not chunk:
                break
            pending += chunk
            while b"\n" in pending:
                line, pending = pending.split(b"\n", 1)
                try:
                    row = json.loads(line)
                except ValueError:
                    continue
                result = consume(row, send)
                if result is not None:
                    return result
        raise RuntimeError("Model discovery did not complete.")
    finally:
        selector.close()
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        except ProcessLookupError:
            pass
        process.stdin.close()
        process.stdout.close()


def codex_entries(data):
    rows = [m for m in data.get("data", []) if not m.get("hidden") and m.get("model")]
    default = next((m for m in rows if m.get("isDefault")), None)
    entries = [{"value": "default", "title": "Default" + (" · " + default["displayName"] if default else ""),
                "description": "Follow Codex's recommended model", "vision": "image" in default.get("inputModalities", []) if default else True}]
    for model in rows:
        entries.append({"value": model["model"], "title": model.get("displayName") or model["model"],
                        "description": model.get("description", ""), "vision": "image" in model.get("inputModalities", [])})
    return entries


def claude_entries(data):
    entries = []
    for model in data.get("models", []):
        value = model.get("value")
        if not value:
            continue
        title = model.get("displayName") or value
        if value == "default":
            title = "Default · " + str(model.get("description") or model.get("resolvedModel") or "Claude Code")
        entries.append({"value": value, "title": title, "description": model.get("description", ""),
                        "resolvedModel": model.get("resolvedModel", value)})
    return entries


def discover(engine):
    if engine == "codex":
        collected = []
        def consume(row, send):
            if row.get("id") == 1:
                if "error" in row:
                    raise RuntimeError("Codex initialization failed.")
                send({"method": "initialized"})
                send({"id": 2, "method": "model/list", "params": {}})
            elif row.get("id") == 2:
                if "error" in row:
                    raise RuntimeError("Codex model list unavailable.")
                page = row["result"]
                collected.extend(page.get("data", []))
                if page.get("nextCursor"):
                    send({"id": 2, "method": "model/list", "params": {"cursor": page["nextCursor"]}})
                else:
                    return codex_entries({"data": collected})
        return query(["codex", "--no-daemon", "app-server"],
                     {"id": 1, "method": "initialize", "params": {"clientInfo": {"name": "quickshell-model-picker", "version": "1.0"}}}, consume)
    def consume(row, send):
        if row.get("type") == "control_response" and row.get("response", {}).get("request_id") == "models":
            return claude_entries(row["response"].get("response", {}))
    with tempfile.TemporaryDirectory(prefix="ii-models-") as tmp:
        return query(bridge.command("claude", {"tools": []}, Path(tmp)),
                     {"type": "control_request", "request_id": "models", "request": {"subtype": "initialize"}}, consume, cwd=tmp)


def cached(engine):
    binary = shutil.which(engine)
    if not binary:
        return []
    path = bridge.STATE / (engine + "-models.json")
    previous = {}
    try:
        value = json.loads(path.read_text())
        previous = value if isinstance(value, dict) else {}
        if time.time() - previous.get("updated", 0) < 600 and previous.get("binaryMtime") == os.stat(binary).st_mtime:
            return previous["models"]
    except (OSError, ValueError, KeyError):
        pass
    try:
        models = discover(engine)
        if not models:
            return previous.get("models", [])
        path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as temp:
            json.dump({"updated": time.time(), "binaryMtime": os.stat(binary).st_mtime, "models": models}, temp)
            temporary = Path(temp.name)
        temporary.replace(path)
        return models
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.SubprocessError):
        return previous.get("models", [])


def list_models():
    with ThreadPoolExecutor(max_workers=2) as pool:
        return dict(zip(("codex", "claude"), pool.map(cached, ("codex", "claude"))))

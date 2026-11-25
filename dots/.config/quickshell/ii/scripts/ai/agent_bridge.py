#!/usr/bin/env python3
"""One stream contract for signed-in Codex, Claude Code and OpenCode.

The CLIs own authentication. No token copying, API-key entry or HTTP emulation.
QuickShell owns conversation history; CLI turns are ephemeral. All desktop
actions use the same scoped MCP tools and approval cards as OpenCode.
"""
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import signal
import subprocess
import sys
import time
import uuid

import opencode_bridge as oc

HERE = Path(__file__).resolve().parent
STATE = Path(os.environ.get("XDG_STATE_HOME", Path.home()/".local/state")) / "quickshell/user/ai"
RUNS = STATE / "agent-runs"


def emit(kind, data=None):
    print(json.dumps({"type": kind, "data": data or {}}, ensure_ascii=False), flush=True)


def environment():
    env = os.environ.copy()
    for key in ("OPENAI_API_KEY", "ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
                "CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "ANTHROPIC_BASE_URL", "CLAUDE_CODE_USE_BEDROCK", "CLAUDE_CODE_USE_VERTEX"):
        env.pop(key, None)
    return env


def status():
    result = []
    for engine, command in (("codex", ["codex", "login", "status"]), ("claude", ["claude", "auth", "status"])):
        binary = shutil.which(command[0])
        entry = {"id": engine, "installed": bool(binary), "signedIn": False,
                 "signInCommand": "codex login" if engine == "codex" else "claude auth login"}
        if binary:
            try:
                reply = subprocess.run(command, capture_output=True, text=True, env=environment(), timeout=5)
                if engine == "claude":
                    info = json.loads(reply.stdout)
                    entry["signedIn"] = info.get("loggedIn") is True and info.get("authMethod") == "claude.ai"
                else:
                    entry["signedIn"] = reply.returncode == 0 and "chatgpt" in (reply.stdout+reply.stderr).lower()
            except (OSError, ValueError, subprocess.TimeoutExpired): pass
        result.append(entry)
    try:
        binary = oc.opencode_binary()
    except oc.BridgeError:
        binary = None
    result.append({"id": "opencode", "installed": bool(binary), "signedIn": bool(oc.list_models()) if binary else False,
                   "signInCommand": "opencode auth login"})
    return result


def answer(session, request, decision):
    if not session.startswith("agent_"):
        return oc.decide_permission(session, request, decision)
    if not re.fullmatch(r"agent_[0-9a-f]{32}", session) or not re.fullmatch(r"req_[0-9a-f]{32}", request):
        raise ValueError("Invalid agent approval id.")
    if decision not in ("once", "reject"): raise ValueError("Invalid decision.")
    directory = RUNS / session
    if not directory.is_dir(): raise ValueError("That agent turn has already ended.")
    path = directory / (request + ".json")
    temporary = path.with_suffix(".tmp")
    temporary.write_text(json.dumps({"decision": decision}))
    temporary.chmod(0o600)
    temporary.replace(path)


def command(engine, body, directory):
    model = str(body.get("model", {}).get("modelID", "default"))
    guide = str(body.get("instructions", "")) + "\n\n" + oc.TOOLS_GUIDE
    (directory / "instructions.txt").write_text(guide)
    request_path = str(directory / "request.json")
    mcp_env = {**oc.desktop_environment(), "II_AGENT_REQUEST": request_path}
    tools = body.get("tools", [])
    if engine == "codex":
        argv = ["codex", "--no-daemon", "exec", "--json", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                "--sandbox", "read-only", "--skip-git-repo-check", "-C", str(STATE / "agent-workspace")]
        settings = {"features.shell_tool": False, "features.apps": False, "features.plugins": False,
                    "features.multi_agent": False, "features.skip_host_skill_discovery": True,
                    "features.skill_search": False, "features.browser_use": False, "features.computer_use": False,
                    "approval_policy": "never", "suppress_unstable_features_warning": True,
                    "developer_instructions": guide}
        if tools:
            settings.update({"mcp_servers.ii-shell.command": sys.executable,
                "mcp_servers.ii-shell.args": [str(HERE / "agent_tools_mcp.py")],
                "mcp_servers.ii-shell.startup_timeout_sec": 15,
                "mcp_servers.ii-shell.default_tools_approval_mode": "approve",
                "mcp_servers.ii-shell.tool_timeout_sec": 660})
            settings.update({"mcp_servers.ii-shell.env." + key: value for key, value in mcp_env.items()})
        for key, value in settings.items(): argv += ["-c", key + "=" + json.dumps(value, ensure_ascii=False)]
        if model != "default": argv += ["--model", model]
        for item in body.get("files", []):
            if item.get("kind") == "image" and Path(item.get("path", "")).is_file():
                argv += ["--image", item["path"]]
        argv.append("-")
        return argv
    config = {"mcpServers": {"ii-shell": {"command": sys.executable, "args": [str(HERE / "agent_tools_mcp.py")],
                                          "env": mcp_env}}} if tools else {"mcpServers": {}}
    (directory / "mcp.json").write_text(json.dumps(config))
    argv = ["claude", "-p", "--output-format", "stream-json", "--input-format", "stream-json",
            "--verbose", "--include-partial-messages", "--tools", "", "--strict-mcp-config",
            "--mcp-config", str(directory / "mcp.json"), "--setting-sources", "", "--disable-slash-commands",
            "--no-session-persistence", "--permission-mode", "bypassPermissions",
            "--system-prompt-file", str(directory / "instructions.txt")]
    if model != "default": argv += ["--model", model]
    return argv


def prompt(body, engine):
    extra, images = oc.attachment_parts(body.get("files", []), body.get("attachmentTextBudget"), str(body.get("text", "")))
    text = oc.with_transcript(body.get("prior", []), str(body.get("text", "")))
    text += str(body.get("context", "")) + ("\n\n" + extra if extra else "")
    if engine == "codex": return text
    content = [{"type": "text", "text": text}]
    for item in images:
        header, encoded = item["uri"].split(",", 1)
        content.append({"type": "image", "source": {"type": "base64", "media_type": header[5:].split(";")[0], "data": encoded}})
    return json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n"


class Stream:
    def __init__(self, engine):
        self.engine = engine
        self.text = False
        self.answer = ""
        self.failed = ""
        self.completed = False

    def consume(self, event):
        kind = event.get("type")
        if self.engine == "codex":
            item = event.get("item", {})
            if kind == "item.completed" and item.get("type") == "agent_message":
                self.answer += ("\n\n" if self.text else "") + item.get("text", "")
                emit("session.text.delta", {"delta": ("\n\n" if self.text else "") + item.get("text", "")}); self.text = True
            elif kind == "item.completed" and item.get("type") == "reasoning":
                emit("session.reasoning.delta", {"delta": item.get("text", "")})
            elif kind == "turn.completed":
                self.completed = True
                usage = event.get("usage", {})
                emit("session.step.ended", {"tokens": {"input": usage.get("input_tokens", 0), "output": usage.get("output_tokens", 0)}})
            elif kind in ("turn.failed", "error"):
                error = event.get("error", {})
                self.failed = error.get("message", "") if isinstance(error, dict) else str(error)
                self.failed = self.failed or event.get("message", "Codex could not complete this turn.")
        elif kind == "stream_event" and event.get("parent_tool_use_id") is None:
            part = event.get("event", {})
            delta = part.get("delta", {})
            if part.get("type") == "content_block_delta" and delta.get("type") == "text_delta":
                self.answer += delta.get("text", "")
                emit("session.text.delta", {"delta": delta.get("text", "")}); self.text = True
            elif delta.get("type") == "thinking_delta":
                emit("session.reasoning.delta", {"delta": delta.get("thinking", "")})
        elif kind == "result":
            self.completed = not event.get("is_error", False)
            if event.get("is_error"): self.failed = str(event.get("result") or "; ".join(event.get("errors", [])) or "Claude could not complete this turn.")
            if not self.text and event.get("result") and not event.get("is_error"):
                self.answer += event["result"]
                emit("session.text.delta", {"delta": event["result"]}); self.text = True
            usage = event.get("usage", {})
            emit("session.step.ended", {"tokens": {"input": usage.get("input_tokens", 0), "output": usage.get("output_tokens", 0)}})


def run(body_path, marker, state_path):
    body = json.loads(Path(body_path).read_text())
    import agent_memory
    if body.get("learningReview") and not agent_memory.online_policy_allowed():
        raise RuntimeError("Online AI is disabled.")
    body["contextOverheadChars"] = len(oc.TOOLS_GUIDE.encode("utf-8"))
    body = agent_memory.prepare(body)
    engine = body.get("engine", "opencode")
    if engine == "opencode":
        import tempfile
        # The OpenCode bridge owns server state; give it the same prepared
        # prompt as the native CLIs without overwriting the canonical request.
        with tempfile.NamedTemporaryFile(mode="w", suffix=".json") as request:
            json.dump(body, request); request.flush()
            return oc.run_turn(request.name, marker, state_path)
    if engine not in ("codex", "claude"): raise ValueError("Unknown agent backend.")
    if not shutil.which(engine): raise RuntimeError(f"{engine} is not installed. Install it and sign in first.")
    RUNS.mkdir(parents=True, exist_ok=True)
    RUNS.chmod(0o700)
    (STATE / "agent-workspace").mkdir(parents=True, exist_ok=True)
    directory = RUNS / ("agent_" + uuid.uuid4().hex)
    directory.mkdir(mode=0o700)
    body["tools"] = [name for name in body.get("tools", []) if name in oc.SHELL_TOOLS]
    (directory / "request.json").write_text(json.dumps(body))
    process = None
    old_handler = signal.getsignal(signal.SIGTERM)
    def cancel(*_):
        if process is not None and process.poll() is None:
            os.killpg(process.pid, signal.SIGTERM)
        raise SystemExit(0)
    signal.signal(signal.SIGTERM, cancel)
    stream = Stream(engine)
    try:
        with (directory / "stderr.log").open("w+") as errors:
            process = subprocess.Popen(command(engine, body, directory), cwd=STATE / "agent-workspace", env=environment(),
                                       stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
                                       text=True, bufsize=1, start_new_session=True)
            process.stdin.write(prompt(body, engine)); process.stdin.close()
            selector = selectors.DefaultSelector(); selector.register(process.stdout, selectors.EVENT_READ)
            event_offset = 0
            def drain():
                nonlocal event_offset
                path = directory / "events.jsonl"
                if not path.exists(): return
                with path.open() as source:
                    source.seek(event_offset)
                    while True:
                        before = source.tell(); line = source.readline()
                        if not line or not line.endswith("\n"): source.seek(before); break
                        print(line.rstrip(), flush=True)
                    event_offset = source.tell()
            deadline = time.monotonic() + 1800
            while time.monotonic() < deadline:
                drain()
                if selector.select(.1):
                    line = process.stdout.readline()
                    if line:
                        try: stream.consume(json.loads(line))
                        except ValueError: pass
                    elif process.poll() is not None: break
                elif process.poll() is not None:
                    for line in process.stdout:
                        try: stream.consume(json.loads(line))
                        except ValueError: pass
                    break
            else:
                os.killpg(process.pid, signal.SIGTERM)
                stream.failed = "The agent timed out."
            process.wait(timeout=10); drain(); selector.close(); process.stdout.close()
            if process.returncode or stream.failed or not stream.completed:
                errors.seek(0)
                detail = stream.failed or errors.read()[-1600:] or f"{engine} exited before completing. Sign in with its CLI and try again."
                import agent_learning
                agent_learning.from_file(body, stream.answer, directory / "events.jsonl", completed=False)
                emit("session.execution.failed", {"error": {"message": detail}})
                print(marker + "200", flush=True)
                return 0
        import agent_learning
        agent_learning.from_file(body, stream.answer, directory / "events.jsonl")
        emit("session.execution.succeeded")
        print(marker + "200", flush=True)
        return 0
    finally:
        signal.signal(signal.SIGTERM, old_handler)
        if process is not None:
            try: os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError: pass
            try: process.wait(timeout=3)
            except subprocess.TimeoutExpired:
                try: os.killpg(process.pid, signal.SIGKILL)
                except ProcessLookupError: pass
        shutil.rmtree(directory, ignore_errors=True)


def main():
    if sys.argv[1:] == ["status"]:
        print(json.dumps(status())); return 0
    try:
        if len(sys.argv) == 5 and sys.argv[1] == "turn": return run(*sys.argv[2:])
        if len(sys.argv) == 5 and sys.argv[1] == "answer": answer(*sys.argv[2:]); return 0
        raise ValueError("Usage: agent_bridge.py status | turn BODY MARKER STATE | answer SESSION REQUEST once|reject")
    except Exception as error:
        if len(sys.argv) > 1 and sys.argv[1] == "turn":
            emit("session.execution.failed", {"error": {"message": str(error)}})
            print(sys.argv[3] + "200", flush=True)
            return 0
        print(str(error), file=sys.stderr); return 7


if __name__ == "__main__": raise SystemExit(main())

#!/usr/bin/env python3
"""The existing shell tools, scoped and approved for one signed-in CLI turn."""
import json
import os
from pathlib import Path
import time
import uuid

import opencode_bridge as policy
import shell_tools_mcp as mcp


def event(directory, kind, data):
    payload = json.dumps({"type": kind, "data": data}, ensure_ascii=False) + "\n"
    fd = os.open(directory / "events.jsonl", os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o600)
    try: os.write(fd, payload.encode())
    finally: os.close(fd)


def approved(directory, request, name, arguments, call_id):
    effect = policy.tool_effect(name, request.get("auto") is True, request.get("configWrites") is not False)
    if effect == "allow": return True
    ident = "req_" + uuid.uuid4().hex
    event(directory, "permission.asked", {"id": ident, "sessionID": directory.name,
        "action": "ii-shell_" + name, "metadata": {"input": arguments},
        "source": {"id": call_id}})
    answer = directory / (ident + ".json")
    deadline = time.monotonic() + 600
    while time.monotonic() < deadline:
        try:
            decision = json.loads(answer.read_text()).get("decision")
            allowed = decision == "once"
            event(directory, "permission.replied", {"requestID": ident, "reply": "once" if allowed else "reject"})
            return allowed
        except (OSError, ValueError): time.sleep(.15)
    return False


def main():
    directory = Path(os.environ["II_AGENT_REQUEST"]).resolve().parent
    request = json.loads((directory / "request.json").read_text())
    os.environ["II_AGENT_PROJECT"] = str(request.get("projectId", ""))
    mcp.LEARNING_REVIEW = {key: request.get(key) for key in ("learningReview", "learningJob", "learningVerified", "learningEvidence", "learningRequest")}
    enabled = set(request.get("tools", [])) & mcp.TOOL_NAMES
    mcp.TOOLS = [tool for tool in mcp.TOOLS if tool["name"] in enabled]
    mcp.TOOL_NAMES = enabled
    mcp.MODE_FILE = str(directory / "mode.json")
    (directory / "mode.json").write_text(json.dumps({"auto": request.get("auto") is True}))
    execute = mcp.call_tool
    def call(name, arguments):
        if name not in enabled: return mcp.fail("This tool is disabled for the current request.")
        ident = "call_" + uuid.uuid4().hex
        event(directory, "session.tool.input.started", {"id": ident, "name": "ii-shell_" + name})
        event(directory, "session.tool.called", {"id": ident, "input": arguments})
        if not approved(directory, request, name, arguments, ident):
            result = mcp.fail("The user did not approve this action.")
        else:
            try: result = execute(name, arguments)
            except Exception as error: result = mcp.fail(str(error))
        failed = bool(result.get("isError"))
        event(directory, "session.tool.failed" if failed else "session.tool.success", {
            "id": ident, "content": [{"type": "text", "text": result.get("text", "")}],
            "error": {"message": result.get("text", "")} if failed else None})
        return result
    mcp.call_tool = call
    return mcp.main()


if __name__ == "__main__": raise SystemExit(main())

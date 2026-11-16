#!/usr/bin/env python3
"""Consolidated boot-time index for the Ai service.

Returns a single JSON document combining:

  - signed-in Codex and Claude model choices (cached CLI discovery)
  - models of a running local OpenCode server (never started here)
  - default prompt file names (.md/.txt) under the repo's defaults/ai/prompts
  - user prompt file names (.md/.txt) under the user's ai/prompts

Chats are not listed here any more: they live in the session store, which
`ai_sessions.py` owns.

Usage:
    ai_index.py DEFAULT_PROMPTS_DIR USER_PROMPTS_DIR

Output (one JSON object on stdout):
    {
        "agent_models": {"codex": [...], "claude": [...]},
        "opencode_models": [{"providerID": "opencode-go", "modelID": "...", ...}, ...],
        "default_prompts": ["/abs/path/p1.md", ...],
        "user_prompts":    ["/abs/path/u1.md", ...]
    }
"""

import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))


def list_files(directory: str, suffixes: tuple[str, ...]) -> list[str]:
    if not directory or not os.path.isdir(directory):
        return []
    out: list[str] = []
    try:
        for name in sorted(os.listdir(directory)):
            if any(name.endswith(suf) for suf in suffixes):
                out.append(os.path.join(directory, name))
    except OSError:
        pass
    return out


def list_opencode_models() -> list[dict]:
    # Asks only a server that is already running; starting one is the bridge's job, on a chat turn.
    try:
        import opencode_bridge

        return opencode_bridge.list_models()
    except Exception:
        return []


def main() -> int:
    argv = sys.argv[1:]

    if len(argv) < 2:
        print(
            json.dumps(
                {
                    "agent_models": {},
                    "opencode_models": [],
                    "default_prompts": [],
                    "user_prompts": [],
                }
            )
        )
        return 0

    default_dir, user_dir = argv[0], argv[1]
    payload = {
        "agents": __import__("agent_bridge").status(),
        "agent_models": __import__("agent_models").list_models(),
        "opencode_models": list_opencode_models(),
        "default_prompts": list_files(default_dir, (".md", ".txt")),
        "user_prompts": list_files(user_dir, (".md", ".txt")),
    }
    print(json.dumps(payload))
    return 0


if __name__ == "__main__":
    sys.exit(main())

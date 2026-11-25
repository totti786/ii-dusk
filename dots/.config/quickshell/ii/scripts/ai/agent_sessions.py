#!/usr/bin/env python3
"""One list of the coding-agent sessions running on this machine, and a few things to do with them.

The voice orb uses this to know what Claude Code, Codex and OpenCode are up to, report it, and
(with a spoken yes) steer them. Nothing here talks to a model: it reads what each tool already
records and calls the local server OpenCode already runs.

    agent_sessions.py list [--all]            JSON: [{tool, id, name, cwd, status, ...}]
    agent_sessions.py detail <tool> <id>      JSON: the same plus the last few messages
    agent_sessions.py send <tool> <id> <text> steer a session (OpenCode; Claude Code by typing into its terminal)
    agent_sessions.py interrupt <tool> <id>   stop what it is doing (OpenCode, Claude Code)
    agent_sessions.py focus <tool> <id>       bring its terminal window to the front (Claude Code)
    agent_sessions.py resolve <tool> [hint]   which session a request means

Sources:
  Claude Code  ~/.claude/sessions/<pid>.json (one per live process: status, name, cwd) and the
               transcript under ~/.claude/projects/ for the title and the last exchange.
  Codex        the newest rollout files under ~/.codex/sessions/ (started/complete events say
               whether a turn is running).
  OpenCode     the local server (`GET /api/session`), through opencode_bridge's connection.

status is one of: working, idle, waiting (needs you). A session nothing has touched for a day
is left out unless --all.
"""
import glob
import json
import os
import sys
import time

HOME = os.path.expanduser("~")
DAY_MS = 24 * 3600 * 1000
TAIL_BYTES = 192 * 1024
IDLE_MS = 3 * 3600 * 1000      # an idle session older than this is not worth mentioning


def now_ms():
    return int(time.time() * 1000)


def tail_lines(path, size=TAIL_BYTES):
    """The last records of a JSONL file, oldest first, without reading all of it."""
    try:
        with open(path, "rb") as handle:
            handle.seek(0, os.SEEK_END)
            end = handle.tell()
            handle.seek(max(0, end - size))
            data = handle.read().decode("utf-8", "replace")
    except OSError:
        return []
    lines = data.split("\n")
    if end > size:
        lines = lines[1:]            # the first line is cut in half
    out = []
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            out.append(json.loads(line))
        except ValueError:
            continue
    return out


def clip(text, limit=220):
    text = " ".join(str(text or "").split())
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except (OSError, ValueError):
        return False


# ── Claude Code ──────────────────────────────────────────────────────────────

def claude_text(content):
    if isinstance(content, str):
        return content
    parts = []
    for block in content or []:
        if isinstance(block, dict) and block.get("type") == "text":
            parts.append(block.get("text", ""))
    return "\n".join(parts)


def claude_transcript(session_id, cwd):
    folder = cwd.replace("/", "-").replace(".", "-")
    path = os.path.join(HOME, ".claude", "projects", folder, session_id + ".jsonl")
    if not os.path.exists(path):
        found = glob.glob(os.path.join(HOME, ".claude", "projects", "*", session_id + ".jsonl"))
        path = found[0] if found else ""
    return path


def entry_time(entry):
    """Seconds since the epoch of a transcript record, or 0."""
    stamp = str(entry.get("timestamp") or "")
    try:
        return time.mktime(time.strptime(stamp[:19], "%Y-%m-%dT%H:%M:%S")) - time.timezone
    except ValueError:
        return 0.0


def claude_sessions(include_all=False):
    out = []
    for path in glob.glob(os.path.join(HOME, ".claude", "sessions", "*.json")):
        try:
            with open(path) as handle:
                record = json.load(handle)
        except (OSError, ValueError):
            continue
        pid = record.get("pid")
        if not pid or not alive(pid):
            continue
        # The orb's own warm helper and other headless runs are not sessions a person is in.
        if record.get("entrypoint") not in ("cli", None) or record.get("kind") != "interactive":
            continue
        session_id = str(record.get("sessionId", ""))
        cwd = str(record.get("cwd", ""))
        title, prompt, answer = "", "", ""
        pending_tool, pending_at = "", 0.0
        asked_in_text = False
        transcript = claude_transcript(session_id, cwd)
        for entry in tail_lines(transcript, 2 * 1024 * 1024) if transcript else []:
            kind = entry.get("type")
            if kind == "ai-title":
                title = str(entry.get("aiTitle") or entry.get("title") or title)
            elif kind == "user" and not entry.get("isMeta"):
                text = claude_text((entry.get("message") or {}).get("content"))
                if text.strip() and not text.lstrip().startswith("<"):
                    prompt = text
            elif kind == "assistant":
                content = (entry.get("message") or {}).get("content")
                text = claude_text(content)
                if text.strip():
                    answer = text
                    asked_in_text = text.rstrip().endswith("?")
                tools = [b for b in content or [] if isinstance(b, dict) and b.get("type") == "tool_use"]
                if tools:
                    pending_tool = str(tools[-1].get("name", ""))
                    pending_at = entry_time(entry)
                else:
                    pending_tool = ""
            if kind == "user" and any(isinstance(b, dict) and b.get("type") == "tool_result"
                                      for b in ((entry.get("message") or {}).get("content") or []) if isinstance(b, (dict,))):
                pending_tool = ""
        status = {"busy": "working", "idle": "idle"}.get(str(record.get("status")), "idle")
        question = ""
        if record.get("status") in ("waiting", "needs_input", "needsAction"):
            status, question = "waiting", "needs you"
        elif pending_tool in ("AskUserQuestion", "ExitPlanMode") and time.time() - pending_at > 2:
            status = "waiting"
            question = "has a question" if pending_tool == "AskUserQuestion" else "has a plan for you to approve"
        elif status == "idle" and asked_in_text:
            # It finished its turn on a question: it is waiting for an answer, not done.
            status, question = "waiting", "asked a question"
        updated = int(record.get("statusUpdatedAt") or record.get("updatedAt") or 0)
        out.append({"tool": "claude", "id": session_id, "name": title or record.get("name") or session_id[:8],
                    "cwd": cwd, "status": status, "updatedAt": updated, "pid": pid,
                    "prompt": clip(prompt), "last": clip(answer, 400), "why": question})
    return out


# ── Codex ────────────────────────────────────────────────────────────────────

def codex_sessions(include_all=False):
    cutoff = time.time() - (30 * 86400 if include_all else 86400)
    files = []
    for path in glob.glob(os.path.join(HOME, ".codex", "sessions", "*", "*", "*", "rollout-*.jsonl")):
        try:
            mtime = os.path.getmtime(path)
        except OSError:
            continue
        if mtime >= cutoff:
            files.append((mtime, path))
    files.sort(reverse=True)
    out = []
    for mtime, path in files[:8]:
        meta = {}
        try:
            with open(path) as handle:
                first = json.loads(handle.readline())
            meta = first.get("payload") or {}
        except (OSError, ValueError):
            continue
        prompt, answer, state, why = "", "", "idle", ""
        for entry in tail_lines(path):
            payload = entry.get("payload") or {}
            if entry.get("type") == "response_item" and payload.get("type") == "message" and payload.get("role") == "user":
                text = " ".join(part.get("text", "") for part in payload.get("content") or [] if isinstance(part, dict))
                if text.strip() and not text.lstrip().startswith("<"):
                    prompt = text
                continue
            if entry.get("type") != "event_msg":
                continue
            kind = payload.get("type")
            if kind == "task_started":
                state = "working"
            elif kind in ("task_complete", "turn_aborted"):
                state = "idle"
                why = ""
                answer = payload.get("last_agent_message") or answer
            elif kind in ("exec_approval_request", "apply_patch_approval_request", "request_user_input", "request_permissions"):
                state, why = "waiting", "needs your approval" if "approval" in kind or "permission" in kind else "has a question"
        # A turn that stopped writing minutes ago is stuck or abandoned, not working.
        if state == "working" and time.time() - mtime > 600:
            state = "idle"
        out.append({"tool": "codex", "id": str(meta.get("id", "")), "name": clip(prompt, 60) or "Codex session",
                    "cwd": str(meta.get("cwd", "")), "status": state, "updatedAt": int(mtime * 1000),
                    "prompt": clip(prompt), "last": clip(answer, 400), "why": why})
    return out


# ── OpenCode ─────────────────────────────────────────────────────────────────

def opencode_server():
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import opencode_bridge
    return opencode_bridge.connect(False)


def opencode_sessions(include_all=False):
    try:
        server = opencode_server()
        listing = server.call("GET", "/api/session?limit=12", timeout=6) or {}
    except Exception:
        return []
    out = []
    for item in listing.get("data", []):
        stamps = item.get("time") or {}
        updated = int(stamps.get("updated") or 0)
        if not include_all and now_ms() - updated > DAY_MS:
            continue
        busy = int(stamps.get("busy") or 0) > int(stamps.get("idle") or 0)
        status, why = ("working" if busy else "idle"), ""
        if busy:
            try:
                pending = server.call("GET", f"/api/session/{item.get('id')}/permission", timeout=3) or {}
                if pending.get("data") if isinstance(pending, dict) else pending:
                    status, why = "waiting", "needs your approval"
            except Exception:
                pass
        out.append({"tool": "opencode", "id": str(item.get("id", "")), "name": str(item.get("title") or "OpenCode session"),
                    "cwd": str((item.get("location") or {}).get("directory", "")),
                    "status": status, "updatedAt": updated, "why": why,
                    "model": str((item.get("model") or {}).get("id", "")), "prompt": "", "last": ""})
    return out


def opencode_messages(session_id, limit=4):
    server = opencode_server()
    listing = server.call("GET", f"/api/session/{session_id}/message?limit={limit}", timeout=8) or {}
    out = []
    for item in listing.get("data", []):
        text = ""
        for part in item.get("parts") or item.get("content") or []:
            if isinstance(part, dict) and part.get("type") == "text":
                text += str(part.get("text", ""))
        role = (item.get("info") or item).get("role") or item.get("role") or ""
        if text.strip():
            out.append({"role": role, "text": clip(text, 500)})
    return out


# ── The list, the detail and the actions ─────────────────────────────────────

def list_sessions(include_all=False):
    sessions = []
    for source in (claude_sessions, codex_sessions, opencode_sessions):
        try:
            sessions.extend(source(include_all))
        except Exception:
            continue
    if not include_all:
        sessions = [s for s in sessions if s["status"] != "idle" or now_ms() - int(s.get("updatedAt") or 0) < IDLE_MS]
    order = {"waiting": 0, "working": 1, "idle": 2}
    sessions.sort(key=lambda s: (order.get(s["status"], 3), -int(s.get("updatedAt") or 0)))
    return sessions


def find(tool, session_id):
    if not session_id:
        return resolve(tool)
    for session in list_sessions(True):
        if session["tool"] == tool and (session["id"] == session_id or session["id"].startswith(session_id)):
            return session
    return None


def detail(tool, session_id):
    session = find(tool, session_id)
    if not session:
        return None
    if tool == "opencode":
        try:
            session["messages"] = opencode_messages(session["id"])
        except Exception:
            session["messages"] = []
    return session


# ── Finding a session from what was said, and the terminal route ──────────────

TOOLS = ("claude", "codex", "opencode")


def resolve(tool, hint=""):
    """The session a request means: of that tool, the one whose name or folder matches the hint words,
    else the one working now, else the most recently active. None when the tool has none."""
    pool = [s for s in list_sessions(True) if s["tool"] == tool]
    if not pool:
        return None
    words = [w for w in str(hint).lower().replace("-", " ").split() if len(w) > 2 and w not in ("session", "sessions", "the", "that", "for")]
    if words:
        scored = []
        for s in pool:
            hay = (s["name"] + " " + s["cwd"]).lower()
            scored.append((sum(1 for w in words if w in hay), s))
        best = max(score for score, _ in scored)
        if best > 0:
            pool = [s for score, s in scored if score == best]
    pool.sort(key=lambda s: (s["status"] != "working", -int(s.get("updatedAt") or 0)))
    return pool[0]


def hypr_json(*args):
    import subprocess
    try:
        done = subprocess.run(["hyprctl", "-j", *args], capture_output=True, text=True, timeout=5)
        return json.loads(done.stdout or "null")
    except (OSError, ValueError, subprocess.SubprocessError):
        return None


def terminal_window(pid):
    """The Hyprland window the CLI with this pid runs in, or None."""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import focus_agent_window as focus
    clients = hypr_json("clients") or []
    return focus.pick_window(focus.ancestry(int(pid)), clients)


def type_into(pid, keys):
    """Focus the terminal of a CLI, make sure it really has focus, type, and put focus back.
    `keys` is a list of ("text", str) or ("key", name). Nothing is typed anywhere else."""
    import subprocess
    window = terminal_window(pid)
    if not window:
        return "That session's terminal window was not found."
    before = hypr_json("activewindow") or {}
    address = window.get("address")
    subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{address}"], capture_output=True, timeout=5)
    for _ in range(10):
        time.sleep(0.08)
        if (hypr_json("activewindow") or {}).get("address") == address:
            break
    else:
        return "Could not bring the terminal to the front, so nothing was typed."
    time.sleep(0.15)
    for kind, value in keys:
        cmd = ["wtype", "--", value] if kind == "text" else ["wtype", "-k", value]
        subprocess.run(cmd, capture_output=True, timeout=10)
        time.sleep(0.05)
    if before.get("address") and before.get("address") != address:
        time.sleep(0.2)
        subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{before['address']}"], capture_output=True, timeout=5)
    return ""


def focus(tool, session_id):
    session = find(tool, session_id)
    if not session:
        return {"ok": False, "error": "No such session."}
    pid = session.get("pid")
    if not pid:
        return {"ok": False, "error": f"{tool} sessions have no window to show."}
    window = terminal_window(pid)
    if not window:
        return {"ok": False, "error": "That session's terminal window was not found."}
    import subprocess
    subprocess.run(["hyprctl", "dispatch", "focuswindow", f"address:{window['address']}"], capture_output=True, timeout=5)
    return {"ok": True, "note": f"Showing {session['name']}."}


def send(tool, session_id, text):
    session = find(tool, session_id)
    if not session:
        return {"ok": False, "error": "No such session."}
    text = str(text).strip()
    if not text or len(text) > 4000:
        return {"ok": False, "error": "Say what to send, up to 4000 characters."}
    if tool == "opencode":
        try:
            opencode_server().call("POST", f"/api/session/{session['id']}/prompt", {"text": text}, timeout=15)
            return {"ok": True, "note": f"Sent to {session['name']}."}
        except Exception as error:
            return {"ok": False, "error": f"OpenCode did not take it: {error}"}
    if tool == "claude" and session.get("pid"):
        problem = type_into(session["pid"], [("text", text), ("key", "Return")])
        return {"ok": not problem, "note": f"Sent to {session['name']}.", "error": problem}
    return {"ok": False, "error": f"Sending to {tool} sessions is not wired up yet."}


def interrupt(tool, session_id):
    session = find(tool, session_id)
    if not session:
        return {"ok": False, "error": "No such session."}
    if tool == "opencode":
        try:
            opencode_server().call("POST", f"/api/session/{session['id']}/interrupt", timeout=10)
            return {"ok": True, "note": f"Stopped {session['name']}."}
        except Exception as error:
            return {"ok": False, "error": f"OpenCode did not take it: {error}"}
    if tool == "claude" and session.get("pid"):
        problem = type_into(session["pid"], [("key", "Escape")])
        return {"ok": not problem, "note": f"Stopped {session['name']}.", "error": problem}
    return {"ok": False, "error": f"Stopping {tool} sessions is not wired up yet."}


def spoken_summary(sessions, limit=5):
    """A short plain-English line for the orb to say or to carry in its context."""
    if not sessions:
        return "No coding sessions are running."
    names = {"claude": "Claude", "codex": "Codex", "opencode": "OpenCode"}
    working = [s for s in sessions if s["status"] == "working"]
    waiting = [s for s in sessions if s["status"] == "waiting"]
    head = f"{len(sessions)} coding session{'s' if len(sessions) != 1 else ''}"
    parts = [f"{len(working)} working" if working else "none working"]
    if waiting:
        parts.append(f"{len(waiting)} waiting for you")
    lines = [head + ": " + ", ".join(parts) + "."]
    for s in sessions[:limit]:
        place = "your home folder" if s["cwd"].rstrip("/") == HOME else os.path.basename(s["cwd"].rstrip("/")) or "the root folder"
        lines.append(f"{names.get(s['tool'], s['tool'])} \"{clip(s['name'], 50)}\" in {place} is {s['status']}.")
    return " ".join(lines)


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    verb = argv[1]
    if verb == "list":
        print(json.dumps(list_sessions("--all" in argv)))
    elif verb == "summary":
        print(spoken_summary(list_sessions()))
    elif verb == "detail" and len(argv) >= 4:
        print(json.dumps(detail(argv[2], argv[3])))
    elif verb == "send" and len(argv) >= 5:
        print(json.dumps(send(argv[2], argv[3], " ".join(argv[4:]))))
    elif verb == "focus" and len(argv) >= 4:
        print(json.dumps(focus(argv[2], argv[3])))
    elif verb == "resolve" and len(argv) >= 3:
        print(json.dumps(resolve(argv[2], " ".join(argv[3:]))))
    elif verb == "interrupt" and len(argv) >= 4:
        print(json.dumps(interrupt(argv[2], argv[3])))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

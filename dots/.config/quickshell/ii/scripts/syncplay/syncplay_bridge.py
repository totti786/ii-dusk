#!/usr/bin/env python3
"""Syncplay bridge for the shell's Syncplay app.

Runs Syncplay's own client (the protocol, the mpv control and the drift
correction are all upstream's) headless, with a UI object that speaks JSON lines
on a unix socket instead of drawing anything. The shell is only a frontend: it
never touches the Syncplay protocol or mpv itself.

    start  --host H --name N --room R [--port P] [--file F] [--player-path P]
           [--player-arg A ...]
        Spawns a detached session (so a shell reload does not end the call or
        kill mpv) and prints one JSON line. The server password, if any, is read
        from stdin and handed to the session through its environment, never argv.
    stop
        Asks the running session to quit.
    status
        {"running": bool}
    defaults
        Prefill values read from the user's syncplay.ini (never a password).
    run   (internal: the session itself)
    compat [syncplay options] [file] [-- mpv options]
        Stands in for the `syncplay` binary when Mediator plays with Watch Together
        (MEDIATOR_SYNCPLAY). Runs the session in the foreground, so Mediator owns the
        process and mpv's IPC socket as usual while the shell window shows the room.
        A session started from the window is ended first and rejoined with the same
        room settings. Host, name and room come from the options Mediator passes on,
        else from syncplay.ini.

The session listens on $XDG_RUNTIME_DIR/ii-syncplay.sock (0600). It sends

    {"type": "state", ...}   whole room state, coalesced (users, playlist, ...)
    {"type": "tick", ...}    playback position and pause, once a second
    {"type": "msg", "kind": "chat|system|error", ...}
    {"type": "ack", "id": N, "ok": bool, "error": str}

and takes {"cmd": ..., "id": N, ...} lines: ready, pause, seek, chat, room,
open, trust, playlist-add (with "trust": true to vouch for the host), playlist-remove, playlist-play, playlist-set, undo,
shuffle, identify, state, quit.

Sessions never store anything: the user's ~/.config/syncplay.ini is read for
defaults (trusted domains, search folders, thresholds) and never written.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import time
from pathlib import Path

SYNCPLAY_LIB = os.environ.get("II_SYNCPLAY_LIB", "/usr/lib/syncplay")
SOCKET_NAME = "ii-syncplay.sock"
PASSWORD_ENV = "II_SYNCPLAY_SERVER_PASSWORD"
HOST_RE_BAD = ("/", " ", "\n", "\r", "\t")


def runtime_dir() -> Path:
    base = os.environ.get("XDG_RUNTIME_DIR")
    if not base:
        raise SystemExit(json.dumps({"ok": False, "error": "XDG_RUNTIME_DIR is not set"}))
    return Path(base)


def socket_path() -> Path:
    return runtime_dir() / SOCKET_NAME


def emit(payload: dict) -> None:
    sys.stdout.write(json.dumps(payload, separators=(",", ":")) + "\n")
    sys.stdout.flush()


# ── Spawner ──────────────────────────────────────────────────────────────────

def alive() -> bool:
    """A session answers on its socket."""
    import socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(1.0)
    try:
        sock.connect(str(socket_path()))
        return True
    except OSError:
        return False
    finally:
        sock.close()


def cmd_start(args: argparse.Namespace) -> int:
    if alive():
        emit({"ok": False, "error": "A Syncplay session is already running", "code": "running"})
        return 0
    host = args.host.strip()
    if not host or any(ch in host for ch in HOST_RE_BAD):
        emit({"ok": False, "error": "Enter a server address", "code": "host"})
        return 0
    name = args.name.strip()
    if not name:
        emit({"ok": False, "error": "Enter a name", "code": "name"})
        return 0
    password = sys.stdin.readline().rstrip("\n") if not sys.stdin.isatty() else ""
    socket_path().unlink(missing_ok=True)
    env = dict(os.environ)
    if password:
        env[PASSWORD_ENV] = password
    # --opt=value everywhere: a value that starts with "-" must not read as an option.
    cmd = [sys.executable, "-I", os.path.abspath(__file__), "run",
           f"--host={host}", f"--port={args.port}", f"--name={name}", f"--room={args.room}"]
    if args.player_path:
        cmd.append(f"--player-path={args.player_path}")
    for extra in args.player_arg or []:
        cmd.append(f"--player-arg={extra}")
    if args.file:
        cmd.append(f"--file={args.file}")
    log = open(runtime_dir() / "ii-syncplay.log", "ab")
    subprocess.Popen(cmd, env=env, stdin=subprocess.DEVNULL, stdout=log, stderr=log,
                     start_new_session=True, close_fds=True)
    # The socket appears once the reactor is up; the shell connects to it itself.
    deadline = time.time() + 8
    while time.time() < deadline:
        if alive():
            emit({"ok": True})
            return 0
        time.sleep(0.1)
    emit({"ok": False, "error": "The Syncplay session did not start", "code": "timeout"})
    return 0


def send_one(payload: dict) -> bool:
    import socket
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.settimeout(2.0)
    try:
        sock.connect(str(socket_path()))
        sock.sendall((json.dumps(payload) + "\n").encode())
        return True
    except OSError:
        return False
    finally:
        sock.close()


def cmd_stop(_args: argparse.Namespace) -> int:
    emit({"ok": True, "stopped": send_one({"cmd": "quit"})})
    return 0


def ini_path() -> Path:
    base = os.environ.get("XDG_CONFIG_HOME") or str(Path.home() / ".config")
    return Path(base) / "syncplay.ini"


def read_defaults() -> dict:
    """What the connect screen starts from: the user's own Syncplay settings, read-only."""
    import ast
    import configparser
    cfg = configparser.RawConfigParser()
    try:
        cfg.read(ini_path(), encoding="utf-8-sig")
    except (OSError, configparser.Error):
        pass

    def get(section: str, key: str, default=""):
        try:
            return cfg.get(section, key)
        except (configparser.Error, KeyError):
            return default

    def as_list(value: str) -> list:
        try:
            parsed = ast.literal_eval(value)
        except (ValueError, SyntaxError):
            return []
        return [str(x) for x in parsed] if isinstance(parsed, (list, tuple)) else []

    port = get("server_data", "port", "8999")
    out = {
        "ok": True,
        "host": get("server_data", "host", ""),
        "port": int(port) if port.isdigit() else 8999,
        "name": get("client_settings", "name", ""),
        "room": get("client_settings", "room", ""),
        "rooms": as_list(get("client_settings", "roomlist", "[]")),
        "publicServers": as_list(get("client_settings", "publicservers", "[]")),
        "mediaDirs": as_list(get("client_settings", "mediasearchdirectories", "[]")),
        "player": get("client_settings", "playerpath", ""),
    }
    return out


def cmd_defaults(_args: argparse.Namespace) -> int:
    emit(read_defaults())
    return 0


def cmd_status(_args: argparse.Namespace) -> int:
    emit({"ok": True, "running": alive()})
    return 0


# ── Session ──────────────────────────────────────────────────────────────────

def run_session(args: argparse.Namespace) -> int:
    import site
    site.addsitedir(SYNCPLAY_LIB)
    sys.path.insert(0, SYNCPLAY_LIB)

    argv = ["syncplay", "--no-gui", "--no-store", "--language", "en",
            "-a", f"{args.host}:{args.port}", "-n", args.name, "-r", args.room]
    if args.player_path:
        argv += ["--player-path", args.player_path]
    if getattr(args, "playlist", ""):
        argv += ["--load-playlist-from-file", args.playlist]
    if args.file:
        argv.append(args.file)
    if args.player_arg:
        argv += ["--"] + list(args.player_arg)
    sys.argv = argv

    from twisted.internet import protocol, reactor, task

    from syncplay import constants, ui as sp_ui
    from syncplay import client as sp_client

    session = Session(reactor, constants, sp_client, protocol, task, args)
    sp_ui.getUi = lambda graphical=False, passedBar=None: session.ui

    from syncplay.clientManager import SyncplayClientManager
    # ConfigurationGetter ignores the password option when it comes from argv with
    # --no-store; the environment is the only way it reaches the session.
    password = os.environ.pop(PASSWORD_ENV, "")
    if password:
        from syncplay.ui import ConfigurationGetter as cg
        original = cg.ConfigurationGetter.getConfiguration

        def with_password(self, *a, **kw):
            config = original(self, *a, **kw)
            config["password"] = password
            return config
        cg.ConfigurationGetter.getConfiguration = with_password
    try:
        SyncplayClientManager().run()
    finally:
        socket_path().unlink(missing_ok=True)
    return 0


class Session:
    """Holds the UI object, the socket server and the state snapshot logic."""

    def __init__(self, reactor, constants, sp_client, protocol, task, args):
        self.reactor = reactor
        self.constants = constants
        self.protocol_mod = protocol
        self.args = args
        self.client = None
        self.peers: list = []
        self.push_pending = False
        self.motd = ""
        self.ssl = ""
        self.last_error = ""
        self.history: list = []  # recent msg events, replayed to a shell that connects later
        self.features: dict = {}
        self.ui = BridgeUI(self)
        self.ticker = task.LoopingCall(self.tick)
        # Chat arrives as a plain message through UiManager; tag it so the shell
        # can draw it as chat rather than parse "<name> text" back out.
        original = sp_client.UiManager.showChatMessage
        session = self

        def showChatMessage(manager, username, message):
            session.broadcast({"type": "msg", "kind": "chat", "user": username,
                               "text": message, "t": time.time()})
            session.chat_in_flight = True
            try:
                original(manager, username, message)
            finally:
                session.chat_in_flight = False
        sp_client.UiManager.showChatMessage = showChatMessage
        self.chat_in_flight = False

    # ── Socket server ────────────────────────────────────────────────────────
    def listen(self) -> None:
        session = self
        protocol = self.protocol_mod

        class Peer(protocol.Protocol):
            def __init__(self):
                self.buffer = b""

            def connectionMade(self):
                for event in session.history:
                    self.transport.write((json.dumps(event, separators=(",", ":")) + "\n").encode())
                session.peers.append(self)
                session.push_state(force=True)

            def connectionLost(self, reason=None):
                if self in session.peers:
                    session.peers.remove(self)

            def dataReceived(self, data):
                self.buffer += data
                while b"\n" in self.buffer:
                    line, self.buffer = self.buffer.split(b"\n", 1)
                    if not line.strip():
                        continue
                    try:
                        message = json.loads(line)
                    except ValueError:
                        continue
                    if isinstance(message, dict):
                        session.handle(self, message)
                if len(self.buffer) > 1 << 20:
                    self.transport.loseConnection()

        factory = protocol.Factory()
        factory.protocol = Peer
        path = str(socket_path())
        Path(path).unlink(missing_ok=True)
        self.reactor.listenUNIX(path, factory, mode=0o600)

    def broadcast(self, payload: dict) -> None:
        if payload.get("type") == "msg":
            self.history.append(payload)
            del self.history[:-300]
        data = (json.dumps(payload, separators=(",", ":")) + "\n").encode()
        for peer in list(self.peers):
            try:
                peer.transport.write(data)
            except Exception:
                pass

    # ── Snapshots ────────────────────────────────────────────────────────────
    def schedule_push(self) -> None:
        if self.push_pending:
            return
        self.push_pending = True
        self.reactor.callLater(0.05, self.push_state)

    def push_state(self, force: bool = False) -> None:
        self.push_pending = False
        if self.peers:
            self.broadcast(self.snapshot())

    @staticmethod
    def file_info(file_):
        if not file_:
            return None
        return {"name": file_.get("name") or "", "duration": file_.get("duration") or 0,
                "size": file_.get("size") or 0}

    def snapshot(self) -> dict:
        client = self.client
        base = {"type": "state", "host": self.args.host, "port": self.args.port,
                "motd": self.motd, "ssl": self.ssl, "error": self.last_error, "t": time.time()}
        if client is None:
            return dict(base, connected=False, users=[], playlist={"items": [], "index": None})
        userlist = client.userlist
        me = userlist.currentUser
        protocol = getattr(client, "_protocol", None)
        connected = bool(protocol and getattr(protocol, "logged", False))
        room = me.room or self.args.room
        users = []
        everyone = [me] + [u for u in userlist._users.values()]
        for user in everyone:
            is_me = user is me
            if not user.username:
                continue
            users.append({
                "name": user.username,
                "room": user.room or "",
                "inRoom": (user.room or "") == (me.room or ""),
                "me": is_me,
                "file": self.file_info(user.file),
                "ready": user.isReady(),
                "controller": bool(user.isController()),
                "sameFile": bool(is_me or (me.file and user.file and me.isFileSame(user.file))),
            })
        playlist = client.playlist
        items = list(getattr(playlist, "_playlist", []) or [])
        missing = self._missing(client, items)
        index = getattr(playlist, "_playlistIndex", None)
        try:
            shared = bool(client.sharedPlaylistIsEnabled())
        except Exception:
            shared = False
        features = {k: v for k, v in (getattr(client, "serverFeatures", {}) or {}).items()
                    if isinstance(v, (bool, int, float, str))}
        return dict(base, connected=connected, name=me.username or self.args.name, room=room,
                    users=users, features=features, sharedPlaylist=shared,
                    playlist={"items": items, "index": index, "missing": missing},
                    owner=getattr(self.args, "owner", "") or "",
                    canUndo=bool(self._can_undo(playlist, items)),
                    file=self.file_info(me.file), ready=me.isReady(),
                    controller=bool(me.isController()),
                    controlledRoom=bool(room and room.startswith("+")),
                    **self.playback())

    @staticmethod
    def _missing(client, items) -> list:
        """Indexes of playlist entries this machine cannot find in its media directories.

        Syncplay identifies a shared entry by file name and each user finds it in their own
        media directories; one that is not found here cannot be switched to. URLs are fine.
        """
        out = []
        try:
            from syncplay import utils
            for i, name in enumerate(items):
                if utils.isURL(name):
                    continue
                if not client.fileSwitch.findFilepath(name):
                    out.append(i)
        except Exception:
            return []
        return out

    @staticmethod
    def _can_undo(playlist, items) -> bool:
        try:
            return playlist.canUndoPlaylist(items)
        except Exception:
            return False

    def playback(self) -> dict:
        client = self.client
        if client is None:
            return {"position": 0.0, "paused": True, "globalPosition": 0.0, "globalPaused": True}
        try:
            return {"position": round(float(client.getPlayerPosition()), 2),
                    "paused": bool(client.getPlayerPaused()),
                    "globalPosition": round(float(client.getGlobalPosition()), 2),
                    "globalPaused": bool(client.getGlobalPaused())}
        except Exception:
            return {"position": 0.0, "paused": True, "globalPosition": 0.0, "globalPaused": True}

    def tick(self) -> None:
        if self.peers and self.client is not None:
            payload = {"type": "tick"}
            payload.update(self.playback())
            self.broadcast(payload)

    # ── Commands ─────────────────────────────────────────────────────────────
    def handle(self, peer, message: dict) -> None:
        ident = message.get("id")
        cmd = str(message.get("cmd", ""))
        client = self.client
        error = ""
        try:
            if cmd == "state":
                peer.transport.write((json.dumps(self.snapshot()) + "\n").encode())
            elif cmd == "quit":
                self.reactor.callLater(0.05, self.shutdown)
            elif client is None:
                error = "Not connected yet"
            else:
                error = self.dispatch(client, cmd, message) or ""
        except Exception as exc:  # a bad command must never end the call
            error = f"{type(exc).__name__}: {exc}"
        if ident is not None:
            peer.transport.write((json.dumps({"type": "ack", "id": ident, "ok": not error,
                                              "error": error}) + "\n").encode())

    @staticmethod
    def trust(client, item: str) -> None:
        """Let this session switch to a stream's host, in memory only.

        Syncplay refuses to switch to a link whose host is not in its trusted domains, and a
        stream host changes from episode to episode. Mediator vouches for the links it queues.
        Nothing is written: the session runs with --no-store.
        """
        from urllib.parse import urlparse
        host = urlparse(item).hostname if "://" in item else None
        if not host:
            return
        current = list(client._config.get("trustedDomains") or [])
        if host not in current:
            client._config["trustedDomains"] = current + [host]

    def dispatch(self, client, cmd: str, message: dict) -> str:
        playlist = client.playlist
        if cmd == "ready":
            client.changeReadyState(bool(message.get("value")))
        elif cmd == "pause":
            paused = bool(message.get("value"))
            client.setPaused(paused)
            # The player confirms and the protocol broadcasts it; nudge the shell now.
        elif cmd == "seek":
            client.setPosition(float(message.get("position", 0)))
        elif cmd == "chat":
            text = str(message.get("text", "")).strip()
            if text:
                client.sendChat(text)
        elif cmd == "room":
            room = str(message.get("name", "")).strip()
            if not room:
                return "Enter a room name"
            client.userlist.currentUser.room = room
            client.sendRoom()
        elif cmd == "open":
            path = str(message.get("path", ""))
            if not path:
                return "No file"
            client.openFile(path, resetPosition=True, fromUser=True)
        elif cmd == "trust":
            self.trust(client, str(message.get("item", "")))
        elif cmd == "playlist-add":
            item = str(message.get("item", ""))
            if message.get("trust"):
                self.trust(client, item)
            playlist.addToPlaylist(item)
        elif cmd == "playlist-remove":
            playlist.deleteAtIndex(int(message.get("index", -1)))
        elif cmd == "playlist-play":
            playlist.changeToPlaylistIndex(int(message.get("index", 0)))
        elif cmd == "playlist-set":
            items = [str(x) for x in message.get("items", [])]
            playlist.changePlaylist(items)
        elif cmd == "undo":
            playlist.undoPlaylistChange()
        elif cmd == "shuffle":
            playlist.shuffleRemainingPlaylist()
        elif cmd == "identify":
            password = str(message.get("password", ""))
            if password:
                client.identifyAsController(password)
        elif cmd == "refresh":
            client.getUserList()
        else:
            return f"Unknown command: {cmd}"
        self.schedule_push()
        return ""

    def shutdown(self) -> None:
        try:
            if self.client is not None:
                self.client.stop(False)
        finally:
            try:
                self.reactor.stop()
            except Exception:
                pass


class BridgeUI:
    """The UI surface SyncplayClient expects, turned into JSON events."""

    def __init__(self, session: Session):
        self.session = session
        self.uiMode = session.constants.GRAPHICAL_UI_MODE

    def _msg(self, kind: str, text: str, **extra) -> None:
        payload = {"type": "msg", "kind": kind, "text": text, "t": time.time()}
        payload.update(extra)
        self.session.broadcast(payload)

    def addClient(self, client):
        self.session.client = client
        self.session.listen()
        self.session.ticker.start(1.0, now=False)

    # Messaging
    def showMessage(self, message, noTimestamp=False, isMotd=False):
        if self.session.chat_in_flight:
            return  # already sent as chat
        if isMotd:
            self.session.motd = message
            self.session.schedule_push()
        self._msg("system", message, motd=bool(isMotd))

    def showDebugMessage(self, message):
        pass

    def showErrorMessage(self, message, criticalerror=False):
        self.session.last_error = message
        self._msg("error", message, critical=bool(criticalerror))
        self.session.schedule_push()

    def showUserList(self, currentUser, rooms):
        self.session.schedule_push()

    def showOSDMessage(self, *a, **kw):
        pass

    def promptFor(self, prompt=">", message=""):
        return ""  # the shell never answers a console prompt; never block the reactor

    def executeCommand(self, command):
        pass

    # Room / list notifications: all mean "the snapshot changed"
    def userListChange(self):
        self.session.schedule_push()

    def markEndOfUserlist(self):
        self.session.schedule_push()

    def addRoomToList(self, *a):
        self.session.schedule_push()

    def updateRoomName(self, room=""):
        self.session.schedule_push()

    def setPlaylist(self, newPlaylist, newIndexFilename=None):
        self.session.schedule_push()

    def setPlaylistIndexFilename(self, filename):
        self.session.schedule_push()

    def addFileToPlaylist(self, file):
        pass

    def fileSwitchFoundFiles(self):
        self.session.schedule_push()

    def setFeatures(self, featureList):
        self.session.schedule_push()

    def setControllerStatus(self, username, isController):
        self.session.schedule_push()

    def updateAutoPlayState(self, newState):
        self.session.schedule_push()

    def setSSLMode(self, sslMode, sslInformation=""):
        self.session.ssl = f"{sslMode} {sslInformation}".strip()
        self.session.schedule_push()

    def drop(self):
        self.session.broadcast({"type": "ended"})
        self.session.reactor.callLater(0.2, self.session.shutdown)


def cmd_compat(rest: list[str]) -> int:
    """`syncplay`-compatible entry for Mediator: foreground session in place of the GUI."""
    if "--" in rest:
        i = rest.index("--")
        rest, player_args = rest[:i], rest[i + 1:]
    else:
        player_args = []
    p = argparse.ArgumentParser(prog="compat", add_help=False)
    p.add_argument("--host", "-a", default="")
    p.add_argument("--port", type=int, default=0)
    p.add_argument("--name", "-n", default="")
    p.add_argument("--room", "-r", default=None)
    p.add_argument("--player-path", default="")
    p.add_argument("--load-playlist-from-file", dest="playlist", default="")
    p.add_argument("file", nargs="?", default="")
    opts, _unknown = p.parse_known_args(rest)
    host, port, name, room = opts.host, opts.port, opts.name, opts.room
    if not (host and name):
        saved = read_defaults()
        host = host or saved.get("host", "")
        port = port or int(saved.get("port") or 0)
        name = name or saved.get("name", "")
        room = room if room is not None else saved.get("room", "")
    if ":" in host and not port:
        host, _, tail = host.rpartition(":")
        port = int(tail) if tail.isdigit() else 0
    if not host or not name:
        print("Syncplay: no server or name set. Open Syncplay in the shell first.", file=sys.stderr)
        return 2
    if alive():
        send_one({"cmd": "quit"})
        for _ in range(50):
            if not alive():
                break
            time.sleep(0.1)
    socket_path().unlink(missing_ok=True)
    args = argparse.Namespace(host=host, port=port or 8999, name=name, room=room or "",
                              file=opts.file, player_path=opts.player_path,
                              player_arg=player_args, playlist=opts.playlist, owner="mediator")
    return run_session(args)


def main(argv: list[str]) -> int:
    if argv and argv[0] == "compat":
        return cmd_compat(argv[1:])
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("start", "run"):
        p = sub.add_parser(name)
        p.add_argument("--host", required=True)
        p.add_argument("--port", type=int, default=8999)
        p.add_argument("--name", required=True)
        p.add_argument("--room", default="")
        p.add_argument("--file", default="")
        p.add_argument("--player-path", default="")
        p.add_argument("--player-arg", action="append")
    sub.add_parser("stop")
    sub.add_parser("status")
    sub.add_parser("defaults")
    args = parser.parse_args(argv)
    if args.command == "start":
        return cmd_start(args)
    if args.command == "stop":
        return cmd_stop(args)
    if args.command == "status":
        return cmd_status(args)
    if args.command == "defaults":
        return cmd_defaults(args)
    return run_session(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

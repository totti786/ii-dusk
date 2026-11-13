#!/usr/bin/env python3
"""Keeps the Discordo Voice helper alive across shell reloads.

The helper speaks NDJSON on stdin/stdout, and a child of the shell dies when the shell does.
This script puts a small daemon in between:

    broker.py attach HELPER   what the shell runs in place of the helper. It starts the daemon
                              if there is none, then relays stdin/stdout to it. Killing it (a
                              shell reload) only detaches; the call carries on.
    broker.py stop            ends the daemon and its helper (an explicit disconnect)
    broker.py daemon HELPER   (internal) owns the helper process and serves it on a socket

The daemon remembers the helper's `ready` line and replays it to whoever attaches, so a new
shell session sees the handshake it missed, and then asks for `status` to learn the state. When
the helper exits the daemon exits with it, so the next attach starts a fresh one.
"""
import asyncio
import os
import signal
import socket
import subprocess
import sys
import threading
import time

SOCK = os.path.join(os.environ.get("XDG_RUNTIME_DIR") or "/tmp", "ii-discordo-voice.sock")
STOP = b"#stop\n"
EXIT = b"#exit "
# With nobody attached (the shell is gone) and no channel joined, the daemon has no reason to
# keep a signed-in helper around. The shell ends it sooner itself (DiscordoVoiceService).
ORPHAN_SECONDS = 15 * 60


def connect():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(SOCK)
    return s


def attach(helper):
    try:
        s = connect()
    except OSError:
        subprocess.Popen([sys.executable, "-I", os.path.abspath(__file__), "daemon", helper],
                         stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)
        s = None
        for _ in range(60):
            time.sleep(0.05)
            try:
                s = connect()
                break
            except OSError:
                continue
        if s is None:
            print("discordo voice broker did not start", file=sys.stderr)
            return 1

    code = [0]

    def up():
        try:
            for line in sys.stdin.buffer:
                s.sendall(line)
        except OSError:
            pass
        os._exit(code[0])  # the shell went away: detach, leave the daemon running

    threading.Thread(target=up, daemon=True).start()
    out = sys.stdout.buffer
    with s.makefile("rb") as f:
        for line in f:
            if line.startswith(EXIT):
                try:
                    code[0] = int(line[len(EXIT):].strip() or 0)
                except ValueError:
                    code[0] = 1
                continue
            out.write(line)
            out.flush()
    out.flush()
    os._exit(code[0])  # the stdin thread may be blocked in a read; do not wait for it


def stop():
    try:
        s = connect()
    except OSError:
        return 0
    s.sendall(STOP)
    # Read until the daemon closes: closing with its replayed `ready` line unread makes the
    # kernel reset the connection, and the reset can eat the stop request
    s.settimeout(5)
    try:
        while s.recv(4096):
            pass
    except OSError:
        pass
    s.close()
    return 0


async def daemon(helper):
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    proc = await asyncio.create_subprocess_exec(
        helper, stdin=asyncio.subprocess.PIPE, stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
        # a page of chat history is far past asyncio's 64 KiB line default
        limit=16 * 1024 * 1024)
    clients = set()
    state = {"ready": None, "joined": False, "alone_since": time.monotonic()}

    async def pump():
        while True:
            line = await proc.stdout.readline()
            if not line:
                return
            compact = line.replace(b" ", b"")
            if b'"type":"ready"' in compact:
                state["ready"] = line
            elif b'"type":"channel"' in compact:
                state["joined"] = b'"joined":true' in compact
            for w in list(clients):
                try:
                    w.write(line)
                except Exception:
                    clients.discard(w)

    async def on_client(reader, writer):
        if state["ready"]:
            writer.write(state["ready"])
        clients.add(writer)
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                if line == STOP:
                    # Ask the helper to leave the call and exit; kill it if it will not
                    try:
                        proc.stdin.write(b'{"cmd":"shutdown"}\n')
                        await proc.stdin.drain()
                    except (ConnectionError, OSError):
                        pass
                    asyncio.get_running_loop().call_later(3, lambda: proc.kill() if proc.returncode is None else None)
                    break
                if proc.stdin and not proc.stdin.is_closing():
                    proc.stdin.write(line)
                    await proc.stdin.drain()
        except (ConnectionError, OSError):
            pass
        finally:
            clients.discard(writer)
            writer.close()

    async def watchdog():
        while True:
            await asyncio.sleep(min(30, ORPHAN_SECONDS / 2))
            if clients or state["joined"]:
                state["alone_since"] = time.monotonic()
            elif time.monotonic() - state["alone_since"] > ORPHAN_SECONDS:
                if proc.returncode is None:
                    try:
                        proc.stdin.write(b'{"cmd":"shutdown"}\n')
                        await proc.stdin.drain()
                    except (ConnectionError, OSError):
                        pass
                    asyncio.get_running_loop().call_later(3, lambda: proc.kill() if proc.returncode is None else None)
                return

    server = await asyncio.start_unix_server(on_client, path=SOCK)
    os.chmod(SOCK, 0o600)
    pumping = asyncio.create_task(pump())
    watching = asyncio.create_task(watchdog())
    code = await proc.wait()
    watching.cancel()
    try:
        await asyncio.wait_for(pumping, 1)
    except Exception:
        pass
    for w in list(clients):
        try:
            w.write(EXIT + str(code if code is not None else 1).encode() + b"\n")
            await w.drain()
            w.close()
        except Exception:
            pass
    server.close()
    try:
        os.unlink(SOCK)
    except FileNotFoundError:
        pass
    return 0


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else ""
    if mode == "attach" and len(sys.argv) > 2:
        return attach(sys.argv[2])
    if mode == "stop":
        return stop()
    if mode == "daemon" and len(sys.argv) > 2:
        signal.signal(signal.SIGHUP, signal.SIG_IGN)
        return asyncio.run(daemon(sys.argv[2]))
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main())

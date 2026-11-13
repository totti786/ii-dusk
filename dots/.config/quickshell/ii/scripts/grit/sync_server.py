#!/usr/bin/env python3
"""Grit's tiny self-hosted sync server.

The Quickshell app keeps one mergeable JSON document per install. This server
stores the latest revision of that document and refuses a write based on an old
revision, so two devices can merge without either one silently overwriting the
other:

    GET  /grit   -> {"revision": N, "payload": {...} | null, "updatedAt": "..."}
    POST /grit   -> {"baseRevision": N, "payload": {...}}
                 <- {"revision": N + 1, "updatedAt": "..."}
                 <- 409 {"revision": M, "payload": {...}, "updatedAt": "..."}

Every request needs `Authorization: Bearer <--token>`. The server is meant for
a private LAN or a tunnel; it is not a public service.
"""

from __future__ import annotations

import argparse
import hmac
import json
import os
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlsplit

MAX_BODY_BYTES = 8 * 1024 * 1024
DEFAULT_PORT = 8765


def default_data_path() -> Path:
    state_home = os.environ.get("XDG_STATE_HOME")
    if not state_home:
        state_home = os.path.join(os.path.expanduser("~"), ".local", "state")
    return Path(state_home) / "quickshell" / "user" / "grit" / "sync.json"


class DocumentStore:
    """The revisioned document, guarded by one lock and written atomically."""

    def __init__(self, path: Path) -> None:
        self.path = path
        self.lock = threading.Lock()
        self.revision = 0
        self.payload: dict | None = None
        self.updated_at = ""
        self._load()

    def _load(self) -> None:
        try:
            raw = self.path.read_text(encoding="utf-8")
        except FileNotFoundError:
            return
        except OSError as error:
            print(f"[grit] cannot read {self.path}: {error}", file=sys.stderr, flush=True)
            return
        if not raw.strip():
            return
        try:
            document = json.loads(raw)
            revision = int(document.get("revision", 0))
            payload = document.get("payload")
        except (ValueError, TypeError, AttributeError) as error:
            backup = self.path.with_name(self.path.name + ".corrupt-" + str(int(time.time())))
            try:
                self.path.replace(backup)
                print(f"[grit] unreadable data moved to {backup}: {error}", file=sys.stderr, flush=True)
            except OSError:
                print(f"[grit] unreadable data at {self.path}: {error}", file=sys.stderr, flush=True)
            return
        if revision < 0:
            revision = 0
        if payload is not None and not isinstance(payload, dict):
            payload = None
        self.revision = revision
        self.payload = payload
        self.updated_at = str(document.get("updatedAt", ""))

    def _save_locked(self) -> None:
        self.path.parent.mkdir(parents=True, exist_ok=True)
        document = {
            "revision": self.revision,
            "payload": self.payload,
            "updatedAt": self.updated_at,
        }
        handle, temp_name = tempfile.mkstemp(prefix=".grit-sync-", dir=str(self.path.parent))
        try:
            with os.fdopen(handle, "w", encoding="utf-8") as output:
                json.dump(document, output, ensure_ascii=False, separators=(",", ":"))
                output.flush()
                os.fsync(output.fileno())
            os.replace(temp_name, self.path)
            try:
                directory = os.open(str(self.path.parent), os.O_RDONLY)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
            except OSError:
                pass
        finally:
            try:
                os.unlink(temp_name)
            except FileNotFoundError:
                pass

    def snapshot(self) -> dict:
        with self.lock:
            return {
                "revision": self.revision,
                "payload": self.payload,
                "updatedAt": self.updated_at,
            }

    def commit(self, base_revision: int, payload: dict) -> tuple[bool, dict]:
        with self.lock:
            if base_revision != self.revision:
                return False, {
                    "revision": self.revision,
                    "payload": self.payload,
                    "updatedAt": self.updated_at,
                }
            self.revision += 1
            self.payload = payload
            self.updated_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
            self._save_locked()
            return True, {
                "revision": self.revision,
                "payload": self.payload,
                "updatedAt": self.updated_at,
            }


class GritServer(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True

    def __init__(self, address, handler, store: DocumentStore, token: str, verbose: bool) -> None:
        super().__init__(address, handler)
        self.store = store
        self.token = token
        self.verbose = verbose


class GritHandler(BaseHTTPRequestHandler):
    server: GritServer
    server_version = "GritSync/1"

    # ── HTTP plumbing ───────────────────────────────────────────────────
    def _send_json(self, status: int, body: dict, extra_headers: dict | None = None) -> None:
        data = json.dumps(body, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        for name, value in (extra_headers or {}).items():
            self.send_header(name, value)
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _error(self, status: int, message: str, extra_headers: dict | None = None) -> None:
        self._send_json(status, {"error": message}, extra_headers)

    def _known_path(self) -> bool:
        path = urlsplit(self.path).path.rstrip("/")
        return path in ("", "/grit")

    def _authorized(self) -> bool:
        header = self.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return False
        supplied = header[len("Bearer "):].strip()
        return bool(supplied) and hmac.compare_digest(supplied, self.server.token)

    def log_message(self, format: str, *args) -> None:
        if self.server.verbose:
            super().log_message(format, *args)

    # ── Methods ─────────────────────────────────────────────────────────
    def do_OPTIONS(self) -> None:
        if not self._known_path():
            self._error(404, "unknown endpoint")
            return
        self.send_response(204)
        self.send_header("Content-Length", "0")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Authorization, Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.end_headers()

    def do_GET(self) -> None:
        if not self._known_path():
            self._error(404, "unknown endpoint")
            return
        if not self._authorized():
            self._error(401, "invalid or missing sync key", {"WWW-Authenticate": "Bearer"})
            return
        self._send_json(200, self.server.store.snapshot())

    def do_POST(self) -> None:
        if not self._known_path():
            self._error(404, "unknown endpoint")
            return
        if not self._authorized():
            self._error(401, "invalid or missing sync key", {"WWW-Authenticate": "Bearer"})
            return

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except (TypeError, ValueError):
            self._error(400, "invalid Content-Length")
            return
        if length <= 0:
            self._error(400, "empty request body")
            return
        if length > MAX_BODY_BYTES:
            self._error(413, "request body is too large")
            return

        try:
            raw = self.rfile.read(length)
        except OSError:
            self._error(400, "could not read request body")
            return
        try:
            body = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, ValueError):
            self._error(400, "request body is not JSON")
            return
        if not isinstance(body, dict):
            self._error(400, "request body must be a JSON object")
            return

        payload = body.get("payload")
        if not isinstance(payload, dict):
            self._error(400, "payload must be a JSON object")
            return
        base = body.get("baseRevision", 0)
        if isinstance(base, bool) or not isinstance(base, int) or base < 0:
            self._error(400, "baseRevision must be a non-negative integer")
            return

        accepted, document = self.server.store.commit(base, payload)
        if not accepted:
            # The caller merges this document and retries; nothing was overwritten.
            self._send_json(409, document)
            return
        self._send_json(200, {
            "revision": document["revision"],
            "updatedAt": document["updatedAt"],
        })


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Revisioned sync server for Grit (habits, tasks and focus sessions).",
    )
    parser.add_argument("--host", default="0.0.0.0",
                        help="Address to bind (default: 0.0.0.0, reachable on the LAN).")
    parser.add_argument("--port", type=int, default=DEFAULT_PORT,
                        help=f"Port to bind (default: {DEFAULT_PORT}).")
    parser.add_argument("--token", default=os.environ.get("GRIT_SYNC_TOKEN", ""),
                        help="Shared bearer token. Also read from GRIT_SYNC_TOKEN.")
    parser.add_argument("--data", default=str(default_data_path()),
                        help="Path to the server's document (default: an XDG state path).")
    parser.add_argument("--verbose", action="store_true", help="Log each HTTP request.")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    token = str(args.token or "").strip()
    if not token:
        print("error: --token (or GRIT_SYNC_TOKEN) is required", file=sys.stderr)
        return 2
    if not 1 <= int(args.port) <= 65535:
        print("error: --port must be between 1 and 65535", file=sys.stderr)
        return 2

    store = DocumentStore(Path(args.data).expanduser())
    try:
        server = GritServer((args.host, int(args.port)), GritHandler, store, token, args.verbose)
    except OSError as error:
        print(f"error: cannot listen on {args.host}:{args.port}: {error}", file=sys.stderr)
        return 1

    print(f"Grit sync listening on http://{args.host}:{args.port}/grit", file=sys.stderr, flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nGrit sync stopped", file=sys.stderr, flush=True)
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

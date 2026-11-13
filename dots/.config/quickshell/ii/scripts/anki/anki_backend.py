#!/usr/bin/env python3
"""Backend of the Anki app (services/AnkiService.qml).

This is a thin adapter over upstream's scripts/anki/anki_daemon.py, which stays
untouched so upstream syncs never conflict on it. The daemon is the engine: Anki's own
Rust core (queue, FSRS/SM-2, renderer, AnkiWeb sync), card HTML reshaped for Qt rich
text, MathJax as SVG. This file adds what the app needs on top of it:

  * finding the user's default Anki profile (native or Flatpak, last-used profile),
    instead of upstream's private collection;
  * the request/response protocol the app was built on: `{"id", "cmd", "args": {}}` in,
    `{"id", "ok", "data"}` or `{"id", "ok": false, "error": {code, message, detail}}` out,
    plus unsolicited `{"event": ...}` lines (sync progress);
  * payload shapes the views already read (questionHtml, answerHtml, buttons, deck tree);
  * note-level bury/suspend and the profile list.

Commands the app has no special shape for (login, sync, addNote, ...) go straight to the
daemon with `args` as the request.
"""

from __future__ import annotations

import io
import json
import os
import pickle
import pwd
import re
import signal
import sqlite3
import sys
import threading
import traceback
from html import escape, unescape
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))

# The engine is a private venv holding a PINNED `anki` (scripts/anki/install_engine.sh), so
# the app needs neither the system package nor Anki desktop, and the engine never moves
# ahead of the version that last touched the collection. There is deliberately no fallback
# to the system package: a second engine of unknown version must not open the real profile.
# The folder is looked up through the account database, not $HOME/$XDG_DATA_HOME, which
# tests and sandboxes override.
ENGINE_DIR = os.environ.get("II_ANKI_ENGINE") or os.path.join(
    pwd.getpwuid(os.getuid()).pw_dir, ".local", "share", "ii-anki-engine"
)
ENGINE_VENV = os.path.join(ENGINE_DIR, "venv")
ENGINE_PYTHON = os.path.join(ENGINE_VENV, "bin", "python")
IN_ENGINE = os.path.realpath(sys.prefix) == os.path.realpath(ENGINE_VENV)
if not IN_ENGINE and os.path.exists(ENGINE_PYTHON):
    os.execv(ENGINE_PYTHON, [ENGINE_PYTHON, "-I", os.path.abspath(__file__), *sys.argv[1:]])

# `python3 -I` leaves the script directory off sys.path.
sys.path.insert(0, HERE)

# Protocol on the original stdout; anything libraries print goes to stderr.
PROTOCOL_OUT = os.fdopen(os.dup(1), "w", encoding="utf-8")
sys.stdout = sys.stderr
_out_lock = threading.Lock()

import anki_daemon as up  # noqa: E402


def write_line(obj: dict) -> None:
    with _out_lock:
        try:
            PROTOCOL_OUT.write(json.dumps(obj, ensure_ascii=False, separators=(",", ":")) + "\n")
            PROTOCOL_OUT.flush()
        except BrokenPipeError:
            os._exit(0)


# Upstream's progress events (sync stages) reach the app through the same channel.
up.emit = write_line


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


class BackendError(Exception):
    def __init__(self, code: str, message: str, detail: Any = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.detail = detail


# ---------------------------------------------------------------- finding Anki's data

def anki_bases() -> list[Path]:
    """Anki data folders that exist, native install first, then Flatpak."""
    data = Path(os.environ.get("XDG_DATA_HOME") or Path.home() / ".local" / "share")
    candidates = [
        data / "Anki2",
        Path.home() / ".var" / "app" / "net.ankiweb.Anki" / "data" / "Anki2",
        Path.home() / "Documents" / "Anki",  # very old installs
    ]
    return [base for base in candidates if base.is_dir()]


def _prefs_rows(base: Path, query: str) -> list[tuple]:
    prefs = base / "prefs21.db"
    if not prefs.exists():
        return []
    try:
        con = sqlite3.connect(f"file:{prefs}?mode=ro", uri=True)
        try:
            return con.execute(query).fetchall()
        finally:
            con.close()
    except Exception as exc:
        log(f"could not read {prefs}: {exc}")
        return []


class _PlainUnpickler(pickle.Unpickler):
    """Anki stores its profile dicts as pickles. They hold only plain values, so no
    class or function is ever needed: refusing every global means a tampered
    prefs21.db cannot run code here."""

    def find_class(self, module: str, name: str) -> Any:
        raise pickle.UnpicklingError(f"refusing to load {module}.{name}")


def read_profile_names(base: Path) -> list[str]:
    names = [str(r[0]) for r in _prefs_rows(base, "select name from profiles where name != '_global' collate nocase")]
    if names:
        return names
    # No prefs database (copied folder, fresh sync): any folder holding a collection is a profile.
    try:
        return sorted(p.name for p in base.iterdir() if (p / "collection.anki2").exists())
    except OSError:
        return []


def read_last_profile(base: Path) -> str:
    rows = _prefs_rows(base, "select cast(data as blob) from profiles where name = '_global' collate nocase")
    if not rows or rows[0][0] is None:
        return ""
    try:
        data = _PlainUnpickler(io.BytesIO(rows[0][0])).load()
        if isinstance(data, dict):
            return str(data.get("last_loaded_profile_name") or "")
    except Exception:
        pass
    return ""


def locate_collection(profile: str = "", explicit: str = "") -> tuple[Path, str, list[str]]:
    """The collection to open, its profile name, and every profile found."""
    explicit = (explicit or os.environ.get("II_ANKI_COLLECTION") or "").strip()
    if explicit:
        path = Path(os.path.expanduser(explicit))
        if path.is_dir():
            path = path / "collection.anki2"
        return path, profile or path.parent.name, []

    bases = anki_bases()
    if not bases:
        raise BackendError(
            "no_profiles",
            "No Anki data folder found. Open Anki once, then try again.",
            {"looked": [str(Path.home() / ".local/share/Anki2"), str(Path.home() / ".var/app/net.ankiweb.Anki/data/Anki2")]},
        )
    # Profiles of the first base that has any; the requested or last-used profile wins.
    for base in bases:
        names = read_profile_names(base)
        if not names:
            continue
        chosen = profile if profile in names else ""
        chosen = chosen or read_last_profile(base)
        chosen = chosen if chosen in names else ""
        chosen = chosen or ("User 1" if "User 1" in names else names[0])
        return base / chosen / "collection.anki2", chosen, names
    raise BackendError(
        "no_profiles",
        "Anki has no profiles yet. Open Anki once, then try again.",
        {"base": str(bases[0])},
    )


# ------------------------------------------------------------------------- protocol

KIND = {0: "new", 1: "learning", 2: "review", 3: "relearning"}
VIDEO = {".mp4", ".webm", ".mkv", ".mov", ".avi"}
IMG_TAG = re.compile(r'<img\b[^>]*\bsrc="file://([^"]+)"[^>]*>')
A_TAG = re.compile(r"<a\b[^>]*>", re.I)
HREF = re.compile(r"(?<![-\w])href\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))", re.I)


def sanitize_links(html: str) -> str:
    """Only web and mail links stay clickable; javascript:, file: and friends lose their href."""
    def repl(match: re.Match) -> str:
        tag = match.group(0)
        found = HREF.search(tag)
        if not found:
            return tag
        href = next((g for g in found.groups() if g is not None), "")
        scheme = urlparse(href).scheme.lower()
        if scheme and scheme not in {"http", "https", "mailto"}:
            return HREF.sub("", tag, count=1)
        return tag
    return A_TAG.sub(repl, html)


def check_images(html: str) -> tuple[str, list, bool]:
    """Images that exist are listed; missing ones become a visible placeholder."""
    images: list = []
    missing = False

    def repl(match: re.Match) -> str:
        nonlocal missing
        path = unescape(match.group(1))
        if os.path.exists(path):
            images.append({"src": os.path.basename(path), "url": "file://" + path, "missing": False})
            return match.group(0)
        missing = True
        return f'<span style="color:#888">[missing image: {escape(os.path.basename(path))}]</span>'
    return IMG_TAG.sub(repl, html), images, missing


def style_typed_diff(html: str) -> str:
    """Anki's type-in comparison uses classes from its own stylesheet; Qt rich text needs inline colours."""
    html = re.sub(r"class\s*=\s*[\"']?typeGood[\"']?", 'style="color:#2e7d32;font-weight:600"', html, flags=re.I)
    html = re.sub(r"class\s*=\s*[\"']?typeMissed[\"']?", 'style="color:#c62828;text-decoration:line-through"', html, flags=re.I)
    html = re.sub(r"class\s*=\s*[\"']?typeBad[\"']?", 'style="color:#c62828;text-decoration:line-through"', html, flags=re.I)
    html = re.sub(r"class\s*=\s*[\"']?typearrow[\"']?", 'style="color:#777"', html, flags=re.I)
    return html

# Errors upstream's daemon raises as plain codes: expected outcomes, not crashes.
KNOWN_ERRORS = {
    "empty-name": "Give the deck a name.",
    "not-logged-in": "Sign in to AnkiWeb first.",
    "stale-card": "That card is no longer on screen.",
    "nothing-to-undo": "There is nothing to undo.",
    "outside-media": "That file is outside Anki's media folder.",
}
# anki.notes.NoteFieldsCheckResult
NOTE_CHECK = {
    "note-check-1": "The first field is empty.",
    "note-check-2": "This note already exists.",
    "note-check-3": "A cloze note needs at least one {{c1::...}} deletion.",
    "note-check-4": "This note type is not a cloze type.",
    "note-check-5": "This note type needs cloze text in that field.",
}

# Commands the app passes to the daemon unchanged (args is the request).
PASSTHROUGH = {
    "hello", "createDeck", "noteTypes", "addNote", "importApkg",
    "login", "logout", "sync", "fullSync", "mediaStatus", "play", "stopAudio",
}


class Backend:
    def __init__(self) -> None:
        self.d: Any = None
        self.profile = ""
        self.path: Path | None = None
        self.profiles: list[str] = []
        self.exit_requested = False

    # -- plumbing ---------------------------------------------------------------

    def need(self) -> Any:
        if self.d is None:
            raise BackendError("not_open", "No collection is open.")
        return self.d

    def dispatch(self, line: str) -> None:
        try:
            req = json.loads(line)
        except Exception as exc:
            return self.reply(None, error=BackendError("bad_request", f"invalid JSON: {exc}"))
        rid, cmd = req.get("id"), req.get("cmd")
        args = req.get("args") or {}
        if not isinstance(cmd, str) or not isinstance(args, dict):
            return self.reply(rid, error=BackendError("bad_request", "cmd must be a string and args an object"))
        handler = getattr(self, f"cmd_{cmd}", None)
        try:
            if handler is not None:
                data = handler(args)
            elif cmd in PASSTHROUGH:
                data = getattr(self.need(), f"cmd_{cmd}")(args)
            else:
                raise BackendError("bad_request", f"unknown command: {cmd}")
        except BackendError as exc:
            self.reply(rid, error=exc)
        except (ValueError, RuntimeError) as exc:
            known = KNOWN_ERRORS.get(str(exc)) or (NOTE_CHECK.get(str(exc)) if str(exc).startswith("note-check-") else None)
            if known is None:
                log(traceback.format_exc())
                self.reply(rid, error=BackendError(self.code_for(exc), self.message_for(exc), traceback.format_exc()))
            else:
                self.reply(rid, error=BackendError(str(exc).replace("-", "_"), known))
        except Exception as exc:
            log(traceback.format_exc())
            self.reply(rid, error=BackendError(self.code_for(exc), self.message_for(exc), traceback.format_exc()))
        else:
            self.reply(rid, data=data)

    @staticmethod
    def code_for(exc: Exception) -> str:
        name = type(exc).__name__
        text = str(exc).lower()
        if name == "SyncError":
            kind = str(getattr(exc, "kind", "") or "").lower()
            return "sync_auth" if "auth" in kind or "auth" in text else "sync_error"
        if name in ("NetworkError", "ConnectionError"):
            return "network"
        return "internal"

    @staticmethod
    def message_for(exc: Exception) -> str:
        return f"{type(exc).__name__}: {exc}" if str(exc) else type(exc).__name__

    def reply(self, rid: Any, data: Any = None, error: BackendError | None = None) -> None:
        if error is not None:
            err: dict[str, Any] = {"code": error.code, "message": error.message}
            if error.detail is not None:
                err["detail"] = error.detail
            write_line({"id": rid, "ok": False, "error": err})
        else:
            write_line({"id": rid, "ok": True, "data": data})

    # -- lifecycle --------------------------------------------------------------

    def cmd_open(self, args: dict) -> dict:
        if self.d is not None:
            raise BackendError("already_open", "A collection is already open in this backend.")
        if not IN_ENGINE:
            raise BackendError(
                "anki_missing", "The Anki engine is not installed.",
                {"engine": ENGINE_VENV, "installer": os.path.join(HERE, "install_engine.sh")},
            )
        path, profile, names = locate_collection(str(args.get("profile") or ""), str(args.get("collectionPath") or ""))
        if not path.exists():
            raise BackendError(
                "collection_missing", f"No Anki collection at {path}.",
                {"path": str(path), "profiles": names},
            )
        up.COLLECTION = str(path)
        try:
            self.d = up.Daemon()
        except Exception as exc:
            lowered = str(exc).lower()
            if "already open" in lowered or "locked" in lowered or "busy" in lowered:
                raise BackendError("collection_locked", "Anki is already using this collection.", str(exc)) from exc
            if "not a database" in lowered or "malformed" in lowered or "no such table" in lowered:
                raise BackendError("collection_corrupt", "Anki could not read this collection.", str(exc)) from exc
            if "unsupported" in lowered or "version" in lowered:
                raise BackendError("unsupported_version", str(exc)) from exc
            raise BackendError("internal", f"Could not open the collection: {exc}", str(exc)) from exc
        self.path, self.profile, self.profiles = path, profile, names
        theme = args.get("theme")
        if isinstance(theme, dict):
            self.d.cmd_theme(theme)
        return self.session()

    def cmd_close(self, args: dict) -> dict:
        self.shutdown()
        self.exit_requested = True
        return {"closed": True}

    def shutdown(self) -> None:
        if self.d is not None:
            try:
                self.d.close()
            except Exception as exc:
                log(f"error closing collection: {exc}")
        self.d = None

    def cmd_profiles(self, args: dict) -> dict:
        names = self.profiles
        if not names:
            for base in anki_bases():
                names = read_profile_names(base)
                if names:
                    break
        return {"profiles": names}

    def cmd_theme(self, args: dict) -> bool:
        return self.need().cmd_theme(args)

    # -- decks ------------------------------------------------------------------

    def counts(self) -> dict:
        new, learn, review = self.need().col.sched.counts()
        return {"new": int(new), "learn": int(learn), "review": int(review)}

    def deck_node(self, node: Any) -> dict:
        return {
            "id": int(node.deck_id), "name": str(node.name), "level": int(node.level),
            "collapsed": bool(node.collapsed),
            "new": int(node.new_count), "learn": int(node.learn_count), "review": int(node.review_count),
            "newUncapped": int(node.new_uncapped), "reviewUncapped": int(node.review_uncapped),
            "total": int(node.total_in_deck), "totalWithChildren": int(node.total_including_children),
            "children": [self.deck_node(child) for child in node.children],
        }

    def session(self) -> dict:
        d = self.need()
        from anki.buildinfo import version
        tree = d.col.sched.deck_due_tree()
        return {
            "version": version,
            "profile": self.profile,
            "collectionPath": str(self.path or ""),
            "mediaPath": str(d.col.media.dir()),
            "decks": self.deck_node(tree) if tree is not None else None,
            "currentDeckId": int(d.col.decks.current()["id"]),
            "counts": self.counts(),
            "cards": int(d.col.card_count()),
            "loggedIn": bool(d.auth),
            "username": (d.auth or {}).get("username", ""),
            "mathjax": bool(d.math.available),
            "studiedToday": d._studied_today(),
        }

    def cmd_decks(self, args: dict) -> dict:
        return self.session()

    def cmd_selectDeck(self, args: dict) -> dict:
        d = self.need()
        try:
            deck_id = int(args.get("deckId"))
        except Exception as exc:
            raise BackendError("bad_request", "deckId must be an integer") from exc
        if d.col.decks.get(deck_id, default=False) is None:
            raise BackendError("bad_request", f"Deck {deck_id} does not exist.")
        out = self.card_out(d.cmd_study({"deckId": deck_id}))
        out["currentDeckId"] = deck_id
        return out

    # -- cards ------------------------------------------------------------------

    def card_out(self, p: dict | None) -> dict:
        d = self.need()
        if p is None:
            return {"done": True, "counts": self.counts()}
        card = d.current[0]
        audio = self.clips(p.get("audioQ") or [], "question")
        question, images, missing_image = check_images(sanitize_links(p["question"]))
        # The daemon strips scripts; the card still says it relied on them.
        scripted = bool(re.search(r"<script\b", card.render_output(reload=False).question_text, re.I))
        payload = {
            "cardId": int(card.id), "noteId": int(card.nid), "deckId": int(card.current_deck_id()),
            "deckName": p.get("deck", ""), "kind": KIND.get(int(card.type), "review"),
            "questionHtml": question, "audio": audio, "images": images,
            "style": {"textAlign": "left", "fontSize": 0},
            "typeAnswer": p["typeIn"], "scripted": scripted,
            "marked": bool(p.get("marked")), "flag": int(p.get("flag") or 0),
            "hasMissingMedia": missing_image or any(c["missing"] for c in audio),
            "counts": p["counts"],
        }
        return {"done": False, "card": payload, "counts": payload["counts"]}

    @staticmethod
    def clips(tags: list, side: str) -> list:
        out = []
        for index, tag in enumerate(tags):
            if tag.get("kind") != "file":
                continue  # text-to-speech has no player here
            path = tag["path"]
            out.append({
                "side": side, "index": index, "filename": tag["name"],
                "url": "file://" + path if os.path.exists(path) else "",
                "missing": not os.path.exists(path),
                "video": Path(tag["name"]).suffix.lower() in VIDEO,
            })
        return out

    def cmd_card(self, args: dict) -> dict:
        return self.card_out(self.need().cmd_current({}))

    def cmd_reveal(self, args: dict) -> dict:
        d = self.need()
        if not d.current:
            raise BackendError("no_card", "There is no card to reveal.")
        typed = str(args.get("typed") or "")
        p = d.cmd_reveal({"cardId": d.current[0].id, "typed": typed})
        card = d.current[0]
        clips = self.clips(p.get("audioA") or [], "answer")
        answer, _images, _missing = check_images(sanitize_links(p["answer"]))
        typed_result = None
        info = d._type_field(card, card.render_output(reload=False).question_text) if p.get("typeIn") else None
        if info:
            diff = style_typed_diff(d.col.compare_answer(info["expected"], typed))
            typed_result = {"provided": typed, "html": diff, "correct": "color:#c62828" not in diff}
            answer = style_typed_diff(answer)
            # The comparison belongs to the question side of most templates, which the app
            # does not show again once the answer is up: put it first in the answer.
            if "typeans" not in answer:
                answer = '<div id="typeans" style="margin-top:12px">' + diff + "</div>" + answer
        return {
            "answerHtml": answer, "style": {"textAlign": "left", "fontSize": 0},
            "buttons": self.buttons(card, p.get("labels") or []),
            "audio": clips, "typedResult": typed_result, "counts": p["counts"],
        }

    def buttons(self, card: Any, labels: list) -> list:
        count = int(self.need().col.sched.answerButtons(card))
        names = {0: "Again", 1: "Hard", 2: "Good", 3: "Easy"}
        if count == 2:
            pairs = [(0, 0), (2, 1)]
        elif count == 3:
            pairs = [(0, 0), (2, 1), (3, 2)]
        else:
            pairs = [(0, 0), (1, 1), (2, 2), (3, 3)]
        return [{"rating": r, "label": names[r], "interval": labels[i] if i < len(labels) else ""} for r, i in pairs]

    def cmd_answer(self, args: dict) -> dict:
        d = self.need()
        if not d.current:
            raise BackendError("no_card", "There is no card to answer.")
        try:
            rating = int(args.get("rating", -1))
        except Exception as exc:
            raise BackendError("bad_request", "rating must be 0-3") from exc
        if rating not in (0, 1, 2, 3):
            raise BackendError("bad_request", "rating must be 0-3")
        return self.card_out(d.cmd_answer({"cardId": d.current[0].id, "ease": rating + 1}))

    def cmd_undo(self, args: dict) -> dict:
        d = self.need()
        try:
            return self.card_out(d.cmd_undo({}))
        except RuntimeError as exc:
            raise BackendError("nothing_to_undo", "There is nothing to undo.") from exc

    def cmd_cardAction(self, args: dict) -> dict:
        """mark | flag (1-7, toggles) | suspend | suspendNote | bury | buryNote."""
        d = self.need()
        if not d.current:
            raise BackendError("no_card", "There is no card on screen.")
        card = d.current[0]
        action = args.get("action")
        if action == "mark":
            p = d.cmd_mark({"cardId": card.id})
            return {"marked": bool(p["marked"]), "flag": int(p["flag"])}
        if action == "flag":
            value = int(args.get("flag", 0))
            if value not in range(1, 8):
                raise BackendError("bad_request", "flag must be 1-7")
            p = d.cmd_flag({"cardId": card.id, "flag": 0 if int(card.user_flag()) == value else value})
            return {"marked": bool(p["marked"]), "flag": int(p["flag"])}
        if action == "suspend":
            return self.card_out(d.cmd_suspend({"cardId": card.id}))
        if action == "suspendNote":
            d.col.sched.suspend_cards(d.col.card_ids_of_note(card.nid))
            return self.card_out(d._next())
        if action == "bury":
            return self.card_out(d.cmd_bury({"cardId": card.id}))
        if action == "buryNote":
            return self.card_out(d.cmd_bury({"cardId": card.id, "note": True}))
        raise BackendError("bad_request", f"unknown action: {action}")


def main() -> int:
    backend = Backend()

    def on_signal(signum: int, frame: Any) -> None:
        backend.shutdown()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)
    try:
        for line in sys.stdin:
            line = line.strip()
            if line:
                backend.dispatch(line)
            if backend.exit_requested:
                break
    except BrokenPipeError:
        pass
    finally:
        backend.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""JSON-line bridge between the Quickshell Anki app and Anki's Python backend.

The shell app owns the collection while its window is open. This process opens the
collection once, keeps the queued card and scheduler states in memory, and speaks one
JSON object per line over stdin/stdout. All diagnostics go to stderr.

It intentionally does not implement AnkiWeb sync; that is a separate follow-up.
"""

from __future__ import annotations

import argparse
import html as html_mod
import json
import os
import pickle
import re
import signal
import sqlite3
import sys
import traceback
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote, urlparse

try:
    from anki import buildinfo
    from anki.collection import Collection
    from anki.scheduler_pb2 import CardAnswer
except Exception as exc:  # pragma: no cover - exercised only on a broken install
    buildinfo = None
    Collection = None
    CardAnswer = None
    ANKI_IMPORT_ERROR: Exception | None = exc
else:
    ANKI_IMPORT_ERROR = None


TYPE_RE = re.compile(r"\[\[type:(.+?)\]\]", re.S)
PLAY_RE = re.compile(r"\[anki:play:[qa]:(\d+)\]")
SCRIPT_RE = re.compile(r"<script\b[^>]*>.*?</script\s*>", re.I | re.S)
UNSAFE_BLOCK_RE = re.compile(
    r"<(iframe|object|embed|video|audio)\b[^>]*>.*?</\1\s*>", re.I | re.S
)
UNSAFE_TAG_RE = re.compile(r"</?(iframe|object|embed|video|audio)\b[^>]*>", re.I)
EVENT_ATTR_RE = re.compile(r"\son[a-z]+\s*=\s*(?:\"[^\"]*\"|'[^']*'|[^\s>]+)", re.I)
HREF_RE = re.compile(
    r"(?<![-\w])href\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))", re.I
)
SRC_RE = re.compile(r"(?<![-\w])src\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s>]+))", re.I)
IMG_RE = re.compile(r"<img\b[^>]*>", re.I)
A_RE = re.compile(r"<a\b[^>]*>", re.I)


class BridgeError(Exception):
    def __init__(self, code: str, message: str, detail: Any = None):
        super().__init__(message)
        self.code = code
        self.message = message
        self.detail = detail


# Replies go to the real stdout only. Anki's library prints deprecation notices; from main() on,
# anything that writes to sys.stdout lands on stderr instead of corrupting the JSON lines.
PROTOCOL_OUT = sys.stdout


def log(message: str) -> None:
    print(message, file=sys.stderr, flush=True)


def anki_base() -> Path:
    value = os.environ.get("XDG_DATA_HOME")
    root = Path(value) if value else Path.home() / ".local" / "share"
    return root / "Anki2"


def _read_profile_names(base: Path) -> list[str]:
    prefs = base / "prefs21.db"
    if not prefs.exists():
        return []
    try:
        con = sqlite3.connect(f"file:{prefs}?mode=ro", uri=True)
        try:
            rows = con.execute(
                "select name from profiles where name != '_global' collate nocase"
            ).fetchall()
        finally:
            con.close()
    except Exception as exc:
        log(f"could not read profile names: {exc}")
        return []
    return [str(row[0]) for row in rows]


def _read_last_profile(base: Path) -> str:
    prefs = base / "prefs21.db"
    if not prefs.exists():
        return ""
    try:
        con = sqlite3.connect(f"file:{prefs}?mode=ro", uri=True)
        try:
            row = con.execute(
                "select cast(data as blob) from profiles where name = '_global' collate nocase"
            ).fetchone()
        finally:
            con.close()
    except Exception:
        return ""
    if not row or row[0] is None:
        return ""
    try:
        data = pickle.loads(row[0])
        if isinstance(data, dict):
            return str(data.get("last_loaded_profile_name") or "")
    except Exception:
        pass
    return ""


class Bridge:
    def __init__(self) -> None:
        self.col: Collection | None = None
        self.default_collection = ""
        self.default_profile = ""
        self.profile = ""
        self.collection_path: Path | None = None
        self.media_dir: Path | None = None
        self.queued = None
        self.card = None
        self.side = "closed"  # closed | idle | question | answer | done
        self.type_info: dict[str, Any] | None = None
        self.exit_requested = False

    # ------------------------------------------------------------------ wiring

    def dispatch(self, line: str) -> None:
        request: dict[str, Any]
        try:
            request = json.loads(line)
        except Exception as exc:
            self._respond(None, error=BridgeError("bad_request", f"invalid JSON: {exc}"))
            return

        request_id = request.get("id")
        command = request.get("cmd")
        args = request.get("args") or {}
        if not isinstance(args, dict):
            self._respond(request_id, error=BridgeError("bad_request", "args must be an object"))
            return
        if not isinstance(command, str):
            self._respond(request_id, error=BridgeError("bad_request", "missing cmd"))
            return

        handler = getattr(self, f"cmd_{command}", None)
        if handler is None:
            self._respond(request_id, error=BridgeError("bad_request", f"unknown command: {command}"))
            return

        try:
            data = handler(args)
        except BridgeError as exc:
            self._respond(request_id, error=exc)
        except Exception as exc:
            log(traceback.format_exc())
            self._respond(
                request_id,
                error=BridgeError("internal", f"{type(exc).__name__}: {exc}", traceback.format_exc()),
            )
        else:
            self._respond(request_id, data=data)

    def _respond(self, request_id: Any, data: Any = None, error: BridgeError | None = None) -> None:
        if error is not None:
            payload: dict[str, Any] = {
                "id": request_id,
                "ok": False,
                "error": {"code": error.code, "message": error.message},
            }
            if error.detail is not None:
                payload["error"]["detail"] = error.detail
        else:
            payload = {"id": request_id, "ok": True, "data": data}
        try:
            PROTOCOL_OUT.write(json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n")
            PROTOCOL_OUT.flush()
        except BrokenPipeError:
            self.exit_requested = True

    # ---------------------------------------------------------------- lifecycle

    def _require_open(self) -> Collection:
        if self.col is None:
            raise BridgeError("not_open", "No collection is open.")
        return self.col

    def _close_collection(self) -> None:
        if self.col is not None:
            try:
                self.col.close()
            except Exception as exc:
                log(f"error closing collection: {exc}")
        self.col = None
        self.queued = None
        self.card = None
        self.side = "closed"
        self.type_info = None
        self.collection_path = None
        self.media_dir = None

    def shutdown(self) -> None:
        self._close_collection()
        self.exit_requested = True

    def cmd_ping(self, args: dict[str, Any]) -> dict[str, Any]:
        return {
            "version": getattr(buildinfo, "version", "unknown") if buildinfo else "missing",
            "open": self.col is not None,
        }

    def cmd_profiles(self, args: dict[str, Any]) -> dict[str, Any]:
        base = anki_base()
        return {"profiles": _read_profile_names(base), "last": _read_last_profile(base)}

    def cmd_open(self, args: dict[str, Any]) -> dict[str, Any]:
        if self.col is not None:
            raise BridgeError("already_open", "A collection is already open in this bridge.")
        if Collection is None:
            raise BridgeError(
                "anki_missing",
                "The Anki Python backend is not installed.",
                str(ANKI_IMPORT_ERROR) if ANKI_IMPORT_ERROR else None,
            )

        requested = str(args.get("profile") or self.default_profile or "")
        explicit_path = str(args.get("collectionPath") or self.default_collection or "").strip()

        if explicit_path:
            path = Path(os.path.expanduser(explicit_path))
            if path.is_dir():
                path = path / "collection.anki2"
            profile = requested or path.parent.name
        else:
            base = anki_base()
            profiles = _read_profile_names(base)
            profile = requested or _read_last_profile(base)
            if not profile:
                profile = "User 1" if "User 1" in profiles else (profiles[0] if profiles else "")
            if not profile:
                raise BridgeError(
                    "no_profiles",
                    "Anki has no profiles yet. Open Anki once, then try again.",
                    {"base": str(base)},
                )
            path = base / profile / "collection.anki2"

        if not path.exists():
            raise BridgeError(
                "collection_missing",
                f"No Anki collection at {path}.",
                {"path": str(path), "profiles": _read_profile_names(anki_base())},
            )

        try:
            self.col = Collection(str(path))
        except Exception as exc:
            message = str(exc)
            lowered = message.lower()
            if "already open" in lowered or "media currently syncing" in lowered:
                raise BridgeError(
                    "collection_locked",
                    "Anki is already using this collection.",
                    message,
                ) from exc
            if "not a database" in lowered or "malformed" in lowered or "no such table" in lowered:
                raise BridgeError(
                    "collection_corrupt",
                    "Anki could not read this collection.",
                    message,
                ) from exc
            if "unsupported" in lowered or "version" in lowered:
                raise BridgeError("unsupported_version", message) from exc
            raise BridgeError("internal", f"Could not open the collection: {message}", message) from exc

        self.profile = profile
        self.collection_path = path
        self.media_dir = path.parent / "collection.media"
        self.queued = None
        self.card = None
        self.side = "idle"
        self.type_info = None
        return self._session_payload()

    def cmd_close(self, args: dict[str, Any]) -> dict[str, Any]:
        self._close_collection()
        self.exit_requested = True
        return {"closed": True}

    # ------------------------------------------------------------------- decks

    def cmd_decks(self, args: dict[str, Any]) -> dict[str, Any]:
        return self._session_payload()

    def cmd_selectDeck(self, args: dict[str, Any]) -> dict[str, Any]:
        col = self._require_open()
        raw_id = args.get("deckId")
        try:
            deck_id = int(raw_id)
        except Exception as exc:
            raise BridgeError("bad_request", "deckId must be an integer") from exc
        if col.decks.get(deck_id, default=False) is None:
            raise BridgeError("bad_request", f"Deck {deck_id} does not exist.")
        col.decks.select(deck_id)
        self.queued = None
        self.card = None
        self.side = "idle"
        self.type_info = None
        return self._next_card_payload()

    def _session_payload(self) -> dict[str, Any]:
        col = self._require_open()
        current = col.decks.current()
        tree = col.sched.deck_due_tree()
        return {
            "version": getattr(buildinfo, "version", "unknown") if buildinfo else "unknown",
            "profile": self.profile,
            "collectionPath": str(self.collection_path or ""),
            "mediaPath": str(self.media_dir or ""),
            "decks": self._deck_node(tree) if tree is not None else None,
            "currentDeckId": int(current["id"]),
            "counts": self._counts(),
        }

    def _counts(self) -> dict[str, int]:
        col = self._require_open()
        new, learn, review = col.sched.counts()
        return {"new": int(new), "learn": int(learn), "review": int(review)}

    def _deck_node(self, node: Any) -> dict[str, Any]:
        return {
            "id": int(node.deck_id),
            "name": str(node.name),
            "level": int(node.level),
            "collapsed": bool(node.collapsed),
            "new": int(node.new_count),
            "learn": int(node.learn_count),
            "review": int(node.review_count),
            "newUncapped": int(node.new_uncapped),
            "reviewUncapped": int(node.review_uncapped),
            "total": int(node.total_in_deck),
            "totalWithChildren": int(node.total_including_children),
            "children": [self._deck_node(child) for child in node.children],
        }

    # ------------------------------------------------------------------- cards

    def cmd_card(self, args: dict[str, Any]) -> dict[str, Any]:
        self._require_open()
        return self._next_card_payload()

    def _next_card_payload(self) -> dict[str, Any]:
        col = self._require_open()
        if self.queued is not None:
            return self._card_payload(self.queued)

        queued = col.sched.get_queued_cards(fetch_limit=1)
        if not queued.cards:
            self.queued = None
            self.card = None
            self.side = "done"
            self.type_info = None
            return {"done": True, "counts": self._counts()}

        self.queued = queued.cards[0]
        self.card = col.get_card(self.queued.card.id)
        self.card.start_timer()
        self.side = "question"
        self.type_info = None
        return self._card_payload(self.queued)

    def _card_payload(self, queued: Any) -> dict[str, Any]:
        card = self.card
        deck_name = str(getattr(queued.context, "deck_name", "") or "")
        if not deck_name:
            deck = self._require_open().decks.get(card.did, default=False)
            deck_name = str(deck.get("name", "")) if deck else ""

        prepared = self._prepare_html(card.question(), "question")
        question_audio = self._audio_tags(card.question_av_tags(), "question")
        self.type_info = prepared.get("type")
        public_type = None
        if self.type_info is not None:
            public_type = {
                key: value
                for key, value in self.type_info.items()
                if key != "expected"
            }
        kind_map = {0: "new", 1: "learning", 2: "review", 3: "relearning"}
        payload = {
            "cardId": int(card.id),
            "noteId": int(card.nid),
            "deckId": int(card.did),
            "deckName": deck_name,
            "kind": kind_map.get(int(card.type), "review"),
            "questionHtml": prepared["html"],
            "audio": question_audio,
            "images": prepared["images"],
            "style": prepared["style"],
            "typeAnswer": public_type,
            "scripted": prepared["scripted"],
            "marked": bool(self._require_open().get_note(card.nid).has_tag("marked")),
            "flag": int(card.user_flag()),
            "hasMissingMedia": prepared["missing"] or any(
                clip.get("missing", False) for clip in question_audio
            ),
            "counts": self._counts(),
        }
        return {"done": False, "card": payload, "counts": payload["counts"]}

    def cmd_reveal(self, args: dict[str, Any]) -> dict[str, Any]:
        col = self._require_open()
        if self.queued is None:
            raise BridgeError("no_card", "There is no card to reveal.")
        if self.side == "answer":
            # Idempotent: the UI may retry after a dropped response.
            return self._answer_payload(col, args)
        if self.side != "question":
            raise BridgeError("no_card", "There is no question to reveal.")

        self.side = "answer"
        return self._answer_payload(col, args)

    def _answer_payload(self, col: Collection, args: dict[str, Any]) -> dict[str, Any]:
        queued = self.queued
        card = self.card
        raw_answer = card.answer()
        typed = args.get("typed")
        typed_result = None

        if self.type_info is not None:
            provided = "" if typed is None else str(typed)
            expected = str(self.type_info.get("expected", ""))
            combining = bool(self.type_info.get("combining", True))
            try:
                diff = col.compare_answer(expected, provided, combining)
            except Exception as exc:
                raise BridgeError("internal", f"Could not compare the typed answer: {exc}") from exc
            correct = "typeMissed" not in diff
            diff = self._style_typed_diff(diff)
            typed_result = {"provided": provided, "html": diff, "correct": correct}
            replacement = (
                '<div id="typeans" style="margin-top:12px">'
                + diff
                + "</div>"
            )
            # The QML review pane shows only the answer side (everything after Anki's
            # answer rule). Put the typed comparison there, even when the type marker
            # came from the question side.
            raw_answer = TYPE_RE.sub("", raw_answer, count=1)
            answer_rule = re.search(
                r"<hr[^>]*\bid\s*=\s*[\"']?answer[\"']?[^>]*>",
                raw_answer,
                re.I,
            )
            if answer_rule:
                raw_answer = (
                    raw_answer[: answer_rule.end()]
                    + replacement
                    + raw_answer[answer_rule.end() :]
                )
            else:
                raw_answer = raw_answer + replacement

        prepared = self._prepare_html(raw_answer, "answer")
        return {
            "answerHtml": prepared["html"],
            "style": prepared["style"],
            "buttons": self._buttons(),
            "audio": self._audio_tags(card.answer_av_tags(), "answer"),
            "typedResult": typed_result,
            "counts": self._counts(),
        }

    def _buttons(self) -> list[dict[str, Any]]:
        col = self._require_open()
        count = int(col.sched.answerButtons(self.card))
        labels = [str(label) for label in col.sched.describe_next_states(self.queued.states)]
        names = {0: "Again", 1: "Hard", 2: "Good", 3: "Easy"}
        if count == 2:
            pairs = [(0, 0), (2, 1)]
        elif count == 3:
            pairs = [(0, 0), (2, 1), (3, 2)]
        else:
            pairs = [(0, 0), (1, 1), (2, 2), (3, 3)]
        return [
            {
                "rating": rating,
                "label": names[rating],
                "interval": labels[index] if index < len(labels) else "",
            }
            for rating, index in pairs
        ]

    def cmd_answer(self, args: dict[str, Any]) -> dict[str, Any]:
        col = self._require_open()
        if self.queued is None:
            raise BridgeError("no_card", "There is no card to answer.")
        if self.side != "answer":
            raise BridgeError("answer_not_ready", "Reveal the answer first.")
        try:
            rating = int(args.get("rating", -1))
        except Exception as exc:
            raise BridgeError("bad_request", "rating must be 0-3") from exc
        if rating not in (0, 1, 2, 3):
            raise BridgeError("bad_request", "rating must be 0-3")

        try:
            answer = col.sched.build_answer(
                card=self.card,
                states=self.queued.states,
                rating=rating,
            )
            col.sched.answer_card(answer)
        except Exception as exc:
            raise BridgeError("internal", f"Anki rejected the answer: {exc}") from exc

        self.queued = None
        self.card = None
        self.side = "idle"
        self.type_info = None
        return self._next_card_payload()

    def cmd_undo(self, args: dict[str, Any]) -> dict[str, Any]:
        col = self._require_open()
        try:
            changed = col.undo()
        except Exception as exc:
            raise BridgeError("nothing_to_undo", f"Could not undo: {exc}") from exc
        if changed is False or changed is None:
            raise BridgeError("nothing_to_undo", "There is nothing to undo.")
        self.queued = None
        self.card = None
        self.side = "idle"
        self.type_info = None
        return self._next_card_payload()

    def cmd_cardAction(self, args: dict[str, Any]) -> dict[str, Any]:
        """Mark, flag, suspend or bury the card on screen (all undoable with `undo`).

        mark and flag keep the card; the others send it away and return the next one.
        """
        col = self._require_open()
        if self.card is None or self.queued is None:
            raise BridgeError("no_card", "There is no card on screen.")
        action = args.get("action")
        card = self.card
        card_id = int(card.id)
        note_id = int(card.nid)
        try:
            if action == "mark":
                note = col.get_note(note_id)
                if note.has_tag("marked"):
                    col.tags.bulk_remove([note_id], "marked")
                else:
                    col.tags.bulk_add([note_id], "marked")
                return {"marked": bool(col.get_note(note_id).has_tag("marked")), "flag": int(card.user_flag())}
            if action == "flag":
                value = int(args.get("flag", 0))
                if value not in (1, 2, 3, 4, 5, 6, 7):
                    raise BridgeError("bad_request", "flag must be 1-7")
                new_flag = 0 if int(card.user_flag()) == value else value
                col.set_user_flag_for_cards(new_flag, [card_id])
                card.load()
                return {"marked": bool(col.get_note(note_id).has_tag("marked")), "flag": new_flag}
            if action == "suspend":
                col.sched.suspend_cards([card_id])
            elif action == "suspendNote":
                col.sched.suspend_cards(col.card_ids_of_note(note_id))
            elif action == "bury":
                col.sched.bury_cards([card_id])
            elif action == "buryNote":
                col.sched.bury_cards(col.card_ids_of_note(note_id))
            else:
                raise BridgeError("bad_request", f"unknown action: {action}")
        except BridgeError:
            raise
        except Exception as exc:
            raise BridgeError("internal", f"Anki rejected the action: {exc}") from exc

        self.queued = None
        self.card = None
        self.side = "idle"
        self.type_info = None
        return self._next_card_payload()

    # ------------------------------------------------------------------ render

    def _prepare_html(self, raw: str, side: str) -> dict[str, Any]:
        missing = False
        scripted = bool(re.search(r"<script\b", raw, re.I))
        raw = SCRIPT_RE.sub("", raw)
        raw = UNSAFE_BLOCK_RE.sub("", raw)
        raw = UNSAFE_TAG_RE.sub("", raw)
        raw = EVENT_ATTR_RE.sub("", raw)
        raw = re.sub(r"\s+srcdoc\s*=\s*(?:\"[^\"]*\"|'[^']*'|[^\s>]+)", "", raw, flags=re.I)

        type_info = None
        if side == "question":
            match = TYPE_RE.search(raw)
            if match:
                type_info = self._type_metadata(match.group(1))
            raw = TYPE_RE.sub("", raw, count=1)
        else:
            raw = TYPE_RE.sub("", raw)

        raw = PLAY_RE.sub("", raw)
        raw = self._sanitize_links(raw)

        images: list[dict[str, Any]] = []

        def image_replacement(match: re.Match[str]) -> str:
            nonlocal missing
            tag = match.group(0)
            src = self._attr_value(tag, SRC_RE)
            if not src:
                return tag
            path = self._media_path(src)
            if path is None or not path.exists():
                missing = True
                name = html_mod.escape(src)
                return f'<span style="color:#888">[missing image: {name}]</span>'
            url = self._file_url(path)
            images.append({"src": src, "url": url, "missing": False})
            return self._rewrite_image_tag(tag, url, path)

        raw = IMG_RE.sub(image_replacement, raw)
        return {
            "html": raw,
            "scripted": scripted,
            "images": images,
            "missing": missing,
            "type": type_info,
            "style": self._base_style(raw),
        }

    @staticmethod
    def _base_style(raw: str) -> dict[str, Any]:
        """The small part of Anki's .card CSS that Qt rich text can reliably use."""
        style: dict[str, Any] = {"textAlign": "left", "fontSize": 0}
        match = re.search(r"\.card\s*\{([^}]*)\}", raw, re.I | re.S)
        if not match:
            return style
        body = match.group(1)
        align = re.search(r"text-align\s*:\s*(left|center|right)", body, re.I)
        if align:
            style["textAlign"] = align.group(1).lower()
        size = re.search(r"font-size\s*:\s*([0-9.]+)px", body, re.I)
        if size:
            try:
                style["fontSize"] = max(10, min(48, int(float(size.group(1)))))
            except ValueError:
                pass
        return style

    def _type_metadata(self, token: str) -> dict[str, Any] | None:
        field = token.strip()
        cloze = False
        combining = True
        if field.startswith("cloze:"):
            cloze = True
            field = field[len("cloze:"):]
        elif field.startswith("nc:"):
            combining = False
            field = field[len("nc:"):]

        if not field or self.queued is None:
            return None
        try:
            note = self.card.note()
            if field not in note:
                return None
            expected = str(note[field])
        except Exception:
            return None
        if not expected:
            return None
        if cloze:
            try:
                expected = self._require_open().extract_cloze_for_typing(
                    expected, int(self.card.ord) + 1
                )
            except Exception:
                return None
        return {
            "field": field,
            "clozeOrdinal": (int(self.card.ord) + 1) if cloze else None,
            "combining": combining,
            "expected": expected,
        }

    def _audio_tags(self, tags: Any, side: str) -> list[dict[str, Any]]:
        result: list[dict[str, Any]] = []
        for index, tag in enumerate(tags or []):
            filename = str(getattr(tag, "filename", "") or "")
            if not filename:
                continue
            path = self._media_path(filename)
            exists = path is not None and path.exists()
            url = self._file_url(path) if exists else ""
            video = Path(filename).suffix.lower() in {".mp4", ".webm", ".mkv", ".mov", ".avi"}
            result.append(
                {
                    "side": side,
                    "index": index,
                    "filename": filename,
                    "url": url,
                    "missing": not exists,
                    "video": video,
                }
            )
        return result

    @staticmethod
    def _style_typed_diff(raw: str) -> str:
        raw = re.sub(
            r"class\s*=\s*[\"']?typeGood[\"']?",
            'style="color:#2e7d32;font-weight:600"',
            raw,
            flags=re.I,
        )
        raw = re.sub(
            r"class\s*=\s*[\"']?typeMissed[\"']?",
            'style="color:#c62828;text-decoration:line-through"',
            raw,
            flags=re.I,
        )
        raw = re.sub(
            r"class\s*=\s*[\"']?typearrow[\"']?",
            'style="color:#777"',
            raw,
            flags=re.I,
        )
        return raw

    def _sanitize_links(self, raw: str) -> str:
        def repl(match: re.Match[str]) -> str:
            tag = match.group(0)
            href = self._attr_value(tag, HREF_RE)
            if not href:
                return tag
            scheme = urlparse(href).scheme.lower()
            if scheme and scheme not in {"http", "https", "mailto"}:
                return HREF_RE.sub("", tag, count=1)
            return tag

        return A_RE.sub(repl, raw)

    def _rewrite_image_tag(self, tag: str, url: str, path: Path) -> str:
        tag = SRC_RE.sub("", tag, count=1)
        tag = re.sub(r"\s(width|height)\s*=\s*(?:\"[^\"]*\"|'[^']*'|[^\s>]+)", "", tag, flags=re.I)
        width = 0
        try:
            from PIL import Image

            with Image.open(path) as image:
                width = int(image.width)
        except Exception:
            width = 0
        suffix = "/>" if tag.rstrip().endswith("/>") else ">"
        body = tag.rstrip()[: -len(suffix)] if suffix in tag else tag.rstrip()
        if width > 600:
            body += ' width="600"'
        return f'{body} src="{url}"{suffix}'

    def _media_path(self, name: str) -> Path | None:
        if self.media_dir is None:
            return None
        clean = unquote(str(name).split("?")[0].split("#")[0])
        if not clean:
            return None
        try:
            media = self.media_dir.resolve()
            candidate = (self.media_dir / clean).resolve()
        except Exception:
            return None
        if candidate != media and media not in candidate.parents:
            return None
        return candidate

    @staticmethod
    def _file_url(path: Path | None) -> str:
        if path is None:
            return ""
        return "file://" + quote(str(path), safe="/")

    @staticmethod
    def _attr_value(tag: str, pattern: re.Pattern[str]) -> str:
        match = pattern.search(tag)
        if not match:
            return ""
        for value in match.groups():
            if value is not None:
                return html_mod.unescape(value)
        return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--collection", default="")
    parser.add_argument("--profile", default="")
    args = parser.parse_args()
    sys.stdout = sys.stderr

    bridge = Bridge()
    bridge.default_collection = args.collection
    bridge.default_profile = args.profile

    def on_signal(signum: int, frame: Any) -> None:
        bridge.shutdown()
        raise SystemExit(0)

    signal.signal(signal.SIGTERM, on_signal)
    signal.signal(signal.SIGINT, on_signal)

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            bridge.dispatch(line)
            if bridge.exit_requested:
                break
    except BrokenPipeError:
        pass
    finally:
        bridge.shutdown()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

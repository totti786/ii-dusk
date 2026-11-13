#!/usr/bin/env python3
"""Z-Library source adapter for the Books app.

The Browse protocol (see opds.py) is source-agnostic: a page is
{title, entries, detail, next, search}; an entry is
{kind, title, author, cover, thumb, formats[{ext,label,size,href}], summary}.
This module produces that shape from books-cli's JSON interface (see bookscli.py).

Nothing here reads or stores tokens: only the CLI (with its 0600 config) does.
"""

from __future__ import annotations

import json
import re
import urllib.parse

from bookscli import SourceError
import bookscli

PAGE_SIZE = 20
SUPPORTED_EXTS = {"pdf", "epub", "djvu", "cbz"}
SEARCH_TIMEOUT = 120
FETCH_TIMEOUT = 600
LOGIN_TIMEOUT = 120
SETTINGS_TIMEOUT = 30
LINK_RE = re.compile(r"^zlib://([^/?#]+)/([^/?#]+)$")


def _run(args: list[str], stdin_text: str | None = None,
         timeout: int = 60) -> tuple[int, dict]:
    return bookscli.run("zlib", args, timeout, stdin_text)


def status() -> dict:
    _code, data = _run(["status", "--json"], timeout=SEARCH_TIMEOUT)
    if data.get("ok") is False:
        raise SourceError("zlib", data.get("message") or "books-cli status failed")
    if not data.get("loggedIn") and data.get("reason") == "unreachable":
        raise SourceError("mirror", data.get("message") or "the mirror is unreachable")
    return data


def settings(domain: str | None = None) -> dict:
    args = ["config", "--json"]
    if domain is not None:
        args.append(f"--domain={domain}")
    _code, data = _run(args, timeout=SETTINGS_TIMEOUT)
    if data.get("ok") is False:
        raise SourceError("settings", data.get("message") or "could not save the settings")
    return data


def login(payload: dict) -> dict:
    _code, data = _run(["login", "--json"], stdin_text=json.dumps(payload),
                       timeout=LOGIN_TIMEOUT)
    if not data:
        raise SourceError("login", "books-cli returned no answer")
    return data


def _page_title(quota) -> str:
    return "Z-Library" if quota is None else f"Z-Library · {quota} left today"


def _search_target(query: str, url: str) -> tuple[str, int]:
    if url:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme == "zlib" and parsed.netloc == "search":
            qs = urllib.parse.parse_qs(parsed.query)
            query = (qs.get("q") or [query])[0]
            try:
                page = max(1, int((qs.get("page") or ["1"])[0]))
            except ValueError:
                page = 1
            return query, page
    return query, 1


def _signed_out_page(message: str) -> dict:
    return {"ok": True, "title": "Z-Library · sign in", "entries": [], "detail": None,
            "next": "", "search": False, "loggedIn": False,
            "message": message or "Sign in to Z-Library."}


def _entry(row: dict) -> dict | None:
    ext = str(row.get("extension") or "").lower().lstrip(".")
    if ext not in SUPPORTED_EXTS:
        return None
    book_id = row.get("id")
    book_hash = row.get("hash")
    if not book_id or not book_hash:
        return None
    try:
        size = int(row.get("filesize") or 0)
    except (TypeError, ValueError):
        size = 0
    cover = str(row.get("cover") or "")
    return {
        "kind": "book",
        "title": str(row.get("title") or "Untitled"),
        "author": str(row.get("author") or ""),
        "cover": cover,
        "thumb": cover,
        "summary": str(row.get("description") or ""),
        "formats": [{"ext": ext, "label": ext.upper(), "size": size,
                     "href": f"zlib://{book_id}/{book_hash}"}],
        "related": [],
        "href": "",
    }


def browse(query: str = "", url: str = "") -> dict:
    query, page = _search_target(query, url)
    state = status()
    if not state.get("loggedIn"):
        return _signed_out_page(state.get("message", ""))
    if not query:
        return {"ok": True, "title": _page_title(state.get("quota")), "entries": [],
                "detail": None, "next": "", "search": True, "loggedIn": True}
    _code, data = _run(
        ["search", "--json", "--limit", str(PAGE_SIZE), "--page", str(page),
         "--ext=pdf,epub,djvu,cbz", "--", query],
        timeout=SEARCH_TIMEOUT,
    )
    if data.get("ok") is not True:
        if data.get("error") == "auth":
            state = status()
            if not state.get("loggedIn"):
                return _signed_out_page(state.get("message", ""))
        raise SourceError(data.get("error") or "search",
                          data.get("message") or "The search failed.")
    rows = data.get("books") or []
    entries = [entry for entry in (_entry(row) for row in rows) if entry is not None]
    next_url = ""
    if len(rows) >= PAGE_SIZE:
        next_url = f"zlib://search?q={urllib.parse.quote_plus(query)}&page={page + 1}"
    return {"ok": True, "title": _page_title(state.get("quota")), "entries": entries,
            "detail": None, "next": next_url, "search": True, "loggedIn": True}


def download(url: str, dest: str, title: str, author: str, ext: str) -> dict:
    match = LINK_RE.match(url or "")
    if not match:
        raise SourceError("bad_link", "The download link is not valid.")
    book_id, book_hash = match.groups()
    _code, data = _run(
        ["fetch", "--json", f"--id={book_id}", f"--hash={book_hash}",
         f"--dir={dest}", f"--title={title}", f"--author={author}", f"--ext={ext}"],
        timeout=FETCH_TIMEOUT,
    )
    if data.get("ok") is True:
        return {"done": True, "path": data.get("path", ""), "size": data.get("size", 0)}
    if data.get("error") == "auth":
        raise SourceError("auth", data.get("message") or "Sign in to Z-Library.")
    raise SourceError(data.get("error") or "download",
                      data.get("message") or "The download failed.")

#!/usr/bin/env python3
"""Library Genesis source adapter for the Books app.

Produces the same page shape as zlib_source (see opds.py) from books-cli's JSON
interface. LibGen needs no account; books-cli picks a working mirror itself.
"""

from __future__ import annotations

import re
import urllib.parse

import bookscli
from bookscli import SourceError
from zlib_source import SUPPORTED_EXTS

PAGE_SIZE = 20
SEARCH_TIMEOUT = 120
FETCH_TIMEOUT = 600
LINK_RE = re.compile(r"^libgen://([^/?#]*)/([^/?#]*)$")


def _run(args: list[str], timeout: int) -> dict:
    return bookscli.run("libgen", args, timeout)[1]


def _search_target(query: str, url: str) -> tuple[str, int]:
    if url:
        parsed = urllib.parse.urlparse(url)
        if parsed.scheme == "libgen" and parsed.netloc == "search":
            qs = urllib.parse.parse_qs(parsed.query)
            try:
                page = max(1, int((qs.get("page") or ["1"])[0]))
            except ValueError:
                page = 1
            return (qs.get("q") or [query])[0], page
    return query, 1


def _size(text: str) -> int:
    match = re.match(r"([\d.]+)\s*([KMG]?)B", str(text or "").strip(), re.I)
    if not match:
        return 0
    unit = {"": 1, "K": 1024, "M": 1024 ** 2, "G": 1024 ** 3}[match.group(2).upper()]
    return int(float(match.group(1)) * unit)


def _entry(row: dict) -> dict | None:
    ext = str(row.get("extension") or "").lower().lstrip(".")
    if ext not in SUPPORTED_EXTS or not (row.get("id") or row.get("hash")):
        return None
    year = str(row.get("year") or "")
    language = str(row.get("language") or "")
    summary = " · ".join(part for part in (year, language) if part)
    return {
        "kind": "book",
        "title": str(row.get("title") or "Untitled"),
        "author": str(row.get("author") or ""),
        "cover": "", "thumb": "",
        "summary": summary,
        "formats": [{"ext": ext, "label": ext.upper(), "size": _size(row.get("size")),
                     "href": f"libgen://{row.get('id') or ''}/{row.get('hash') or ''}"}],
        "related": [],
        "href": "",
    }


def browse(query: str = "", url: str = "") -> dict:
    query, page = _search_target(query, url)
    page_info = {"title": "Library Genesis", "detail": None, "search": True}
    if not query:
        return {"ok": True, "entries": [], "next": "", **page_info}
    data = _run(["search", "--json", "--limit", str(PAGE_SIZE), "--page", str(page),
                 "--ext", "pdf,epub,djvu,cbz", "--", query], SEARCH_TIMEOUT)
    if data.get("ok") is not True:
        raise SourceError(data.get("error") or "search", data.get("message") or "The search failed.")
    rows = data.get("books") or []
    entries = [entry for entry in (_entry(row) for row in rows) if entry is not None]
    next_url = ""
    if len(rows) >= PAGE_SIZE:
        next_url = f"libgen://search?q={urllib.parse.quote_plus(query)}&page={page + 1}"
    return {"ok": True, "entries": entries, "next": next_url, **page_info}


def download(url: str, dest: str, title: str, author: str, ext: str) -> dict:
    match = LINK_RE.match(url or "")
    if not match:
        raise SourceError("bad_link", "The download link is not valid.")
    book_id, book_hash = match.groups()
    args = ["fetch", "--json", f"--dir={dest}", f"--title={title}", f"--author={author}", f"--ext={ext}"]
    args.append(f"--md5={book_hash}" if book_hash else f"--id={book_id}")
    data = _run(args, FETCH_TIMEOUT)
    if data.get("ok") is True:
        return {"done": True, "path": data.get("path", ""), "size": data.get("size", 0)}
    raise SourceError(data.get("error") or "download", data.get("message") or "The download failed.")

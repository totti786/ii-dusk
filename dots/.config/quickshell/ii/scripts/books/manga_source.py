#!/usr/bin/env python3
"""Manga downloads for the Books app, direct from the MangaDex API.

This is the same pipeline mangal's built-in Mangadex source uses, without the CLI:

  search       GET /manga?title=...&includes[]=cover_art,author,artist
  chapters     GET /manga/{id}/feed?translatedLanguage[]=en&order[chapter]=asc
  pages        GET /at-home/server/{chapterId}, then the page files from the node
  packaging    one CBZ per chapter, pages as 000000.ext, plus ComicInfo.xml
  library      <books>/Manga/<manga>/[0000] Chapter 0 - Prologue.cbz + cover.jpg

Only public MangaDex endpoints are used. External/paid chapters are skipped because
MangaDex does not serve their pages.
"""

from __future__ import annotations

import base64
import concurrent.futures
import html
import json
import os
import re
import shutil
import tempfile
import time
import urllib.error
import urllib.parse
import urllib.request
import xml.sax.saxutils
import zipfile
from pathlib import Path

API = "https://api.mangadex.org"
UPLOADS = "https://uploads.mangadex.org"
USER_AGENT = "ii-books/2.0 (Quickshell; manga reader)"
TIMEOUT = 30
SEARCH_LIMIT = 24
FEED_LIMIT = 500
LANGUAGE = os.environ.get("II_MANGA_LANGUAGE", "en").strip() or "en"
RATINGS = ("safe", "suggestive")
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".gif", ".avif"}
CACHE_HOME = Path(os.environ.get("XDG_CACHE_HOME", Path.home() / ".cache"))
COVER_CACHE = CACHE_HOME / "ii-books" / "manga-covers"


class MangaError(RuntimeError):
    pass


# ------------------------------------------------------------------ HTTP


def _headers(accept: str = "application/json") -> dict[str, str]:
    return {
        "User-Agent": USER_AGENT,
        "Accept": accept,
    }


def _sleep_for_retry(error: urllib.error.HTTPError, attempt: int) -> None:
    retry_after = error.headers.get("Retry-After") if error.headers else None
    try:
        delay = float(retry_after) if retry_after else 1.5 * (attempt + 1)
    except (TypeError, ValueError):
        delay = 1.5 * (attempt + 1)
    time.sleep(max(0.5, min(delay, 15.0)))


def _request_json(url: str, params: dict | None = None) -> dict:
    if params:
        query = urllib.parse.urlencode(params, doseq=True)
        url = url + ("&" if "?" in url else "?") + query
    request = urllib.request.Request(url, headers=_headers())
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code == 429 or 500 <= error.code < 600:
                _sleep_for_retry(error, attempt)
                continue
            raise MangaError(f"MangaDex returned HTTP {error.code}.") from error
        except (urllib.error.URLError, TimeoutError, ValueError) as error:
            last_error = error
            time.sleep(1.0 * (attempt + 1))
    raise MangaError("MangaDex did not answer." if last_error is None else str(last_error))


def _download(url: str, target: Path, accept: str = "image/*") -> int:
    request = urllib.request.Request(url, headers=_headers(accept))
    target.parent.mkdir(parents=True, exist_ok=True)
    partial = target.with_name(target.name + ".part")
    last_error: Exception | None = None
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=TIMEOUT) as response, open(partial, "wb") as out:
                received = 0
                while True:
                    chunk = response.read(128 * 1024)
                    if not chunk:
                        break
                    out.write(chunk)
                    received += len(chunk)
                if received == 0:
                    raise MangaError("MangaDex sent an empty page.")
            partial.replace(target)
            return received
        except urllib.error.HTTPError as error:
            last_error = error
            if error.code == 429 or 500 <= error.code < 600:
                _sleep_for_retry(error, attempt)
                continue
            break
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            last_error = error
            time.sleep(1.0 * (attempt + 1))
    partial.unlink(missing_ok=True)
    raise MangaError(f"Could not download a page: {last_error}")


# ------------------------------------------------------------------ metadata


def _safe_name(text: str, limit: int = 160) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|\x00-\x1f]+', " ", str(text))
    cleaned = re.sub(r"\s+", " ", cleaned).strip(" .")
    return cleaned[:limit] or "manga"


def _first_text(mapping: dict | None) -> str:
    if not isinstance(mapping, dict):
        return ""
    for key in (LANGUAGE, "en", "ja-ro", "ja", "ko", "zh", "zh-hk", "es", "pt-br", "fr"):
        value = mapping.get(key)
        if isinstance(value, str) and value.strip():
            return value.strip()
    for value in mapping.values():
        if isinstance(value, str) and value.strip():
            return value.strip()
    return ""


def _title(attributes: dict) -> str:
    title = _first_text(attributes.get("title"))
    if title:
        return title
    for alt in attributes.get("altTitles") or []:
        alt_title = _first_text(alt)
        if alt_title:
            return alt_title
    return "Untitled manga"


def _description(attributes: dict) -> str:
    text = _first_text(attributes.get("description"))
    if not text:
        return ""
    text = re.sub(r"<[^>]+>", "", text)
    return html.unescape(text).strip()


def _cover_url(manga_id: str, relationships: list) -> str:
    for relationship in relationships or []:
        if relationship.get("type") == "cover_art":
            filename = (relationship.get("attributes") or {}).get("fileName")
            if filename:
                return f"{UPLOADS}/covers/{manga_id}/{filename}.512.jpg"
    return ""


def _cover_url_small(manga_id: str, relationships: list) -> str:
    large = _cover_url(manga_id, relationships)
    return large.replace(".512.jpg", ".256.jpg") if large.endswith(".512.jpg") else large


def _cache_cover(url: str, manga_id: str, size: int) -> str:
    """Cache a MangaDex cover locally; Qt's image loader does not send a Referer."""
    if not url:
        return ""
    if url.startswith("file://"):
        return url
    if not manga_id:
        return url
    try:
        COVER_CACHE.mkdir(parents=True, exist_ok=True)
        target = COVER_CACHE / f"{manga_id}-{size}.jpg"
        if target.exists() and target.stat().st_size > 0:
            return target.as_uri()
        _download(url, target, accept="image/*")
        return target.as_uri() if target.exists() else url
    except (MangaError, OSError):
        return url


def _entries_with_covers(rows: list) -> list[dict]:
    entries = [_entry(row) for row in rows if row.get("id")]

    def work(entry):
        remote = entry.get("thumb") or entry.get("cover") or ""
        local = _cache_cover(remote, entry.get("mangaId", ""), 256)
        entry["thumb"] = local
        entry["cover"] = local
        return entry

    if not entries:
        return entries
    with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:
        return list(pool.map(work, entries))


def _staff(relationships: list) -> str:
    names = []
    for relationship in relationships or []:
        if relationship.get("type") not in ("author", "artist"):
            continue
        name = (relationship.get("attributes") or {}).get("name")
        if isinstance(name, str) and name.strip() and name.strip() not in names:
            names.append(name.strip())
    return ", ".join(names)


def _genres(attributes: dict) -> list[str]:
    names = []
    for tag in attributes.get("tags") or []:
        name = (tag.get("attributes") or {}).get("name") or {}
        value = _first_text(name) if isinstance(name, dict) else str(name)
        if value and value not in names:
            names.append(value)
    return names


def _status(attributes: dict) -> str:
    value = str(attributes.get("status") or "").strip()
    return {
        "ongoing": "Ongoing",
        "completed": "Completed",
        "hiatus": "Hiatus",
        "cancelled": "Cancelled",
    }.get(value.lower(), value.title())


def _manga_info(manga_id: str) -> dict:
    data = _request_json(f"{API}/manga/{manga_id}", {
        "includes[]": ["cover_art", "author", "artist"],
    })
    manga = data.get("data") or {}
    attributes = manga.get("attributes") or {}
    relationships = manga.get("relationships") or []
    cover_remote = _cover_url(manga_id, relationships)
    return {
        "id": manga_id,
        "mangaId": manga_id,
        "title": _title(attributes),
        "author": _staff(relationships),
        "cover": _cache_cover(cover_remote, manga_id, 512) or cover_remote,
        "coverRemote": cover_remote,
        "thumb": _cache_cover(cover_remote.replace(".512.jpg", ".256.jpg"), manga_id, 256) or cover_remote,
        "summary": _description(attributes),
        "year": attributes.get("year"),
        "status": _status(attributes),
        "genres": _genres(attributes),
        "url": f"https://mangadex.org/title/{manga_id}",
        "source": "MangaDex",
    }


def _chapter_number(attributes: dict) -> str:
    value = attributes.get("chapter")
    return "" if value is None else str(value).strip()


def _chapter_sort_key(chapter: dict) -> tuple:
    volume = chapter.get("_volume_sort")
    number = chapter.get("_number_sort")
    return (
        volume if volume is not None else float("inf"),
        number if number is not None else float("inf"),
        chapter["name"].casefold(),
        chapter["id"],
    )


def _number(value) -> float | None:
    if value is None or str(value).strip() == "":
        return None
    try:
        return float(str(value))
    except ValueError:
        return None


def _chapters(manga_id: str) -> list[dict]:
    chapters: list[dict] = []
    offset = 0
    while True:
        data = _request_json(f"{API}/manga/{manga_id}/feed", {
            "limit": FEED_LIMIT,
            "offset": offset,
            "translatedLanguage[]": [LANGUAGE],
            "contentRating[]": list(RATINGS),
            "includeExternalUrl": 0,
            "order[volume]": "asc",
            "order[chapter]": "asc",
            "includes[]": ["scanlation_group"],
        })
        rows = data.get("data") or []
        total = int(data.get("total") or 0)
        for row in rows:
            attributes = row.get("attributes") or {}
            if attributes.get("externalUrl"):
                continue
            number = _chapter_number(attributes)
            title = str(attributes.get("title") or "").strip()
            if number and title:
                name = f"Chapter {number} - {title}"
            elif number:
                name = f"Chapter {number}"
            elif title:
                name = title
            else:
                name = "Oneshot"
            volume = str(attributes.get("volume") or "").strip()
            chapters.append({
                "name": name,
                "id": str(row.get("id") or ""),
                "number": number,
                "volume": f"Vol.{volume}" if volume else "",
                "pages": int(attributes.get("pages") or 0),
                "url": f"https://mangadex.org/chapter/{row.get('id')}",
                "href": f"manga-dl:{manga_id}:{row.get('id')}",
                "chapterId": str(row.get("id") or ""),
                "_volume_sort": _number(volume),
                "_number_sort": _number(number),
            })
        offset += len(rows)
        if not rows or offset >= total:
            break
    chapters.sort(key=_chapter_sort_key)
    for position, chapter in enumerate(chapters):
        chapter["index"] = int(chapter["_number_sort"]) if chapter["_number_sort"] is not None else position
        chapter["selector"] = position
        chapter.pop("_volume_sort", None)
        chapter.pop("_number_sort", None)
    return chapters


# ------------------------------------------------------------------ search / pages


def _entry(manga: dict) -> dict:
    manga_id = str(manga.get("id") or "")
    attributes = manga.get("attributes") or {}
    relationships = manga.get("relationships") or []
    info = {
        "id": manga_id,
        "title": _title(attributes),
        "author": _staff(relationships),
        "cover": _cover_url(manga_id, relationships),
        "thumb": _cover_url_small(manga_id, relationships),
        "summary": _description(attributes),
        "year": attributes.get("year"),
        "status": _status(attributes),
        "genres": _genres(attributes),
        "url": f"https://mangadex.org/title/{manga_id}",
        "source": "MangaDex",
    }
    return {
        "kind": "book",
        "title": info["title"],
        "author": info["author"],
        "cover": info["cover"],
        "thumb": info["thumb"],
        "summary": info["summary"],
        "year": info["year"],
        "status": info["status"],
        "genres": info["genres"],
        "url": info["url"],
        "source": info["source"],
        "mangaId": manga_id,
        "href": f"manga:{manga_id}",
    }

def _search_page(query: str, offset: int = 0) -> dict:
    data = _request_json(f"{API}/manga", {
        "title": query,
        "limit": SEARCH_LIMIT,
        "offset": offset,
        "contentRating[]": list(RATINGS),
        "includes[]": ["cover_art", "author", "artist"],
        "order[relevance]": "desc",
    })
    rows = data.get("data") or []
    total = int(data.get("total") or 0)
    entries = _entries_with_covers(rows)

    # MangaDex's relevance order can put a longer title containing the query first.
    # Keep its order otherwise, but lift an exact title match to the top.
    needle = re.sub(r"\s+", " ", query.strip().casefold())
    entries.sort(key=lambda item: (
        0 if re.sub(r"\s+", " ", item["title"].strip().casefold()) == needle else
        1 if re.sub(r"\s+", " ", item["title"].strip().casefold()).startswith(needle) else 2
    ))
    next_url = ""
    if entries and offset + len(rows) < total:
        next_url = "manga-search:" + _encode({"q": query, "offset": offset + len(rows)})
    return {
        "title": f"MangaDex · {query}",
        "entries": entries,
        "next": next_url,
        "search": True,
        "detail": None,
    }


def _home_page(offset: int = 0) -> dict:
    data = _request_json(f"{API}/manga", {
        "limit": 24,
        "offset": offset,
        "contentRating[]": list(RATINGS),
        "includes[]": ["cover_art", "author", "artist"],
        "order[followedCount]": "desc",
    })
    rows = data.get("data") or []
    total = int(data.get("total") or 0)
    next_url = ""
    if rows and offset + len(rows) < total:
        next_url = "manga-home:" + str(offset + len(rows))
    return {
        "title": "Popular on MangaDex",
        "entries": _entries_with_covers(rows),
        "next": next_url,
        "search": True,
        "detail": None,
    }


def _detail_page(manga_id: str) -> dict:
    info = _manga_info(manga_id)
    chapters = _chapters(manga_id)
    info["kind"] = "manga"
    info["chapters"] = chapters
    return {
        "title": info["title"],
        "entries": [],
        "next": "",
        "search": True,
        "detail": info,
    }


# ------------------------------------------------------------------ CBZ


def _encode(payload: dict) -> str:
    raw = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    return base64.urlsafe_b64encode(raw).decode("ascii").rstrip("=")


def _decode(token: str) -> dict:
    try:
        padded = token + "=" * (-len(token) % 4)
        data = json.loads(base64.urlsafe_b64decode(padded.encode("ascii")))
    except (ValueError, TypeError) as error:
        raise MangaError("This manga link is not valid.") from error
    if not isinstance(data, dict):
        raise MangaError("This manga link is not valid.")
    return data


def _comic_info(info: dict, chapter: dict, page_count: int) -> str:
    def escape(value) -> str:
        return xml.sax.saxutils.escape(str(value or ""))

    number = chapter.get("number") or ""
    volume = chapter.get("volume") or ""
    volume_number = volume.removeprefix("Vol.").strip() if volume else ""
    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<ComicInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">',
        f"  <Title>{escape(chapter.get('name'))}</Title>",
        f"  <Series>{escape(info.get('title'))}</Series>",
        f"  <Number>{escape(number)}</Number>",
        f"  <Volume>{escape(volume_number)}</Volume>",
        f"  <Web>{escape(chapter.get('url'))}</Web>",
        f"  <PageCount>{page_count}</PageCount>",
        f"  <Summary>{escape(info.get('summary'))}</Summary>",
        f"  <Year>{escape(info.get('year'))}</Year>",
        f"  <Writer>{escape(info.get('author'))}</Writer>",
        f"  <Genre>{escape(', '.join(info.get('genres') or []))}</Genre>",
        f"  <LanguageISO>{escape(LANGUAGE)}</LanguageISO>",
        "  <Manga>YesAndRightToLeft</Manga>",
        "  <Notes>Downloaded directly from MangaDex by ii Books.</Notes>",
        "</ComicInfo>",
    ]
    return "\n".join(lines) + "\n"


def _download_chapter(info: dict, chapter: dict, target: Path, progress=None) -> int:
    chapter_id = chapter.get("chapterId") or ""
    if not chapter_id:
        raise MangaError("This chapter has no MangaDex id.")
    at_home = _request_json(f"{API}/at-home/server/{chapter_id}")
    if at_home.get("result") not in (None, "ok"):
        raise MangaError("MangaDex did not serve this chapter.")
    base_url = str(at_home.get("baseUrl") or "").rstrip("/")
    chapter_data = at_home.get("chapter") or {}
    page_hash = str(chapter_data.get("hash") or "")
    pages = chapter_data.get("data") or []
    if not base_url or not page_hash or not pages:
        raise MangaError("This chapter has no downloadable pages.")

    temp_dir = Path(tempfile.mkdtemp(prefix=".ii-manga-", dir=str(target.parent)))
    files: list[Path] = []
    try:
        def fetch(item):
            position, page = item
            suffix = Path(str(page)).suffix.lower()
            if suffix not in IMAGE_SUFFIXES:
                suffix = ".jpg"
            out = temp_dir / f"{position:06d}{suffix}"
            url = f"{base_url}/data/{page_hash}/{page}"
            return out, _download(url, out)

        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            for out, size in pool.map(fetch, enumerate(pages)):
                files.append(out)
                if progress:
                    progress({"progress": len(files), "total": max(1, len(pages))})
        files.sort(key=lambda path: path.name)
        with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_STORED) as archive:
            for page in files:
                archive.write(page, page.name)
            archive.writestr("ComicInfo.xml", _comic_info(info, chapter, len(files)))
        return sum(path.stat().st_size for path in files)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)


def _write_series(info: dict, folder: Path, chapter_count: int) -> None:
    series = {
        "metadata": {
            "type": "comicSeries",
            "name": info.get("title", ""),
            "description_text": info.get("summary", ""),
            "status": info.get("status", ""),
            "year": info.get("year"),
            "ComicImage": info.get("coverRemote") or info.get("cover", ""),
            "publisher": info.get("author", ""),
            "comicId": 0,
            "booktype": "Print",
            "total_issues": chapter_count,
        }
    }
    (folder / "series.json").write_text(json.dumps(series), encoding="utf-8")


def _cover_file(info: dict, folder: Path) -> None:
    cover = info.get("coverRemote") or info.get("cover") or ""
    target = folder / "cover.jpg"
    if not cover or target.exists():
        return
    if cover.startswith("file://"):
        try:
            shutil.copyfile(urllib.request.url2pathname(cover[len("file://"):]), target)
        except OSError:
            pass
        return
    try:
        _download(cover, target)
    except MangaError:
        pass


# ------------------------------------------------------------------ public API


def browse(url: str, query: str) -> dict:
    if url.startswith("manga:"):
        return _detail_page(url[len("manga:"):])
    if url.startswith("manga-search:"):
        payload = _decode(url[len("manga-search:"):])
        return _search_page(str(payload.get("q") or ""), int(payload.get("offset") or 0))
    if url.startswith("manga-home:"):
        return _home_page(int(url[len("manga-home:"):] or 0))
    if query.strip():
        return _search_page(query.strip())
    return _home_page()


def download(url: str, dest: str, progress=None) -> dict:
    if not url.startswith("manga-dl:"):
        raise MangaError("This is not a manga chapter link.")
    rest = url[len("manga-dl:"):]
    manga_id, separator, selector = rest.partition(":")
    if not separator or not manga_id or not selector:
        raise MangaError("This is not a manga chapter link.")
    info = _manga_info(manga_id)
    chapters = _chapters(manga_id)
    if not chapters:
        raise MangaError("MangaDex has no downloadable chapters for this manga.")
    if selector == "all":
        selected = chapters
    else:
        selected = [chapter for chapter in chapters if chapter.get("chapterId") == selector]
        if not selected:
            raise MangaError("That chapter is no longer on MangaDex.")

    folder = Path(dest).expanduser() / _safe_name(info["title"])
    folder.mkdir(parents=True, exist_ok=True)
    _cover_file(info, folder)
    _write_series(info, folder, len(chapters))

    total_pages = sum(max(1, chapter.get("pages") or 0) for chapter in selected)
    done_pages = 0
    produced: list[Path] = []

    def report(step: dict) -> None:
        if progress:
            progress({"progress": done_pages + int(step.get("progress") or 0), "total": total_pages})

    for position, chapter in enumerate(chapters):
        if chapter not in selected:
            continue
        prefix = f"[{position:04d}]"
        target = folder / f"{prefix} {_safe_name(chapter['name'])}.cbz"
        if target.exists() and target.stat().st_size > 0:
            produced.append(target)
            done_pages += max(1, chapter.get("pages") or 0)
            if progress:
                progress({"progress": done_pages, "total": total_pages})
            continue
        partial = target.with_name(target.name + ".part")
        try:
            _download_chapter(info, chapter, partial, report)
            partial.replace(target)
            produced.append(target)
        except BaseException:
            partial.unlink(missing_ok=True)
            raise
        done_pages += max(1, chapter.get("pages") or 0)
        if progress:
            progress({"progress": done_pages, "total": total_pages})

    if not produced:
        raise MangaError("No CBZ file was produced.")
    produced.sort(key=lambda path: path.name)
    first = produced[0]
    return {
        "done": True,
        "path": str(first),
        "size": first.stat().st_size,
        "count": len(produced),
    }

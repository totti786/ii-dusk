#!/usr/bin/env python3
"""Fetches quran.com's Madani page data and fonts into ~/.local/share/ii-quran/qcf:
  fonts/pNNN.woff2   the per-page glyph font (v2) that draws every line of that page
  pages.json         [ {"l": {"3": [[verseKey, wordIndex, kind, glyphs, text], ...]}} ] x 604
kind: 0 word, 1 verse end marker, 2 other sign. A page's response also carries the words of a verse
that runs onto the next page (flagged with that page's number), so words are regrouped by the page
they are printed on. Progress lines "n/604" go to stdout; the combined
pages.json is written last, so its presence means everything is there."""
import io
import json
import os
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

# The overlap fix needs fontTools + skia-pathops, which live in this private venv. Without the
# venv the fonts are kept as quran.com serves them, and the reader shows white blobs on some glyphs.
VENV_PY = os.path.expanduser("~/.local/state/ii-quran/venv/bin/python3")


def ensure_venv():
    if os.path.exists(VENV_PY) and os.path.realpath(sys.executable) != os.path.realpath(VENV_PY):
        os.execv(VENV_PY, [VENV_PY] + sys.argv)


def remove_overlaps(blob):
    """Merges overlapping contours in a page font: the distance-field renderer draws them as blobs."""
    try:
        from fontTools.ttLib import TTFont
        from fontTools.ttLib.removeOverlaps import removeOverlaps
    except ImportError:
        print("no fontTools: page fonts keep their overlaps", file=sys.stderr, flush=True)
        return blob
    font = TTFont(io.BytesIO(blob))
    removeOverlaps(font)
    out = io.BytesIO()
    font.flavor = "woff2"
    font.save(out)
    return out.getvalue()

ROOT = os.path.expanduser("~/.local/share/ii-quran/qcf")
API = "https://api.quran.com/api/v4/verses/by_page/{n}?words=true&word_fields=code_v2,line_number,text_uthmani&per_page=300&mushaf=1"
FONT = "https://verses.quran.com/fonts/quran/hafs/v2/woff2/p{n}.woff2"
KINDS = {"word": 0, "end": 1}


def get(url, tries=4):
    last = None
    for _ in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "ii-quran"})
            with urllib.request.urlopen(req, timeout=40) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001 - retried, then raised
            last = e
    raise last


def page(n):
    os.makedirs(os.path.join(ROOT, "raw"), exist_ok=True)
    os.makedirs(os.path.join(ROOT, "fonts"), exist_ok=True)
    cache = os.path.join(ROOT, "raw", f"{n}.json")
    if os.path.exists(cache):
        with open(cache, encoding="utf-8") as f:
            rows = json.load(f)
    else:
        raw = json.loads(get(API.format(n=n)))
        rows = []
        for v in raw["verses"]:
            surah, ayah = (int(x) for x in v["verse_key"].split(":"))
            idx = 0
            for w in v["words"]:
                kind = KINDS.get(w["char_type_name"], 2)
                i = idx if kind == 0 else -1
                if kind == 0:
                    idx += 1
                rows.append([v["verse_key"], i, kind, w["code_v2"], w.get("text_uthmani") or "",
                             w["line_number"], w.get("page_number") or n, surah, ayah, w["position"]])
        tmp = cache + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(rows, f, ensure_ascii=False, separators=(",", ":"))
        os.replace(tmp, cache)
    font = os.path.join(ROOT, "fonts", f"p{n}.woff2")
    if not os.path.exists(font):
        blob = remove_overlaps(get(FONT.format(n=n)))
        with open(font + ".tmp", "wb") as f:
            f.write(blob)
        os.replace(font + ".tmp", font)
    return rows


def regroup(all_rows):
    """Pages of lines: every word goes to the page it is printed on, in reading order."""
    seen = set()
    per = [dict() for _ in range(604)]
    for rows in all_rows:
        for r in rows:
            key = (r[7], r[8], r[9])
            if key in seen:
                continue
            seen.add(key)
            pg = r[6]
            if 1 <= pg <= 604:
                per[pg - 1].setdefault(r[5], []).append(r)
    out = []
    for lines in per:
        l = {}
        for ln, rows in lines.items():
            rows.sort(key=lambda r: (r[7], r[8], r[9]))
            l[str(ln)] = [r[:5] for r in rows]
        out.append({"l": l})
    return out


def main():
    ensure_venv()
    os.makedirs(ROOT, exist_ok=True)
    done = 0
    all_rows = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        for rows in pool.map(page, range(1, 605)):
            all_rows.append(rows)
            done += 1
            print(f"{done}/604", flush=True)
    out = regroup(all_rows)
    tmp = os.path.join(ROOT, "pages.json.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        # each page stays a JSON string of its own: the reader parses a page only when it needs it
        json.dump([json.dumps(x, ensure_ascii=False, separators=(",", ":")) for x in out], f,
                  ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, os.path.join(ROOT, "pages.json"))
    print("ok", flush=True)


if __name__ == "__main__":
    main()

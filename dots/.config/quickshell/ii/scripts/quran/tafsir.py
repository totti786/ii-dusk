#!/usr/bin/env python3
"""Downloads one tafsir of one surah from quran.com and stores it in
~/.local/share/ii-quran/tafsir/<id>/<surah>.json as {"v": {"<ayah>": "<html>"}}.

Only the ayahs that carry text are kept: many tafsirs comment on a run of ayahs once, under the
first, and leave the others empty. The reader reads a verse's commentary from the nearest ayah at or
before it. The markup is cut down to what Qt's rich text draws."""
import json
import os
import re
import sys
import urllib.request
from concurrent.futures import ThreadPoolExecutor

KEEP = {"h1", "h2", "h3", "h4", "p", "br", "b", "strong", "i", "em", "ul", "ol", "li", "blockquote"}


def clean(html):
    html = re.sub(r"<(script|style)[^>]*>.*?</\1>", "", html, flags=re.S | re.I)
    html = re.sub(r"<sup[^>]*>.*?</sup>", "", html, flags=re.S | re.I)

    def tag(m):
        closing, name = m.group(1), m.group(2).lower()
        if name == "span":
            return ""
        if name not in KEEP:
            return ""
        if name == "br":
            return "<br/>"
        return f"</{name}>" if closing else f"<{name}>"

    html = re.sub(r"<(/?)([a-zA-Z0-9]+)[^>]*>", tag, html)
    html = re.sub(r"\s+", " ", html)
    return html.strip()


def pool_map(fn, items):
    with ThreadPoolExecutor(max_workers=6) as pool:
        return pool.map(fn, items)


def get(path):
    req = urllib.request.Request("https://api.quran.com/api/v4/" + path, headers={"User-Agent": "ii-quran"})
    with urllib.request.urlopen(req, timeout=40) as r:
        return json.load(r)


# Tafsirs quran.com does not carry, from the spa5k/tafsir_api dataset (MIT; Tarteel QUL texts).
# Plain text, one entry per ayah, with "صفحة N" page markers of the printed edition.
EXTRA = {9025: "ar-tafseer-tahrir-al-tanwir"}


def plain(text):
    paras = []
    for line in text.split("\n"):
        line = line.strip()
        if line and not re.fullmatch(r"صفحة\s*[\d\u0660-\u0669]+", line):
            paras.append("<p>" + line.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;") + "</p>")
    return "".join(paras)


def extra(slug, surah):
    url = f"https://cdn.jsdelivr.net/gh/spa5k/tafsir_api@main/tafsir/{slug}/{surah}.json"
    req = urllib.request.Request(url, headers={"User-Agent": "ii-quran"})
    with urllib.request.urlopen(req, timeout=60) as r:
        rows = json.load(r)
    return {str(row["ayah"]): plain(row.get("text") or "") for row in rows if (row.get("text") or "").strip()}


def main():
    tid, surah = int(sys.argv[1]), int(sys.argv[2])
    verses, page = {}, 1
    if tid in EXTRA:
        verses, page = extra(EXTRA[tid], surah), None
    if not verses:
        first = get(f"tafsirs/{tid}/by_chapter/{surah}?per_page=50&page=1")
        pages = first["pagination"].get("total_pages") or 1
        rest = [] if pages <= 1 else list(pool_map(lambda n: get(f"tafsirs/{tid}/by_chapter/{surah}?per_page=50&page={n}"), range(2, pages + 1)))
        for data in [first] + rest:
            for row in data["tafsirs"]:
                text = clean(row.get("text") or "")
                if text:
                    verses[row["verse_key"].split(":")[1]] = text
    if not verses:
        print("no text", file=sys.stderr)
        sys.exit(1)
    out = os.path.expanduser(f"~/.local/share/ii-quran/tafsir/{tid}")
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, f".{surah}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump({"v": verses}, f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, os.path.join(out, f"{surah}.json"))
    print("ok")


if __name__ == "__main__":
    main()

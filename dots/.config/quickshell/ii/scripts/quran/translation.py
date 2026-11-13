#!/usr/bin/env python3
"""Downloads one quran.com translation and stores it as a flat list of 6236 verse strings
(surah order) in ~/.local/share/ii-quran/tr-<id>.json, footnote markup removed."""
import json
import os
import re
import sys
import urllib.request

def clean(text):
    text = re.sub(r"<sup[^>]*>.*?</sup>", "", text)
    text = re.sub(r"<[^>]+>", "", text)
    return re.sub(r"\s+", " ", text).strip()

def main():
    rid = int(sys.argv[1])
    url = f"https://api.quran.com/api/v4/quran/translations/{rid}"
    req = urllib.request.Request(url, headers={"User-Agent": "ii-quran"})
    with urllib.request.urlopen(req, timeout=40) as r:
        data = json.load(r)["translations"]
    if len(data) != 6236:
        print(f"unexpected verse count {len(data)}", file=sys.stderr)
        sys.exit(1)
    out = os.path.expanduser("~/.local/share/ii-quran")
    os.makedirs(out, exist_ok=True)
    tmp = os.path.join(out, f".tr-{rid}.tmp")
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump([clean(x["text"]) for x in data], f, ensure_ascii=False, separators=(",", ":"))
    os.replace(tmp, os.path.join(out, f"tr-{rid}.json"))
    print("ok")

if __name__ == "__main__":
    main()

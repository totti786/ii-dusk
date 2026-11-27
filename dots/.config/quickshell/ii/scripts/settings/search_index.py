#!/usr/bin/env python3
"""The Settings search index: the controls of every page, plus their landmarks.

SearchRegistry shows results as live clones of the real controls, so the index holds
each ``ContentSection``, its ``ContentSubsection``s and the source of every compact
``Config*`` control in them. Words a page draws outside those come from
``search_landmarks``.

This runs out of process and keeps its output on disk: parsing the page files in the
shell took its UI thread half a second, and the whole build was repeated every time a
search was started. The cache is reused until a settings file or the page list changes.

Usage: search_index.py <shell root> '<pages JSON>' [cache file]
Prints {"sections": [...], "imports": {}, "landmarks": [...], "blocks": {}}; every
string is untranslated, so one cache serves every language.
"""

from __future__ import annotations

import functools
import hashlib
import json
import os
import re
import sys
import tempfile
from pathlib import Path

import search_landmarks

# Search results are live QML clones, so only compact, semantic settings controls
# belong here. Structural layouts and informational surfaces (NoticeBox, ShortcutBox,
# Flow, Row/ColumnLayout, service cards, etc.) either duplicate their descendants or
# depend on page-local ids and produce empty or broken result cards.
CONTROL_TYPES = (
    "ConfigSwitch", "ConfigSpinBox", "ConfigSelectionArray", "ConfigTextField",
    "ConfigSlider", "ConfigComboBox", "ConfigLightDarkToggle", "ConfigSubpageRow",
)
# What names a control, in order of preference.
LABEL_PROPS = ("text", "title", "tooltip", "value", "placeholderText", "description", "summary")

ID_RE = re.compile(r"\bid\s*:\s*([A-Za-z_]\w*)", re.A)
TR_RE = re.compile(r'Translation\.tr\(\s*"((?:\\.|[^"\\])*)"\s*\)')
WORD_RE = re.compile(r"\w+", re.A)


def unescape(body: str) -> str:
    """The text a quoted QML string shows."""
    return re.sub(r"\\(.)", lambda m: {"n": "\n", "t": "\t"}.get(m.group(1), m.group(1)), body)


def extract_imports(text: str) -> str:
    return "".join(line.strip() + "\n" for line in text.split("\n") if line.strip().startswith("import "))


def executable_source(text: str) -> str:
    """Code without prose, for finding page-local ids. Template strings stay intact
    because their ``${...}`` expressions are executable."""
    for pattern in (r'"(?:\\.|[^"\\])*"', r"'(?:\\.|[^'\\])*'", r"/\*[\s\S]*?\*/", r"//[^\n]*"):
        text = re.sub(pattern, " ", text)
    return text


def declared_ids(code: str) -> list[str]:
    return list(dict.fromkeys(ID_RE.findall(code)))


def uses_external_id(block: str, file_ids: list[str]) -> bool:
    code = executable_source(block)
    outside = set(file_ids) - set(declared_ids(code))
    return not outside.isdisjoint(WORD_RE.findall(code))


def is_list_row(block: str) -> bool:
    """A delegate: it reads the model entry its list hands it, so it cannot stand alone."""
    code = executable_source(block)
    if re.search(r"\brequired\s+property\b", code):
        return True
    # `model.map(modelData => ...)` is the control's own; a bare `modelData` is not.
    return bool(re.search(r"(?<![\w.])modelData\b", code)) and not re.search(r"\bmodelData\s*\)?\s*=>", code)


def extract_blocks(text: str, component: str, base: int = 0) -> list[dict]:
    """Every ``component { ... }`` in the text, outermost first and not nested."""
    results = []
    i = 0
    length = len(text)
    while i < length:
        index = text.find(component, i)
        if index == -1:
            break
        after = index + len(component)
        if index > 0 and re.match(r"[A-Za-z0-9_]", text[index - 1]):
            i = after
            continue
        brace = text.find("{", index)
        if brace == -1:
            break
        if text[after:brace].strip():
            i = after
            continue
        depth = 1
        j = brace + 1
        quote = ""
        while j < length and depth > 0:
            ch = text[j]
            # Prose in comments ("the user's ...") holds quotes and braces that are
            # not code: one apostrophe would swallow every section after it.
            if not quote and ch == "/" and text[j + 1:j + 2] in ("/", "*"):
                if text[j + 1] == "/":
                    end = text.find("\n", j)
                    j = length if end == -1 else end
                else:
                    end = text.find("*/", j + 2)
                    j = length if end == -1 else end + 2
                continue
            if not quote and ch in "\"'`":
                quote = ch
            elif quote and ch == quote:
                if text[j - 1] != "\\":
                    quote = ""
            elif not quote:
                if ch == "{":
                    depth += 1
                elif ch == "}":
                    depth -= 1
            j += 1
        results.append({"inner": text[brace + 1:j - 1], "inner_start": base + brace + 1,
                        "start": base + index, "end": base + j})
        i = j
    return results


@functools.cache
def property_patterns(name: str) -> tuple[re.Pattern, ...]:
    # An escaped quote, or an apostrophe, is part of the string and not its end.
    double = r'"((?:\\.|[^"\\])+)"'
    single = r"'((?:\\.|[^'\\])+)'"
    values = [r"Translation\.tr\(\s*" + q + r"\s*\)" for q in (double, single)] + [double, single]
    return tuple(re.compile(name + r"\s*:\s*" + value) for value in values)


def extract_property(block: str, name: str) -> str:
    for pattern in property_patterns(name):
        m = pattern.search(block)
        if m:
            return m.group(1)
    return ""


def extract_controls(text: str, base: int, source: str, file_ids: list[str]) -> list[dict]:
    items = []
    for kind in CONTROL_TYPES:
        for block in extract_blocks(text, kind):
            inner = block["inner"]
            # Rows wired only through an `onClicked` closure usually refer to ids from
            # the original page. A declarative configPage is self-contained.
            if kind == "ConfigSubpageRow" and not re.search(r"\bconfigPage\s*:", inner):
                continue
            # A clone has no access to ids declared by its page or sibling controls:
            # skip it rather than show a half-working result that throws at runtime.
            if uses_external_id(inner, file_ids) or is_list_row(inner):
                continue
            label = next(filter(None, (extract_property(inner, p) for p in LABEL_PROPS)), "")
            # Every other word it shows: tooltip, description and option names.
            extra = []
            for m in TR_RE.finditer(inner):
                if m.group(1) != label and m.group(1) not in extra:
                    extra.append(m.group(1))
            start, end = base + block["start"], base + block["end"]
            items.append({"type": kind, "text": unescape(label), "extra": [unescape(e) for e in extra],
                          "sourceStart": start, "sourceEnd": end, "source": source[start:end]})
    return items


def index_file(text: str, source_key: str, page_id: str, sub_page: str) -> list[dict]:
    file_ids = declared_ids(executable_source(text))
    sections = []
    for block in extract_blocks(text, "ContentSection"):
        inner = block["inner"]
        title = extract_property(inner, "title")
        # A computed title (one a Repeater builds per group, say) names no heading that
        # exists on a page, and its controls could not be recognised under it.
        if not title:
            continue
        subsections = extract_blocks(inner, "ContentSubsection", block["inner_start"])
        subs = [{
            "title": unescape(extract_property(sub["inner"], "title")),
            "icon": extract_property(sub["inner"], "icon"),
            "items": extract_controls(sub["inner"], sub["inner_start"], text, file_ids),
        } for sub in subsections]
        items = [item for item in extract_controls(inner, block["inner_start"], text, file_ids)
                 if not any(item["sourceStart"] >= s["start"] and item["sourceEnd"] <= s["end"] for s in subsections)]
        sections.append({
            "pageId": page_id, "subPage": sub_page, "title": unescape(title),
            "icon": extract_property(inner, "icon"), "sourceKey": source_key,
            "items": items, "subsections": subs,
        })
    return sections


def source_files(shell_root: str, pages: list[dict]) -> list[tuple[str, str, str]]:
    """(path, page id, sub-page) of every file the registry says holds a page's controls."""
    configs = shell_root + search_landmarks.CONFIGS
    files = []
    for page in pages:
        if page.get("searchable") is False:
            continue
        # A page drawn with tiles, cards and live previews can have its options indexed
        # through `searchSources` alone: its own file would add the sections whose
        # controls name page ids, which a clone cannot resolve.
        if page.get("searchComponent") is not False:
            files.append((shell_root + page["component"], page["id"], ""))
        for sub in page.get("subPages") or []:
            files.append((configs + sub, page["id"], sub))
        # Sections outside the page file are not sub-pages: a result opens the page and
        # waits for its lazy loader, unless the source stands in for a sub-page.
        for source in page.get("searchSources") or []:
            files.append((configs + source, page["id"], (page.get("searchSubPages") or {}).get(source, "")))
    return files


def build(shell_root: str, pages: list[dict]) -> dict:
    shell_root = shell_root.rstrip("/") + "/"
    searchable = [p for p in pages if p.get("searchable") is not False]
    blocks: dict = {}
    discovered: list[dict] = []
    landmarks = search_landmarks.crawl(shell_root, searchable, blocks, discovered)
    files = source_files(shell_root, pages)
    # Sub-pages the crawl found through the row that opens them, which no page registers.
    files += [(shell_root + search_landmarks.CONFIGS + s["subPage"], s["pageId"], s["subPage"]) for s in discovered]

    sections: list[dict] = []
    imports: dict[str, str] = {}
    for path, page_id, sub_page in files:
        try:
            text = Path(path).read_text(encoding="utf-8")
        except OSError:
            continue
        found = index_file(text, path, page_id, sub_page)
        if found:
            imports[path] = extract_imports(text)
            sections += found
    return {"sections": sections, "imports": imports, "landmarks": landmarks, "blocks": blocks}


def fingerprint(shell_root: str, pages_json: str) -> str:
    """Changes whenever the output could: the page list, a page file or this indexer."""
    shell_root = shell_root.rstrip("/") + "/"
    paths = [__file__, search_landmarks.__file__]
    for directory, _, names in os.walk(shell_root + search_landmarks.CONFIGS):
        paths += [os.path.join(directory, n) for n in names if n.endswith(".qml")]
    paths += [shell_root + p["component"] for p in json.loads(pages_json)]
    digest = hashlib.sha256((shell_root + "\n" + pages_json).encode())
    for path in sorted(set(paths)):
        try:
            stat = os.stat(path)
        except OSError:
            continue
        digest.update(f"\n{path}\0{stat.st_mtime_ns}\0{stat.st_size}".encode())
    return digest.hexdigest()


def cached_index(shell_root: str, pages_json: str, cache: Path | None) -> str:
    """The index as JSON text, from the cache when nothing it was built from changed."""
    key = fingerprint(shell_root, pages_json)
    if cache:
        try:
            stored_key, _, payload = cache.read_text(encoding="utf-8").partition("\n")
            if stored_key == key and payload.endswith("}"):
                return payload
        except (OSError, UnicodeDecodeError):
            pass
    payload = json.dumps(build(shell_root, json.loads(pages_json)), ensure_ascii=False, separators=(",", ":"))
    if cache:
        try:
            cache.parent.mkdir(parents=True, exist_ok=True)
            # Written aside and renamed: a run cut short must not leave half an index.
            with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=cache.parent, delete=False) as out:
                out.write(key + "\n" + payload)
            os.replace(out.name, cache)
        except OSError as error:
            print(f"search index not cached: {error}", file=sys.stderr)
    return payload


def main(argv: list[str]) -> int:
    if len(argv) not in (3, 4):
        print(__doc__, file=sys.stderr)
        return 2
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stdout.write(cached_index(argv[1], argv[2], Path(argv[3]) if len(argv) == 4 else None))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

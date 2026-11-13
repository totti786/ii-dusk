#!/usr/bin/env python3
"""What the Anki desktop widget shows: cards due today, the top decks and the study streak.

Opens the collection, reads the scheduler's own counts, closes it again. Anki (or the Anki
app, which holds the collection while it runs) blocks that, in which case this answers
{"state": "busy"} and the widget keeps what it had.

    anki_due.py [--profile NAME]
"""

import json
import os
import pwd
import sys
from pathlib import Path

# Runs on the Anki app's own engine (scripts/anki/install_engine.sh), not the system package.
_ENGINE = os.environ.get("II_ANKI_ENGINE") or os.path.join(
    pwd.getpwuid(os.getuid()).pw_dir, ".local", "share", "ii-anki-engine"
)
_ENGINE_PYTHON = os.path.join(_ENGINE, "venv", "bin", "python")
if os.path.realpath(sys.prefix) != os.path.realpath(os.path.join(_ENGINE, "venv")) and os.path.exists(_ENGINE_PYTHON):
    os.execv(_ENGINE_PYTHON, [_ENGINE_PYTHON, "-I", os.path.abspath(__file__), *sys.argv[1:]])


def out(obj):
    sys.stdout.write(json.dumps(obj) + "\n")


def base():
    return Path(os.environ.get("ANKI_BASE") or Path.home() / ".local/share/Anki2")


def main():
    try:
        from anki.collection import Collection
    except Exception as err:
        return out({"state": "missing", "error": "The Anki engine is not installed: " + str(err)})

    profile = sys.argv[sys.argv.index("--profile") + 1] if "--profile" in sys.argv else ""
    if not profile:
        profiles = sorted(p.name for p in base().iterdir() if (p / "collection.anki2").exists()) if base().is_dir() else []
        profile = "User 1" if "User 1" in profiles else (profiles[0] if profiles else "")
    path = base() / profile / "collection.anki2"
    if not profile or not path.exists():
        return out({"state": "missing", "error": "no Anki collection"})

    try:
        col = Collection(str(path))
    except Exception as err:
        message = str(err).lower()
        return out({"state": "busy" if "already open" in message or "locked" in message else "error", "error": str(err)})
    try:
        tree = col.sched.deck_due_tree()
        decks = []
        for node in tree.children:
            due = node.new_count + node.learn_count + node.review_count
            decks.append({"name": str(node.name), "new": node.new_count, "learn": node.learn_count,
                          "review": node.review_count, "due": due})
        decks.sort(key=lambda d: -d["due"])
        cutoff = int(col.sched.day_cutoff)
        days = col.db.list("select distinct cast((? - id / 1000) / 86400 as int) from revlog order by 1", cutoff)
        today_reviews = col.db.scalar("select count() from revlog where id / 1000 > ?", cutoff - 86400) or 0
        studied_today = 0 in days
        # A streak counts back from today, or from yesterday while today is still to be done
        streak, expect = 0, 0 if studied_today else 1
        for day in days:
            if day == expect:
                streak += 1
                expect += 1
            elif day > expect:
                break
        out({"state": "ok", "profile": profile,
             "new": sum(d["new"] for d in decks), "learn": sum(d["learn"] for d in decks),
             "review": sum(d["review"] for d in decks), "decks": decks[:4],
             "streak": streak, "studiedToday": bool(studied_today), "reviewedToday": int(today_reviews)})
    except Exception as err:
        out({"state": "error", "error": str(err)})
    finally:
        col.close()


if __name__ == "__main__":
    main()

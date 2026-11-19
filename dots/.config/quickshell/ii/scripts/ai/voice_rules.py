"""Rules for the commonest spoken commands, matched before any model is asked.

"volume 30", "pause", "next song", "ten minute timer", "dark mode" and the like are
predictable enough that a pattern is faster (a few ms, no network, no memory) and more
reliable than a model. `match(text)` returns None unless the WHOLE utterance is one of these
commands, so anything chatty, ambiguous or unfamiliar falls through to the model unchanged.

A hit is {"actions": [(verb, [args])], "say": "short confirmation"}. The verbs are exactly the
closed table in services/ai/AiCompanionActions.qml, which still validates every argument.
"""
import re
from datetime import datetime, timedelta

UNITS = {"zero": 0, "oh": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
         "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
         "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19}
TENS = {"twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90}
NUMBER_WORD = "|".join(sorted([*UNITS, *TENS, "hundred", "half", "quarter"], key=len, reverse=True))
FILLER = re.compile(
    r"^(?:(?:hey|ok|okay|please|so|just|now|well|um|uh|orb|assistant|can you|could you|would you|will you|"
    r"i want you to|i would like you to|i'd like you to|go ahead and|let's|lets|you can)\s+)+")
TRAILER = re.compile(r"(?:\s+(?:please|for me|thanks|thank you|now|right now))+$")


def words_to_digits(text):
    """'twenty five' -> '25', 'ten' -> '10'. Digits already in the text are left alone."""
    tokens = text.split()
    out, i = [], 0
    while i < len(tokens):
        token = tokens[i]
        value = None
        if token in TENS:
            value = TENS[token]
            if i + 1 < len(tokens) and tokens[i + 1] in UNITS and 0 < UNITS[tokens[i + 1]] < 10:
                value += UNITS[tokens[i + 1]]
                i += 1
        elif token in UNITS and token != "oh":
            value = UNITS[token]
        if value is not None:
            out.append(str(value))
        else:
            out.append(token)
        i += 1
    return " ".join(out)


def normalise(text):
    text = str(text).lower().strip()
    text = re.sub(r"\b([ap])\.?\s?m\.?(?=\W|$)", r"\1m", text)            # a.m. / p m -> am / pm
    text = text.replace("%", " percent ")
    text = re.sub(r"([a-z])(\d)", r"\1 \2", text)                           # "workspace3" -> "workspace 3"
    text = re.sub(r"[^\w:\s'-]", " ", text)
    text = re.sub(r"\s+", " ", text).strip()
    for _ in range(3):
        text = FILLER.sub("", text).strip()
    text = TRAILER.sub("", text).strip()
    text = re.sub(r"\bhalf an hour\b", "30 minutes", text)
    text = re.sub(r"\b(?:an|one) hour and a half\b", "90 minutes", text)
    text = re.sub(r"\ban hour\b", "60 minutes", text)
    text = re.sub(r"\bquarter of an hour\b", "15 minutes", text)
    return words_to_digits(text)


def hit(actions, say):
    return {"actions": [(verb, list(args)) for verb, args in actions], "say": say}


def next_clock(hour, minute, meridiem):
    """24-hour (h, m) for a spoken time; with no am/pm, whichever reading comes next."""
    if hour > 23 or minute > 59:
        return None
    if meridiem:
        if hour < 1 or hour > 12:
            return None
        hour = hour % 12 + (12 if meridiem == "pm" else 0)
        return hour, minute
    if hour > 12 or hour == 0:
        return hour, minute
    now = datetime.now()
    options = []
    for candidate in (hour % 12, hour % 12 + 12):
        at = now.replace(hour=candidate, minute=minute, second=0, microsecond=0)
        if at <= now:
            at += timedelta(days=1)
        options.append((at, candidate))
    return min(options)[1], minute


STOP = r"(?:the |my |this |that |it )?"
MEDIA_NOUN = r"(?: ?(?:the )?(?:music|song|track|video|audio|player|playback|podcast|media))?"
WHAT_TIME = r"(\d{1,2})(?::(\d{2}))?(?: ?(am|pm))?"


# Which settings group a verb belongs to, so a group can be switched off as a whole.
GROUPS = {"media": "media", "volume": "volume", "brightness": "brightness", "theme": "theme", "timer": "timers",
          "alarm": "alarms", "remind": "notes", "task": "notes", "workspace": "workspace", "open": "apps"}


def parse_do(text):
    """'volume set 20; theme dark' -> [("volume", ["set", "20"]), ("theme", ["dark"])], or None if any verb is unknown."""
    actions = []
    for part in str(text).split(";"):
        words = part.split()
        if not words:
            continue
        if words[0].lower() not in GROUPS:
            return None
        actions.append((words[0].lower(), words[1:]))
    return actions or None


def custom_match(t, custom):
    """The user's own phrases. A phrase matches the whole sentence; {n} stands for a number and is
    substituted into the action text, e.g. "volume {n} please" -> "volume set {n}"."""
    for rule in custom or []:
        # normalise() drops punctuation, braces included, so the placeholder travels as a word.
        phrase = normalise(str(rule.get("phrase", "")).replace("{n}", " numberslot "))
        actions = parse_do(rule.get("do", ""))
        if not phrase or actions is None:
            continue
        pattern = re.escape(phrase).replace("numberslot", r"(\d{1,4})")
        found = re.fullmatch(pattern, t)
        if not found:
            continue
        number = found.group(1) if found.groups() else ""
        resolved = [(verb, [arg.replace("{n}", number) for arg in args]) for verb, args in actions]
        return hit(resolved, str(rule.get("say", "")).strip() or "Done.")
    return None


def match(text, off=(), custom=()):
    """The command in `text`, or None. `off` names switched-off groups; `custom` is the user's phrases,
    tried first so they can override a built-in."""
    t = normalise(text)
    if not t:
        return None
    result = custom_match(t, custom) or builtin(t)
    if result is None:
        return None
    if any(GROUPS.get(verb) in set(off) for verb, _ in result["actions"]):
        return None
    return result


def builtin(t):
    if not t or len(t.split()) > 14:
        return None

    # ── media ────────────────────────────────────────────────────────────────
    if re.fullmatch(r"(?:pause|stop|hold)" + MEDIA_NOUN, t):
        return hit([("media", ["pause"])], "Paused.")
    if re.fullmatch(r"(?:play|resume|continue|unpause|start)" + MEDIA_NOUN, t) and t not in ("start",):
        return hit([("media", ["play"])], "Playing.")
    if re.fullmatch(r"(?:play pause|toggle(?: the)? (?:music|playback|song|player)|toggle)", t):
        return hit([("media", ["toggle"])], "Done.")
    if re.fullmatch(r"(?:next|skip|skip (?:this|the|to the next)|play (?:the )?next|go (?:to )?(?:the )?next)" + MEDIA_NOUN, t):
        return hit([("media", ["next"])], "Next.")
    if re.fullmatch(r"(?:previous|go back|back|last|play (?:the )?previous|go (?:back )?to (?:the )?previous|go back (?:a|one) (?:song|track))" + MEDIA_NOUN, t):
        return hit([("media", ["previous"])], "Previous.")

    # ── volume ───────────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:set |change |put |make )?" + STOP + r"(?:volume|sound)(?: level)?(?: set)?(?: to| at)? (\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(?:set |make |turn )" + STOP + r"(?:volume|sound) (\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(?:set|put|turn) (?:the )?(?:volume|sound) (?:to |at )?(\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(\d{1,3}) percent (?:volume|sound)", t)
    if m:
        level = int(m.group(1))
        if 0 <= level <= 100:
            return hit([("volume", ["set", str(level)])], f"Volume {level}.")
    if re.fullmatch(r"(?:mute|silence|shut up)(?: the)?(?: sound| audio| volume| speakers| music)?", t):
        return hit([("volume", ["mute"])], "Muted.")
    if re.fullmatch(r"unmute(?: the)?(?: sound| audio| volume| speakers)?", t):
        return hit([("volume", ["unmute"])], "Unmuted.")
    m = re.fullmatch(
        r"(?:(?:turn|make|put|bring|crank|pump)(?: it| the volume| the sound| the music)? )?"
        r"(?:volume |sound )?(up|down|louder|quieter|softer|lower|higher|raise|lower)(?: (?:a |by )?(bit|little|lot|much|more|slightly))?"
        r"|(?:turn|make|put) (?:it|the volume|the sound) (up|down|louder|quieter)(?: (?:a |by )?(bit|little|lot|much|more|slightly))?"
        r"|volume (up|down)", t)
    if m:
        word = next((g for g in m.groups() if g in ("up", "down", "louder", "quieter", "softer", "lower", "higher", "raise")), None)
        amount = next((g for g in m.groups() if g in ("lot", "much", "more")), None)
        if word:
            direction = "up" if word in ("up", "louder", "higher", "raise") else "down"
            steps = 2 if amount else 1
            return hit([("volume", [direction])] * steps, "Louder." if direction == "up" else "Quieter.")

    # ── brightness ───────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:set |change |put |make )?" + STOP + r"(?:screen )?brightness(?: level)?(?: set)?(?: to| at)? (\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(\d{1,3}) percent brightness", t)
    if m and 0 <= int(m.group(1)) <= 100:
        level = max(5, int(m.group(1)))
        return hit([("brightness", ["set", str(level)])], f"Brightness {level}.")
    m = re.fullmatch(r"(?:(?:turn|make|put|bring)(?: it| the screen| the brightness)? )?(?:brightness )?(up|down|brighter|dimmer|darker)(?: a (?:bit|little))?"
                     r"|(?:turn|make) (?:it|the screen) (up|down|brighter|dimmer|darker)|brightness (up|down)|(?:dim|brighten)(?: the)?(?: screen| display)?", t)
    if m:
        word = next((g for g in m.groups() if g), None) or ("down" if t.startswith("dim") else "up")
        direction = "up" if word in ("up", "brighter") else "down"
        return hit([("brightness", [direction])], "Brighter." if direction == "up" else "Dimmer.")

    # ── theme ────────────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:(?:switch|go|change|turn|set|use|enable|activate)(?: it)?(?: on| to)? )?(dark|light)(?: mode| theme)?(?: on)?", t)
    if m and (len(t.split()) > 1):
        return hit([("theme", [m.group(1)])], f"{m.group(1).capitalize()} mode.")

    # ── timers ───────────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:set |start |make |create |begin )?(?:a |an |the )?(?:timer|countdown)(?: for| of)? (\d{1,3}) ?(minutes?|mins?|hours?|hrs?)(?: (?:called|for|named|labelled|labeled) (.+))?", t) \
        or re.fullmatch(r"(?:set |start |make |create )?(?:a |an )?(\d{1,3}) ?(minutes?|mins?|hours?|hrs?)(?: |-)?(?:timer|countdown)(?: (?:called|for|named) (.+))?", t) \

    if m:
        amount = int(m.group(1)) * (60 if m.group(2).startswith("h") else 1)
        label = (m.group(3) or "").strip()
        if 1 <= amount <= 600:
            args = [str(amount)] + (label.split() if label else [])
            spoken = f"{amount} minute" + ("" if amount == 1 else "s")
            return hit([("timer", args)], f"Timer set for {spoken}.")

    # ── alarms ───────────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:set |make |create |add )?(?:an |the |my )?alarm(?: for| at)? " + WHAT_TIME + r"(?: (?:called|named|for|labelled) (.+))?", t) \
        or re.fullmatch(r"wake me(?: up)?(?: at| by)? " + WHAT_TIME + r"()", t)
    if m:
        clock = next_clock(int(m.group(1)), int(m.group(2) or 0), m.group(3))
        if clock:
            label = (m.group(4) or "").strip()
            stamp = f"{clock[0]:02d}:{clock[1]:02d}"
            return hit([("alarm", [stamp] + (label.split() if label else []))], f"Alarm set for {stamp}.")

    # ── reminders and tasks ──────────────────────────────────────────────────
    m = re.fullmatch(r"remind me (?:to|about|that) (.+)", t)
    if m and not re.search(r"\b(?:in \d+|at \d|tomorrow|tonight|tomorrow|later|on (?:mon|tue|wed|thu|fri|sat|sun)\w*|next (?:week|month)|every)\b", m.group(1)):
        return hit([("remind", m.group(1).split())], "Reminder added.")
    m = re.fullmatch(r"(?:add|put) (.+?) (?:to|on) (?:my |the )?(?:to ?do|task|tasks|to-do|todo)(?: list)?", t) \
        or re.fullmatch(r"(?:add|create|new|make) (?:a )?(?:new )?(?:task|to ?do|to-do)(?: to| called| for| that)? (.+)", t)
    if m:
        return hit([("task", m.group(1).split())], "Task added.")

    # ── workspace ────────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:(?:go|switch|jump|move)(?: back)? (?:to )?|open |show )?(?:the )?(?:workspace|desktop|space) (\d{1,2})", t)
    if m and 1 <= int(m.group(1)) <= 20:
        return hit([("workspace", [m.group(1)])], f"Workspace {m.group(1)}.")

    # ── open an app ──────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:open|launch|start|run|fire up|bring up)(?: up)? (.+)", t)
    if m:
        name = re.sub(r"^(?:the |a )", "", m.group(1))
        name = re.sub(r"(?: app| application| program)$", "", name).strip()
        count = len(name.split())
        banned = r"\b(?:file|files|folder|folders|link|url|website|site|tab|window|sidebar|menu|overview|settings|panel|my|new|last|recent|document|pdf|image|photo|video|song|http)\b"
        if 1 <= count <= 3 and not re.search(banned, name) and not name.isdigit():
            return hit([("open", name.split())], f"Opening {name}.")

    return None


if __name__ == "__main__":
    # `voice_rules.py PHRASE [OFF_CSV [CUSTOM_JSON]]`: what the rules would do with a sentence (settings page "try it").
    import json
    import sys
    phrase = sys.argv[1] if len(sys.argv) > 1 else ""
    off = [item for item in (sys.argv[2] if len(sys.argv) > 2 else "").split(",") if item]
    try:
        custom = json.loads(sys.argv[3]) if len(sys.argv) > 3 else []
    except ValueError:
        custom = []
    result = match(phrase, off, custom)
    print(json.dumps(None if result is None else {"actions": [[v, a] for v, a in result["actions"]], "say": result["say"]}))

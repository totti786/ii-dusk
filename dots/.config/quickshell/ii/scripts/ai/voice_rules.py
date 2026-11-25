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
ORDINALS = {"first": 1, "second": 2, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
            "ninth": 9, "tenth": 10}
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
    # "the third workspace" -> "the workspace 3"
    text = re.sub(r"\b(" + "|".join(ORDINALS) + r") (workspace|desktop|space)\b",
                  lambda m: f"{m.group(2)} {ORDINALS[m.group(1)]}", text)
    text = words_to_digits(text)
    # "one hundred and twenty" came out as "1 hundred and 20": volume goes to 150, so hundreds matter.
    text = re.sub(r"\b(?:1|a) hundred(?: and)? (\d{1,2})\b", lambda m: str(100 + int(m.group(1))), text)
    return re.sub(r"\b(?:1|a) hundred\b", "100", text)


def hit(actions, say, **extra):
    return {"actions": [(verb, list(args)) for verb, args in actions], "say": say, **extra}


def confirm(actions, ask, group="system"):
    """A command that must be confirmed out loud first: nothing runs until the user says yes."""
    return hit(actions, ask, confirm=True, group=group)


def info(kind):
    """A question answered from the desktop context, with no action."""
    return hit([], "", info=kind, group="info")


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
          "alarm": "alarms", "remind": "notes", "task": "notes", "workspace": "workspace", "open": "apps",
          "toggle": "toggles", "power": "power", "capture": "capture", "panel": "panels", "window": "windows",
          "kitten": "kitten", "session": "sessions"}
# Verbs that need a spoken yes first. They are not in GROUPS, so a custom phrase can never run them
# without the confirmation, and the shell refuses them unless the confirmation really happened.
CONFIRMED_VERBS = ("lock", "suspend", "reboot", "shutdown", "close")
CONFIRMED_DONE = {"lock": "Locking.", "suspend": "Going to sleep.", "reboot": "Restarting.", "shutdown": "Shutting down.",
                  "close": "Closed."}


# What a model is told it may do: one line per verb, "usage" then what else the verb accepts. The prompt text
# is generated from this, so it cannot drift from GROUPS, and a test checks it against the shell's action table.
ACTION_HELP = (
    ("media play", "also pause, toggle, next, previous"),
    ("volume set 30", "0 to 150; also up, down, mute, unmute"),
    ("brightness set 60", "5 to 100; also up, down"),
    ("theme dark", "or light"),
    ("open firefox", "an application's name"),
    ("timer 10 pasta", "minutes, then an optional label"),
    ("alarm 07:30 wake up", "24-hour time, then an optional label"),
    ("remind call the bank", "adds a reminder"),
    ("task buy milk", "adds a to-do"),
    ("workspace 3", ""),
    ("toggle wifi off", "wifi, bluetooth, nightlight, dnd, awake, gamemode, mic; then on, off or toggle"),
    ("power saver", "or balanced, performance"),
    ("capture shot", "also area, record, region, stop, color"),
    ("panel settings open", "settings, sidebar, cheatsheet, apps, power, clipboard, mixer; then open or close"),
    ("window fullscreen", "also float, pin, move 3, focus firefox"),
    ("kitten play", "also pet, come, hop, trick, sleep, yawn, hide, laser, stop"),
    ("session focus claude", "bring a coding session's terminal forward: claude, codex or opencode; sending text to one or stopping it needs the user's spoken yes, so use the rules for that"),
)


def action_prompt():
    """The [[DO ...]] lines of the model prompt, from ACTION_HELP."""
    return "".join(f"  [[DO {usage}]]" + (f"  ({extra})" if extra else "") + "\n" for usage, extra in ACTION_HELP)


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


def match(text, off=(), custom=(), learned=()):
    """The command in `text`, or None. `off` names switched-off groups; `custom` is the user's phrases,
    tried first so they can override a built-in; `learned` are phrases the orb picked up itself, tried last
    so they can never override a built-in."""
    t = normalise(text)
    if not t:
        return None
    result = custom_match(t, custom) or builtin(t) or custom_match(t, learned)
    if result is None:
        return None
    groups = {GROUPS.get(verb) for verb, _ in result["actions"]} | {result.get("group")}
    if groups & set(off):
        return None
    return result

# ── toggles, power, capture, panels, windows, questions and the confirmed system commands ─────────
TOGGLE_NAMES = (
    ("wifi", r"wi ?-?fi|wireless|internet"),
    ("bluetooth", r"blue ?tooth"),
    ("nightlight", r"night ?light|night mode|blue light(?: filter)?|warm screen|eye comfort"),
    ("dnd", r"do not disturb|don't disturb|dnd|silent mode|notifications? (?:silent|silence|quiet)"),
    ("awake", r"(?:keep(?:ing)? (?:the )?(?:screen |computer |laptop |it )?awake)|caffeine|stay awake|no sleep"),
    ("gamemode", r"game ?mode|gaming mode"),
    ("mic", r"(?:the |my )?(?:mic|microphone)"),
)


def toggle_rule(t):
    """'turn off wifi', 'bluetooth on', 'enable dnd', 'toggle night light', 'mute the mic'."""
    m = re.fullmatch(r"(?:un)?mute " + STOP + r"(?:mic|microphone)|(?:un)?mute myself", t)
    if m:
        return hit([("toggle", ["mic", "on" if t.startswith("unmute") else "off"])],
                   "Mic on." if t.startswith("unmute") else "Mic muted.")
    if re.fullmatch(r"(?:don't|do not) (?:let (?:anything|anyone|anybody|people|notifications?) )?(?:disturb|bother|interrupt) me"
                    r"|i (?:don't|do not) want to be (?:disturbed|bothered|interrupted)", t):
        return hit([("toggle", ["dnd", "on"])], "Do not disturb on.")
    for name, words in TOGGLE_NAMES:
        if name == "mic":
            continue
        word = r"(?:the |my )?(?:" + words + r")"
        state = None
        found = (re.fullmatch(r"(?:turn|switch|set|put)(?: it)? (on|off) " + word, t)
                 or re.fullmatch(r"(?:turn|switch|set|put) " + word + r" (on|off)", t)
                 or re.fullmatch(word + r" (on|off)", t))
        if found:
            state = found.group(1)
        else:
            found = re.fullmatch(r"(enable|disable|activate|deactivate|start|stop) " + word, t)
            if found:
                state = "on" if found.group(1) in ("enable", "activate", "start") else "off"
        if state is None and re.fullmatch(r"(?:toggle|flip) " + word, t):
            state = "toggle"
        if state is not None:
            label = {"wifi": "Wi-Fi", "bluetooth": "Bluetooth", "nightlight": "Night light", "dnd": "Do not disturb",
                     "awake": "Keep awake", "gamemode": "Game mode"}[name]
            return hit([("toggle", [name, state])], f"{label} {'toggled' if state == 'toggle' else state}.")
    return None


POWER_WORDS = {"power saver": "saver", "power saving": "saver", "battery saver": "saver", "saver": "saver",
               "performance": "performance", "balanced": "balanced", "normal power": "balanced"}


def extended(t):
    if re.fullmatch(r"(?:keep|stay|stop (?:the )?(?:screen|it|computer|laptop) from sleeping|don't let (?:the )?(?:screen|it|computer|laptop) sleep)(?: the| my)?(?: screen| computer| laptop| it)?(?: awake| on)?", t) \
            and ("awake" in t or "sleeping" in t or "sleep" in t):
        return hit([("toggle", ["awake", "on"])], "Staying awake.")
    if re.fullmatch(r"(?:let|allow) (?:the |my )?(?:screen|computer|laptop|it) (?:sleep|turn off)|stop keeping (?:it |the screen |the computer )?awake", t):
        return hit([("toggle", ["awake", "off"])], "Normal sleep.")
    # toggles first: "turn on night light" must not reach the theme rule's "light".
    found = toggle_rule(t)
    if found:
        return found

    m = re.fullmatch(r"(?:(?:set|switch|go|change|turn on|enable|use|put it) ?(?:to |on |into )?)?(?:the )?(power saver|power saving|battery saver|performance|balanced|normal power)(?: mode| profile)?(?: on)?", t)
    if m and (len(t.split()) > 1):
        return hit([("power", [POWER_WORDS[m.group(1)]])], f"{m.group(1).capitalize()}.")

    # capture
    if re.fullmatch(r"(?:take |grab |capture )?(?:a |the )?(?:screenshot|screen shot|screen capture)(?: of (?:the |my )?(?:whole |full |entire )?(?:screen|desktop|display))?|(?:take|grab|capture) (?:the |my )?screen|full screenshot", t):
        return hit([("capture", ["shot"])], "Screenshot.")
    if re.fullmatch(r"(?:take |grab |capture )?(?:a )?(?:screenshot|screen shot) of (?:an |the |a )?(?:area|region|selection|part|section)|(?:screenshot|snip|crop)(?: an?)? (?:area|region|selection)|(?:snip|crop)(?: the screen)?|select (?:an? )?area", t):
        return hit([("capture", ["area"])], "Select an area.")
    if re.fullmatch(r"(?:start |begin )?(?:a )?(?:screen )?recording|(?:start |begin )?recording(?: the)?(?: screen)?|record(?: the| my)? screen|screen record(?:ing)?|start screen record(?:ing)?", t) \
            and not re.search(r"stop|end", t):
        return hit([("capture", ["record"])], "Recording.")
    if re.fullmatch(r"(?:start |begin )?record(?:ing)?(?: a| the)? (?:region|area|selection|part of the screen)", t):
        return hit([("capture", ["region"])], "Select an area to record.")
    if re.fullmatch(r"(?:stop|end|finish|save) (?:the |my )?(?:screen )?record(?:ing)?", t):
        return hit([("capture", ["stop"])], "Stopped recording.")
    if re.fullmatch(r"(?:open |launch |use |start )?(?:the |a )?colou?r pick(?:er)?|pick (?:a )?colou?r|what colou?r is this", t):
        return hit([("capture", ["color"])], "Pick a color.")

    # shell panels, before the generic "open <app>"
    PANELS = (("settings", r"settings|preferences|the settings app"), ("sidebar", r"sidebar|side bar|quick settings|control panel|right sidebar"),
              ("cheatsheet", r"cheat ?sheet|keyboard shortcuts|shortcuts|key ?binds?|hotkeys"), ("apps", r"app drawer|all apps|apps list|app list"),
              ("power", r"power menu|session menu|shutdown menu|logout menu"), ("clipboard", r"clipboard(?: history| manager)?"),
              ("mixer", r"(?:volume |audio |sound )?mixer"))
    for name, words in PANELS:
        found = re.fullmatch(r"(?:open|show|launch|bring up|pull up|display|toggle) (?:me )?(?:the |my )?(?:" + words + r")", t)
        if found:
            return hit([("panel", [name, "toggle" if t.startswith("toggle") else "open"])], f"Opening {name}.")
        found = re.fullmatch(r"(?:close|hide|dismiss) (?:the |my )?(?:" + words + r")", t)
        if found:
            return hit([("panel", [name, "close"])], f"Closing {name}.")

    # windows
    if re.fullmatch(r"(?:make |put |toggle |go )?(?:this |the |my )?(?:window |it |app )?(?:full ?screen|maximi[sz]e)(?: this| the)?(?: window)?|full ?screen(?: this| the)?(?: window)?|exit full ?screen|leave full ?screen", t):
        return hit([("window", ["fullscreen"])], "Fullscreen.")
    if re.fullmatch(r"(?:make |toggle |set )?(?:this |the |my )?(?:window |it |app )?(?:float(?:ing)?|tiled?)(?: this| the)?(?: window)?|float(?:ing)? (?:this|the) window|(?:toggle|switch) (?:floating|tiling)|tile (?:this|the) window", t):
        return hit([("window", ["float"])], "Done.")
    if re.fullmatch(r"(?:pin|unpin)(?: this| the| my)?(?: window| app)?|(?:keep|put) (?:this|the) window on top", t):
        return hit([("window", ["pin"])], "Done.")
    m = re.fullmatch(r"(?:move|send|put|throw|take) (?:this|the|my|that)(?: current)?(?: window| app)?(?: over)? to (?:the )?(?:workspace|desktop|space) (\d{1,2})", t)
    if m and 1 <= int(m.group(1)) <= 20:
        return hit([("window", ["move", m.group(1)])], f"Moved to {m.group(1)}.")
    m = re.fullmatch(r"(?:switch|go|jump|take me) to (?:the )?(.+?)(?: window| app)?|focus (?:the )?(.+?)(?: window| app)?|show me (?:the )?(.+?)(?: window| app)", t)
    if m:
        name = next((g for g in m.groups() if g), "").strip()
        banned = r"\b(?:workspace|desktop|space|mode|theme|dark|light|next|previous|last|back|home|top|bottom|left|right|sleep|settings|sidebar|overview|tab|page|song|track|video|my|new|a|an|different|another|topic|something|anything|else|other|one|it|that|this|\d+)\b"
        if 1 <= len(name.split()) <= 3 and not re.search(banned, name):
            return hit([("window", ["focus"] + name.split())], f"{name.capitalize()}.")

    # questions answered from the desktop context
    if re.fullmatch(r"(?:what(?:'s| is) the time|what time is it|what time(?: is it)? (?:now|right now)|time|the time|tell me the time|current time)", t):
        return info("time")
    if re.fullmatch(r"(?:what(?:'s| is) (?:the )?(?:date|day)(?: today| is it)?|what day is it(?: today)?|(?:today's|todays) date|the date|what(?:'s| is) today)", t):
        return info("date")
    if re.fullmatch(r"(?:how much |what(?:'s| is) (?:my |the )?)?battery(?: level| percentage| percent| left| life| status)?(?: (?:do i have|is left|left|remaining))?|how(?:'s| is) (?:my |the )?battery|(?:battery) status", t):
        return info("battery")
    if re.fullmatch(r"(?:what(?:'s| is) (?:this )?(?:song|track|music|playing|that song)(?: playing)?(?: now)?|what(?:'s| is) playing(?: now| right now)?|what song is (?:this|that|playing)|what(?:'s| is) this (?:song|track)|who(?:'s| is) (?:this|singing)|which song is this)", t):
        return info("playing")
    if re.fullmatch(r"(?:what(?:'s| is) (?:the |my )?(?:current )?volume(?: level)?|how loud(?: is it)?|volume level|what(?:'s| is) (?:the )?sound (?:level|at))", t):
        return info("volume")
    if re.fullmatch(r"(?:when(?:'s| is) (?:my )?next alarm|(?:what(?:'s| is) )?(?:my )?next alarm|do i have an alarm(?: set)?|any alarms?)", t):
        return info("alarm")
    if re.fullmatch(r"(?:do i have|any|are there(?: any)?|how many) (?:new |unread )?notifications?(?: do i have)?|(?:unread )?notifications?(?: count)?", t):
        return info("notifications")
    if re.fullmatch(r"(?:what(?:'s| is) (?:this |the )?(?:window|app|focused|active)(?: window)?(?: focused| open)?|what (?:window|app) is (?:this|that|focused|active|open)|which (?:window|app) is (?:this|focused|active|open)|what am i (?:looking at|using))", t):
        return info("focused")

    # these must be confirmed out loud before anything happens
    if re.fullmatch(r"(?:lock|secure) (?:the |my |this )?(?:screen|computer|laptop|pc|machine|session|desktop)|lock(?: it| up)?|lock screen", t):
        return confirm([("lock", [])], "Lock the screen? Say yes to confirm.")
    if re.fullmatch(r"(?:suspend|sleep|put (?:the |my |this )?(?:computer|laptop|pc|machine) (?:to sleep|in sleep mode|on standby)|go to sleep|hibernate)(?: the)?(?: computer| laptop| pc| machine)?|suspend (?:the )?(?:computer|laptop|pc|machine)", t) \
            and not re.search(r"\b(?:dim|screen|display|monitor)\b", t):
        return confirm([("suspend", [])], "Put the computer to sleep? Say yes to confirm.")
    if re.fullmatch(r"(?:restart|reboot)(?: the| my| this)?(?: computer| laptop| pc| machine| system)?", t) and t not in ("restart",):
        return confirm([("reboot", [])], "Restart the computer? Say yes to confirm.")
    if re.fullmatch(r"(?:shut ?down|power off|turn off|switch off|power down)(?: the| my| this)?(?: computer| laptop| pc| machine| system)|shut ?down|power off", t):
        return confirm([("shutdown", [])], "Shut down the computer? Say yes to confirm.")
    if re.fullmatch(r"(?:close|kill|quit|exit) (?:this|the|my|that|the current|the active|the focused)(?: current| active| focused)?(?: window| app| application| program)?|close it|close window|close the window", t):
        return confirm([("close", [])], "Close this window? Say yes to confirm.")
    return None



# ── Coding sessions (Claude Code, Codex, OpenCode) ─────────────────────────────────────────────
TOOL_WORDS = {"claude": r"claude(?: code)?|cloud code|clod", "codex": r"codex|codecs|code x", "opencode": r"open ?code|open-code"}
TOOL_ANY = "(" + "|".join(f"(?:{words})" for words in TOOL_WORDS.values()) + ")"
SESSION_NOUN = r"(?: ?(?:coding )?(?:sessions?|agents?|terminals?|instances?|windows?))?"


def tool_of(word):
    word = word.strip().lower()
    for name, words in TOOL_WORDS.items():
        if re.fullmatch(words, word):
            return name
    return None


def sessions_rule(t):
    """Questions about, and commands for, the running coding sessions. Sending text to one or stopping
    one is confirmed out loud first; the session it means is worked out by the voice agent."""
    if re.fullmatch(r"(?:what|how)(?:'s| is| are)? (?:are )?(?:all )?(?:my |the )?(?:coding |running )?(?:sessions?|agents?)(?: (?:doing|up to|going|running))?"
                    r"|(?:any|are there any|do i have any)(?: of)? (?:my |the )?(?:coding )?(?:sessions?|agents?)(?: running| working| active)?"
                    r"|(?:status|state|report) of (?:my |the )?(?:coding )?(?:sessions?|agents?)|(?:session|agent) (?:status|report)"
                    r"|(?:which|what) (?:coding )?(?:sessions?|agents?) (?:are )?(?:running|working|active|open)"
                    r"|(?:is|are) (?:any|anything)(?: of my)? (?:coding )?(?:sessions?|agents?)? ?(?:running|working|waiting)(?: for me)?"
                    r"|(?:any )?(?:sessions?|agents?) (?:waiting|need(?:ing)? me)", t):
        return info("sessions")
    m = re.fullmatch(r"(?:(?:what|how)(?:'s| is) )?" + TOOL_ANY + SESSION_NOUN + r"(?: (?:doing|working on|up to|status))?"
                     r"|(?:is|has) " + TOOL_ANY + SESSION_NOUN + r" (?:done|finished|working|running|stuck|waiting)(?: yet)?"
                     r"|(?:what|how)(?:'s| is) " + TOOL_ANY + SESSION_NOUN + r" (?:doing|up to|working on)", t)
    if m and len(t.split()) > 1:
        word = next(g for g in m.groups() if g)
        return info("sessions:" + (tool_of(word) or ""))
    # Any short sentence that is about the coding sessions themselves ("list the running coding sessions",
    # "show me my agents", "give me a rundown of claude sessions") and is not a command for one.
    if len(t.split()) <= 14 and not re.search(r"\b(?:how (?:do|to|can)|what is an?|why|build|create|write|make|install|define|explain)\b", t):
        about = re.search(r"\b(?:coding|running|active|open|my|the|all|any|your)\s+(?:coding\s+|running\s+|active\s+|open\s+)*(?:sessions?|agents?)\b", t) \
            or re.search(TOOL_ANY + r"\s+(?:coding\s+)?(?:sessions?|agents?)\b", t)
        if about and re.search(r"\b(?:list|show|give|get|tell|read|report|check|display|status|rundown|overview|summary|summari[sz]e|what|which|how|any|are|is|who|doing|running|working|done|finished|waiting|stuck)\b", t):
            only = re.search(TOOL_ANY + r"\s+(?:coding\s+)?(?:sessions?|agents?)?", t)
            tool = tool_of(only.group(1)) if only and only.group(1) else None
            return info("sessions" + (":" + tool if tool else ""))
    m = re.fullmatch(r"(?:status|state|progress) (?:of|for|on) " + TOOL_ANY + SESSION_NOUN + r"|" + TOOL_ANY + SESSION_NOUN + r" (?:status|state|progress)", t)
    if m and tool_of(next(g for g in m.groups() if g)):
        return info("sessions:" + tool_of(next(g for g in m.groups() if g)))
    m = re.fullmatch(r"(?:tell|ask|message|prompt|instruct|have|get) " + TOOL_ANY + SESSION_NOUN + r"(?: to| that| about)? (.{3,})", t) \
        or re.fullmatch(r"send (?:this |a message |the message )?(.{3,}?) to " + TOOL_ANY + SESSION_NOUN, t)
    if m:
        groups = m.groups()
        if re.fullmatch(TOOL_ANY, groups[0]):
            word, text = groups[0], groups[1]
        else:
            text, word = groups[0], groups[1]
        tool = tool_of(word)
        if tool and not re.fullmatch(r"(?:to |that |about )?(?:it|this|that)", text):
            return confirm([("session", ["send", tool, "", text.strip()])], "", group="sessions")
    m = re.fullmatch(r"(?:stop|interrupt|cancel|abort|halt|pause|cut off) " + TOOL_ANY + SESSION_NOUN, t)
    if m and tool_of(m.group(1)):
        return confirm([("session", ["stop", tool_of(m.group(1)), ""])], "", group="sessions")
    m = re.fullmatch(r"(?:show|go to|focus|switch to|bring up|take me to|open) (?:the )?" + TOOL_ANY + SESSION_NOUN, t)
    if m and tool_of(m.group(1)):
        return hit([("session", ["focus", tool_of(m.group(1)), ""])], "", group="sessions")
    return None


KITTEN_WORDS = r"(?:kitty|kitten|kitties|cat|kitty cat|the (?:kitty|kitten|cat))"


def kitten_rule(t):
    """'good kitty', 'pet the kitten', 'play with the cat', 'kitty sit', 'pspsps'."""
    if re.fullmatch(r"(?:ps+)+ ?(?:ps+)*|here " + KITTEN_WORDS + r"(?: kitty)*|come here " + KITTEN_WORDS, t):
        return hit([("kitten", ["come"])], "Here, kitty.")
    if re.fullmatch(r"(?:(?:such )?a )?(?:good|nice|sweet|clever|brave|pretty|cute) " + KITTEN_WORDS + r"|(?:pet|stroke|cuddle|scratch) (?:the |my )?" + KITTEN_WORDS, t):
        return hit([("kitten", ["pet"])], "Purr.")
    if re.fullmatch(r"(?:play|have fun) with (?:the |my )?" + KITTEN_WORDS + r"|" + KITTEN_WORDS + r" (?:play|playtime)|entertain (?:the |my )?" + KITTEN_WORDS, t):
        return hit([("kitten", ["play"])], "Playtime.")
    if re.fullmatch(KITTEN_WORDS + r" (?:sit|do a trick|trick|show me a trick)|(?:make|let) (?:the |my )?" + KITTEN_WORDS + r" (?:sit|do a trick)", t):
        return hit([("kitten", ["trick"])], "Good kitty.")
    if re.fullmatch(KITTEN_WORDS + r" (?:jump|hop)|make (?:the |my )?" + KITTEN_WORDS + r" jump", t):
        return hit([("kitten", ["hop"])], "Hop.")
    if re.fullmatch(KITTEN_WORDS + r" (?:sleep|nap|go to sleep|bedtime)|(?:put|send) (?:the |my )?" + KITTEN_WORDS + r" to (?:sleep|bed)", t):
        return hit([("kitten", ["sleep"])], "Sleep tight.")
    if re.fullmatch(KITTEN_WORDS + r" (?:wake up|get up)|wake (?:up )?(?:the |my )?" + KITTEN_WORDS, t):
        return hit([("kitten", ["wake"])], "Wakey wakey.")
    if re.fullmatch(r"(?:hide and seek|play hide and seek)(?: with (?:the |my )?" + KITTEN_WORDS + r")?", t):
        return hit([("kitten", ["hide"])], "Ready or not.")
    if re.fullmatch(r"(?:laser|laser pointer|laser dot|play with the laser)(?: for (?:the |my )?" + KITTEN_WORDS + r")?|(?:turn|switch) (?:on|off) (?:the )?laser", t):
        return hit([("kitten", ["laser"])], "Laser.")
    return None


def builtin(t):
    if not t or len(t.split()) > 14:
        return None
    found = kitten_rule(t) or sessions_rule(t)
    if found:
        return found
    found = extended(t)
    if found:
        return found

    # ── media ────────────────────────────────────────────────────────────────
    if re.fullmatch(r"(?:pause|stop|hold)" + MEDIA_NOUN + r"(?: for (?:a )?(?:second|sec|moment|minute|bit|while))?", t):
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
    # A plain complaint about the sound, said as the whole sentence ("it's too loud"), is a request.
    m = re.fullmatch(r"(?:it'?s|it is|that'?s|that is|this is|its)? ?(?:a (?:bit|little) |way |much |far |really |so |just )*too (loud|noisy|quiet|soft)", t)
    if m:
        loud = m.group(1) in ("loud", "noisy")
        return hit([("volume", ["down" if loud else "up"])], "Quieter." if loud else "Louder.")
    m = re.fullmatch(r"(?:set |change |put |make )?" + STOP + r"(?:volume|sound)(?: level)?(?: set)?(?: to| at)? (\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(?:set |make |turn )" + STOP + r"(?:volume|sound) (\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(?:set|put|turn) (?:the )?(?:volume|sound) (?:to |at )?(\d{1,3})(?: percent)?", t) \
        or re.fullmatch(r"(\d{1,3}) percent (?:volume|sound)", t)
    if m:
        level = int(m.group(1))
        if 0 <= level <= 150:
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
    m = re.fullmatch(r"(?:it'?s|it is|that'?s|this is|its)? ?(?:a (?:bit|little) |way |much |far |really |so )*too bright(?: in here)?"
                     r"|(?:the )?screen (?:is|looks|seems)? ?(?:a (?:bit|little) |way |much |far |really |so )*too (bright|dim|dark)", t)
    if m:
        dim = (m.group(1) or "") in ("dim", "dark")
        return hit([("brightness", ["up" if dim else "down"])], "Brighter." if dim else "Dimmer.")
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
    m = re.fullmatch(r"(?:(?:switch|go|change|turn|set|use|enable|activate|put on)(?: it)?(?: on| to)? )?(?:the |a )?(dark|light)(?: mode| theme| look| style| appearance)?(?: on)?", t)
    if m and (len(t.split()) > 1):
        return hit([("theme", [m.group(1)])], f"{m.group(1).capitalize()} mode.")

    # ── timers ───────────────────────────────────────────────────────────────
    m = re.fullmatch(r"(?:set |start |make |create |begin )?(?:a |an |the )?(?:timer|countdown)(?: for| of)? (\d{1,3}) ?(minutes?|mins?|hours?|hrs?)(?: (?:called|for|named|labelled|labeled) (.+))?", t) \
        or re.fullmatch(r"(?:set |start |make |create |give me )?(?:a |an )?(\d{1,3}) ?(minutes?|mins?|hours?|hrs?)(?: |-)?(?:timer|countdown)(?: (?:called|for|named) (.+))?", t) \

    if m:
        amount = int(m.group(1)) * (60 if m.group(2).startswith("h") else 1)
        label = re.sub(r"^(?:the|a|my) ", "", (m.group(3) or "").strip())
        if 1 <= amount <= 600:
            args = [str(amount)] + (label.split() if label else [])
            spoken = f"{amount} minute" + ("" if amount == 1 else "s")
            return hit([("timer", args)], f"Timer set for {spoken}.")

    # ── alarms ───────────────────────────────────────────────────────────────
    # "wake me up at seven thirty" reaches here as "at 7 30"
    t = re.sub(r"\b(at|for|by|alarm) (\d{1,2}) ([0-5]\d)\b", r"\1 \2:\3", t)
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
    m = re.fullmatch(r"(?:add|put) (.+?) (?:to|on) (?:my |the )?(?:to ?do|task|tasks|to-do|todo|shopping|grocery|groceries)(?: list)?", t) \
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
    try:
        learned = json.loads(sys.argv[4]) if len(sys.argv) > 4 else []
    except ValueError:
        learned = []
    result = match(phrase, off, custom, learned)
    print(json.dumps(None if result is None else {"actions": [[v, a] for v, a in result["actions"]], "say": result["say"]}))


def answer_info(kind, context):
    """The spoken answer to an info rule, read from the <desktop-context> lines the shell sent along.
    None when the context lacks it (the model, which sees the same lines, then takes the turn)."""
    lines = {}
    for line in str(context or "").splitlines():
        key, sep, value = line.partition(":")
        if sep:
            lines[key.strip().lower()] = value.strip()
    if kind == "time":
        m = re.search(r"(\d{1,2}):(\d{2})\s*$", lines.get("time", ""))
        if not m:
            return None
        hour, minute = int(m.group(1)), int(m.group(2))
        return f"It's {(hour % 12) or 12}:{minute:02d} {'PM' if hour >= 12 else 'AM'}."
    if kind == "date":
        value = lines.get("time", "")
        m = re.match(r"(\w+) (\d{1,2}) (\w+) (\d{4})", value)
        return f"It's {m.group(1)}, {m.group(2)} {m.group(3)} {m.group(4)}." if m else None
    if kind == "battery":
        m = re.match(r"(\d{1,3})% (charging|discharging)", lines.get("battery", ""))
        return f"{m.group(1)} percent, {m.group(2)}." if m else None
    if kind == "playing":
        value = lines.get("playing", "")
        if not value:
            return None
        if value.startswith("nothing"):
            return "Nothing is playing."
        return re.sub(r"\s*\((?:playing|paused)\)\s*$", "", value).replace(" — ", ", by ") + "."
    if kind == "volume":
        value = lines.get("volume", "")
        return ("Volume is " + value.replace("%", " percent").replace("(muted)", "and muted") + ".") if value else None
    if kind == "alarm":
        value = lines.get("next alarm", "")
        return f"Your next alarm is at {value}." if value else "You have no alarms set."
    if kind == "notifications":
        value = lines.get("unread notifications", "")
        return f"You have {value} unread." if value else "No unread notifications."
    if kind.startswith("sessions"):
        try:
            import agent_sessions
            sessions = agent_sessions.list_sessions()
            only = kind.partition(":")[2]
            if only:
                sessions = [s for s in sessions if s["tool"] == only]
                if not sessions:
                    return f"No {only.replace('opencode', 'OpenCode').capitalize()} session is running."
            return agent_sessions.spoken_summary(sessions)
        except Exception:
            return None
    if kind == "focused":
        value = lines.get("focused", "")
        return (re.sub(r"\s*\(workspace \d+\)\s*$", "", value).replace(" — ", ", ") + ".") if value else None
    return None


# ── Learning: a sentence no rule matched, which the model turned into an action ──────────────────
# Only plain settings are learned. Anything that depends on what was said before or on what is on screen
# ("turn it back up", "do that again"), anything negated or asked as a question, and the verbs that carry
# free text (remind, task, open, timer, alarm) is left to the model every time.
LEARNABLE = {"media", "volume", "brightness", "theme", "workspace", "toggle", "power", "capture", "panel", "window"}
CONTEXTUAL = re.compile(r"\b(?:it|that|this|those|them|there|again|back|more|less|same|another|other|undo|also|already|"
                        r"earlier|before|last|next|previous)\b")
NEGATED = re.compile(r"\b(?:not|never|without|no|don't|dont|doesn't|stop|cancel)\b")
QUESTION = re.compile(r"^(?:what|whats|what's|why|how|who|when|where|which|can|could|would|should|do|does|did|is|are|am|"
                      r"was|will|tell|show|explain|give|read|search|find)\b")
LEARN_AFTER = 2          # identical results before a phrase becomes a rule
LEARN_KEEP = 200         # candidates remembered at most


def learnable(text, actions):
    """(phrase, do) a rule could be made of, or None. `actions` is [(verb, [args])] the model chose."""
    t = normalise(text)
    words = t.split()
    if not 2 <= len(words) <= 8 or not actions or len(actions) > 3:
        return None
    if CONTEXTUAL.search(t) or NEGATED.search(t) or QUESTION.match(t):
        return None
    numbers = re.findall(r"\b\d{1,4}\b", t)
    if len(numbers) > 1:
        return None
    parts, used = [], False
    for verb, args in actions:
        if verb not in LEARNABLE:
            return None
        shown = []
        for arg in args:
            if numbers and str(arg) == numbers[0]:
                shown.append("{n}")
                used = True
            else:
                shown.append(str(arg))
        parts.append(" ".join([verb, *shown]))
    if numbers and not used:
        return None
    phrase = re.sub(r"\b" + numbers[0] + r"\b", "{n}", t) if used else t
    do = "; ".join(parts)
    # The rule must give back exactly what the model did for this very sentence.
    again = custom_match(t, [{"phrase": phrase, "do": do}])
    want = [(verb, [str(a) for a in args]) for verb, args in actions]
    if again is None or [(v, [str(a) for a in args]) for v, args in again["actions"]] != want:
        return None
    return phrase, do


def tally(candidates, phrase, do, now):
    """Count one more identical result for `phrase`. True when it has now happened often enough to learn
    (and the candidate is dropped). A different result for the same phrase starts the count again."""
    entry = candidates.get(phrase)
    if entry and entry.get("do") == do:
        entry["seen"] = int(entry.get("seen", 0)) + 1
    else:
        entry = {"do": do, "seen": 1}
    entry["at"] = now
    candidates[phrase] = entry
    if entry["seen"] >= LEARN_AFTER:
        del candidates[phrase]
        return True
    for stale in sorted(candidates, key=lambda key: candidates[key].get("at", 0))[:max(0, len(candidates) - LEARN_KEEP)]:
        del candidates[stale]
    return False

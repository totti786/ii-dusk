import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import voice_rules as vr  # noqa: E402


def actions(text):
    hit = vr.match(text)
    return None if hit is None else hit["actions"]


class Matches(unittest.TestCase):
    CASES = [
        ("pause", [("media", ["pause"])]),
        ("Pause the music.", [("media", ["pause"])]),
        ("can you please stop the song", [("media", ["pause"])]),
        ("play", [("media", ["play"])]),
        ("resume the music", [("media", ["play"])]),
        ("next song", [("media", ["next"])]),
        ("skip this track", [("media", ["next"])]),
        ("skip", [("media", ["next"])]),
        ("go back", [("media", ["previous"])]),
        ("previous track", [("media", ["previous"])]),
        ("volume 30", [("volume", ["set", "30"])]),
        ("Set the volume to 30%.", [("volume", ["set", "30"])]),
        ("set volume to thirty percent", [("volume", ["set", "30"])]),
        ("turn the volume to twenty five", [("volume", ["set", "25"])]),
        ("mute", [("volume", ["mute"])]),
        ("unmute the sound", [("volume", ["unmute"])]),
        ("louder", [("volume", ["up"])]),
        ("turn it down", [("volume", ["down"])]),
        ("turn the volume up a bit", [("volume", ["up"])]),
        ("make it quieter", [("volume", ["down"])]),
        ("turn it up a lot", [("volume", ["up"], ), ("volume", ["up"])]),
        ("brightness 70", [("brightness", ["set", "70"])]),
        ("set the brightness to 40 percent", [("brightness", ["set", "40"])]),
        ("brightness set 100", [("brightness", ["set", "100"])]),
        ("Brightness at 50.", [("brightness", ["set", "50"])]),
        ("volume set to 30", [("volume", ["set", "30"])]),
        ("Go to Workspace3", [("workspace", ["3"])]),
        ("brightness to 0", [("brightness", ["set", "5"])]),
        ("brighter", [("brightness", ["up"])]),
        ("make the screen dimmer", [("brightness", ["down"])]),
        ("dark mode", [("theme", ["dark"])]),
        ("switch to light mode", [("theme", ["light"])]),
        ("set a timer for 10 minutes", [("timer", ["10"])]),
        ("timer ten minutes", [("timer", ["10"])]),
        ("set a 5 minute timer", [("timer", ["5"])]),
        ("start a timer for 25 minutes called focus", [("timer", ["25", "focus"])]),
        ("set a timer for half an hour", [("timer", ["30"])]),
        ("timer for 2 hours", [("timer", ["120"])]),
        ("set an alarm for 6:30 pm", [("alarm", ["18:30"])]),
        ("alarm at 7:45 am", [("alarm", ["07:45"])]),
        ("alarm at 14:05", [("alarm", ["14:05"])]),
        ("wake me up at 6 am", [("alarm", ["06:00"])]),
        ("remind me to call the bank", [("remind", ["call", "the", "bank"])]),
        ("add milk to my todo list", [("task", ["milk"])]),
        ("add a task buy eggs", [("task", ["buy", "eggs"])]),
        ("go to workspace 3", [("workspace", ["3"])]),
        ("workspace two", [("workspace", ["2"])]),
        ("open firefox", [("open", ["firefox"])]),
        ("launch the terminal", [("open", ["terminal"])]),
        ("hey orb could you open spotify please", [("open", ["spotify"])]),
    ]

    def test_table(self):
        for text, expected in self.CASES:
            got = actions(text)
            self.assertEqual(None if got is None else [(v, a) for v, a in got], [(v, a) for v, a in expected], text)


class FallsThrough(unittest.TestCase):
    """Anything chatty, ambiguous or unfamiliar must reach the model."""

    def test_none(self):
        for text in (
            "", "hello", "what's the weather like", "play some jazz", "play bohemian rhapsody",
            "I'd like to pause and think about this for a while before we continue with the plan",
            "remind me to call mum tomorrow", "remind me in 10 minutes to stretch", "remind me at 5 to leave",
            "open my downloads folder", "open a new tab", "open the sidebar settings for bluetooth devices",
            "set a timer", "volume", "turn it", "set the brightness", "dark", "alarm", "set an alarm for later",
            "tell me a joke", "stop talking about that", "next week I travel to Cairo",
            "workspace", "go back to what we were saying about the budget", "can you explain dark mode",
            # the new commands must not swallow ordinary talk
            "I am locked out of my account", "take a break", "turn off the light", "turn on the music",
            "what is the battery of my phone", "the wifi at the cafe was terrible", "bluetooth is a standard",
            "close", "close the door", "sleep well", "I need to sleep", "restart", "lock the door", "shut down the server",
            "switch to a different topic", "go to the next one", "record a podcast about wifi",
            "performance", "balanced", "move this to the left", "pin it to the wall", "do not disturb me for ten minutes",
            "take a screenshot of the error and email it to me", "stop recording the meeting notes for later",
        ):
            self.assertIsNone(vr.match(text), text)


class Extended(unittest.TestCase):
    CASES = [
        ("turn off wifi", [("toggle", ["wifi", "off"])]),
        ("wi-fi on", [("toggle", ["wifi", "on"])]),
        ("turn on bluetooth", [("toggle", ["bluetooth", "on"])]),
        ("enable do not disturb", [("toggle", ["dnd", "on"])]),
        ("DND off", [("toggle", ["dnd", "off"])]),
        ("turn on night light", [("toggle", ["nightlight", "on"])]),
        ("toggle the night light", [("toggle", ["nightlight", "toggle"])]),
        ("keep the screen awake", [("toggle", ["awake", "on"])]),
        ("let the screen sleep", [("toggle", ["awake", "off"])]),
        ("mute the mic", [("toggle", ["mic", "off"])]),
        ("unmute the microphone", [("toggle", ["mic", "on"])]),
        ("turn on game mode", [("toggle", ["gamemode", "on"])]),
        ("power saver mode", [("power", ["saver"])]),
        ("switch to performance mode", [("power", ["performance"])]),
        ("balanced mode", [("power", ["balanced"])]),
        ("take a screenshot", [("capture", ["shot"])]),
        ("screenshot of an area", [("capture", ["area"])]),
        ("start recording", [("capture", ["record"])]),
        ("record a region", [("capture", ["region"])]),
        ("stop recording", [("capture", ["stop"])]),
        ("color picker", [("capture", ["color"])]),
        ("open settings", [("panel", ["settings", "open"])]),
        ("open the sidebar", [("panel", ["sidebar", "open"])]),
        ("show the cheat sheet", [("panel", ["cheatsheet", "open"])]),
        ("open the clipboard history", [("panel", ["clipboard", "open"])]),
        ("close the sidebar", [("panel", ["sidebar", "close"])]),
        ("open the power menu", [("panel", ["power", "open"])]),
        ("fullscreen", [("window", ["fullscreen"])]),
        ("make this window float", [("window", ["float"])]),
        ("pin this window", [("window", ["pin"])]),
        ("move this window to workspace 4", [("window", ["move", "4"])]),
        ("switch to firefox", [("window", ["focus", "firefox"])]),
        ("focus the terminal", [("window", ["focus", "terminal"])]),
        ("switch to dark mode", [("theme", ["dark"])]),
        ("go to workspace 3", [("workspace", ["3"])]),
        ("open firefox", [("open", ["firefox"])]),
    ]

    def test_table(self):
        for text, expected in self.CASES:
            got = actions(text)
            self.assertEqual(None if got is None else [(v, a) for v, a in got], expected, text)

    def test_risky_commands_ask_first(self):
        for text, verb in (("lock the screen", "lock"), ("lock", "lock"), ("go to sleep", "suspend"), ("suspend the computer", "suspend"),
                           ("restart the computer", "reboot"), ("reboot my laptop", "reboot"), ("shut down", "shutdown"),
                           ("shut down the computer", "shutdown"), ("close this window", "close"), ("close the window", "close")):
            hit = vr.match(text)
            self.assertIsNotNone(hit, text)
            self.assertTrue(hit.get("confirm"), text)
            self.assertEqual(hit["actions"][0][0], verb, text)
            self.assertIn("yes", hit["say"].lower(), text)

    def test_risky_verbs_are_not_in_custom_phrases(self):
        for verb in vr.CONFIRMED_VERBS:
            self.assertIsNone(vr.parse_do(verb), verb)
            self.assertIsNone(vr.match("do it", custom=[{"phrase": "do it", "do": verb}]), verb)

    def test_questions_are_info_not_actions(self):
        for text, kind in (("what time is it", "time"), ("what's the date", "date"), ("battery", "battery"),
                           ("how much battery do I have", "battery"), ("what's playing", "playing"),
                           ("what song is this", "playing"), ("what's the volume", "volume"),
                           ("when's my next alarm", "alarm"), ("any notifications", "notifications"),
                           ("what window is this", "focused")):
            hit = vr.match(text)
            self.assertIsNotNone(hit, text)
            self.assertEqual(hit.get("info"), kind, text)
            self.assertEqual(hit["actions"], [], text)

    def test_info_answers_come_from_the_context(self):
        context = ("time: Thu 19 Nov 2026, 23:40\nfocused: kitty — \"vim\" (workspace 2)\nplaying: Song — Artist (playing)\n"
                   "volume: 60%\nbattery: 81% discharging\nunread notifications: 3")
        self.assertEqual(vr.answer_info("time", context), "It's 11:40 PM.")
        self.assertEqual(vr.answer_info("battery", context), "81 percent, discharging.")
        self.assertEqual(vr.answer_info("playing", context), "Song, by Artist.")
        self.assertEqual(vr.answer_info("volume", context), "Volume is 60 percent.")
        self.assertEqual(vr.answer_info("notifications", context), "You have 3 unread.")
        self.assertEqual(vr.answer_info("playing", "playing: nothing"), "Nothing is playing.")
        self.assertIsNone(vr.answer_info("battery", "time: x"))
        self.assertIsNone(vr.answer_info("time", ""))

    def test_new_groups_can_be_switched_off(self):
        for text, group in (("turn off wifi", "toggles"), ("power saver mode", "power"), ("take a screenshot", "capture"),
                            ("open settings", "panels"), ("fullscreen", "windows"), ("what time is it", "info"),
                            ("lock the screen", "system")):
            self.assertIsNotNone(vr.match(text), text)
            self.assertIsNone(vr.match(text, off=[group]), text)


class NaturalPhrasing(unittest.TestCase):
    """Sentences people really say, which the plain command forms used to miss. Every positive has a
    negative beside it: a rule that fires on a casual sentence costs more than one that misses."""
    CASES = [
        ("it's too loud", [("volume", ["down"])]),
        ("it is way too quiet", [("volume", ["up"])]),
        ("it's too bright in here", [("brightness", ["down"])]),
        ("the screen is too dark", [("brightness", ["up"])]),
        ("stop the music for a second", [("media", ["pause"])]),
        ("pause for a moment", [("media", ["pause"])]),
        ("switch to the light theme please", [("theme", ["light"])]),
        ("put on a dark look", [("theme", ["dark"])]),
        ("wake me at 7 30 am", [("alarm", ["07:30"])]),
        ("add milk to my shopping list", [("task", ["milk"])]),
        ("don't let anything disturb me", [("toggle", ["dnd", "on"])]),
        ("go to the third workspace", [("workspace", ["3"])]),
        ("mute myself", [("toggle", ["mic", "off"])]),
        ("unmute myself", [("toggle", ["mic", "on"])]),
        ("give me a ten minute timer for the pasta", [("timer", ["10", "pasta"])]),
    ]
    NOT_COMMANDS = [
        "it's too loud outside", "it's too loud for me to think", "it's too dark in here", "I like quiet music",
        "what is the volume of a sphere", "can you explain how timers work", "do I have any alarms", "tell me a joke",
        "what is the capital of France", "how much battery do I have", "thanks that was great", "what's two plus two",
        "I can't hear anything", "I can't see the screen", "why is it too loud", "the third workspace is empty",
        "the second song was better", "don't stop the music", "close all my browser windows",
        "search the web for the weather",
    ]

    def test_table(self):
        for text, want in self.CASES:
            with self.subTest(text):
                self.assertEqual(actions(text), want)

    def test_casual_sentences_stay_unmatched(self):
        for text in self.NOT_COMMANDS:
            with self.subTest(text):
                hit = vr.match(text)
                self.assertTrue(hit is None or not hit["actions"], hit)


class ActionTable(unittest.TestCase):
    QML = Path(__file__).resolve().parents[3] / "services" / "ai" / "AiCompanionActions.qml"

    def qml_verbs(self):
        text = self.QML.read_text()
        body = text.split("readonly property var table: ({", 1)[1]
        return set(re.findall(r"^        (\w+): args =>", body, re.M))

    def test_every_verb_the_models_are_told_about_exists_in_the_shell(self):
        told = {usage.split()[0] for usage, _ in vr.ACTION_HELP}
        self.assertEqual(told, set(vr.GROUPS))
        self.assertLessEqual(told | set(vr.CONFIRMED_VERBS), self.qml_verbs())

    def test_the_prompt_lists_each_verb_once(self):
        lines = vr.action_prompt().splitlines()
        self.assertEqual(len(lines), len(vr.ACTION_HELP))
        self.assertTrue(all(line.startswith("  [[DO ") for line in lines))


class Learning(unittest.TestCase):
    """The orb remembers a sentence the model turned into actions, but only a plain, context-free one."""

    def test_a_plain_setting_is_learnable(self):
        self.assertEqual(vr.learnable("movie mode please", [("theme", ["dark"]), ("brightness", ["set", "30"])]),
                         ("movie mode", "theme dark; brightness set 30"))
        self.assertEqual(vr.learnable("crank the sound to fifty", [("volume", ["set", "50"])]),
                         ("crank the sound to {n}", "volume set {n}"))

    def test_learned_phrase_gives_back_the_same_actions(self):
        phrase, do = vr.learnable("crank the sound to fifty", [("volume", ["set", "50"])])
        rule = {"phrase": phrase, "do": do, "say": ""}
        self.assertEqual(vr.match("crank the sound to 70", learned=[rule])["actions"], [("volume", ["set", "70"])])

    def test_context_dependent_and_risky_sentences_are_not_learned(self):
        refused = [
            ("turn it back up", [("volume", ["up"])]),
            ("do that again", [("media", ["next"])]),
            ("a bit more", [("volume", ["up"])]),
            ("don't mute anything", [("volume", ["mute"])]),
            ("what is the volume", [("volume", ["up"])]),
            ("lock the screen", [("lock", [])]),
            ("close this window", [("close", [])]),
            ("remind me about the thing", [("remind", ["the", "thing"])]),
            ("open the browser", [("open", ["firefox"])]),
            ("set an alarm for the morning", [("alarm", ["07:30"])]),
            ("goodnight", [("theme", ["dark"])]),   # one word: too easy to mishear
            ("one two three four five six seven eight nine", [("theme", ["dark"])]),
            ("set it to 40 and 50", [("volume", ["set", "40"])]),
            ("make it 40", [("volume", ["set", "30"])]),   # the number said is not the one used
        ]
        for text, chosen in refused:
            with self.subTest(text):
                self.assertIsNone(vr.learnable(text, chosen))

    def test_a_learned_phrase_never_overrides_a_builtin(self):
        rule = {"phrase": "pause the music", "do": "volume mute", "say": ""}
        self.assertEqual(vr.match("pause the music", learned=[rule])["actions"], [("media", ["pause"])])

    def test_it_takes_two_identical_results(self):
        seen = {}
        self.assertFalse(vr.tally(seen, "movie mode", "theme dark", 1))
        self.assertTrue(vr.tally(seen, "movie mode", "theme dark", 2))
        self.assertNotIn("movie mode", seen)

    def test_a_different_result_starts_the_count_again(self):
        seen = {}
        vr.tally(seen, "cosy", "theme dark", 1)
        self.assertFalse(vr.tally(seen, "cosy", "brightness down", 2))
        self.assertFalse(vr.tally(seen, "cosy", "theme dark", 3))
        self.assertTrue(vr.tally(seen, "cosy", "theme dark", 4))

    def test_candidates_are_bounded(self):
        seen = {}
        for number in range(vr.LEARN_KEEP + 50):
            vr.tally(seen, f"phrase {number}", "theme dark", number)
        self.assertLessEqual(len(seen), vr.LEARN_KEEP)


class Settings(unittest.TestCase):
    def test_a_switched_off_group_falls_through(self):
        self.assertIsNone(vr.match("pause", off=["media"]))
        self.assertIsNotNone(vr.match("volume 30", off=["media"]))
        self.assertIsNone(vr.match("open firefox", off=["apps"]))

    def test_custom_phrase_runs_several_actions(self):
        custom = [{"phrase": "movie mode", "do": "theme dark; volume set 20; brightness set 30", "say": "Enjoy."}]
        hit = vr.match("Movie mode!", custom=custom)
        self.assertEqual(hit["actions"], [("theme", ["dark"]), ("volume", ["set", "20"]), ("brightness", ["set", "30"])])
        self.assertEqual(hit["say"], "Enjoy.")

    def test_custom_number_placeholder(self):
        custom = [{"phrase": "make it {n}", "do": "volume set {n}"}]
        self.assertEqual(vr.match("make it 45", custom=custom)["actions"], [("volume", ["set", "45"])])
        self.assertIsNone(vr.match("make it loud", custom=custom))

    def test_custom_wins_over_builtin_and_unknown_verbs_are_ignored(self):
        custom = [{"phrase": "pause", "do": "media toggle"}, {"phrase": "nuke it", "do": "rm -rf /"}]
        self.assertEqual(vr.match("pause", custom=custom)["actions"], [("media", ["toggle"])])
        self.assertIsNone(vr.match("nuke it", custom=custom))

    def test_a_custom_phrase_in_a_switched_off_group_is_off_too(self):
        self.assertIsNone(vr.match("movie mode", off=["theme"], custom=[{"phrase": "movie mode", "do": "theme dark"}]))


class Clock(unittest.TestCase):
    def test_pm_and_am_resolve_to_a_24_hour_time(self):
        self.assertEqual(vr.next_clock(6, 30, "pm"), (18, 30))
        self.assertEqual(vr.next_clock(12, 0, "am"), (0, 0))
        self.assertEqual(vr.next_clock(12, 0, "pm"), (12, 0))
        self.assertIsNone(vr.next_clock(13, 0, "pm"))
        self.assertIsNone(vr.next_clock(7, 61, None))

    def test_bare_hour_is_the_next_occurrence(self):
        hour, minute = vr.next_clock(7, 0, None)
        self.assertIn(hour, (7, 19))
        self.assertEqual(minute, 0)


class Spoken(unittest.TestCase):
    def test_confirmation_is_short(self):
        self.assertEqual(vr.match("volume 30")["say"], "Volume 30.")
        self.assertEqual(vr.match("set a timer for 1 minute")["say"], "Timer set for 1 minute.")

    def test_numbers(self):
        self.assertEqual(vr.words_to_digits("twenty five percent"), "25 percent")
        self.assertEqual(vr.words_to_digits("ten minutes"), "10 minutes")


if __name__ == "__main__":
    unittest.main()

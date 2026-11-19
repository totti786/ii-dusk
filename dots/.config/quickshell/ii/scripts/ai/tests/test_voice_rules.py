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
            "", "hello", "what's the weather like", "what's playing", "play some jazz", "play bohemian rhapsody",
            "I'd like to pause and think about this for a while before we continue with the plan",
            "remind me to call mum tomorrow", "remind me in 10 minutes to stretch", "remind me at 5 to leave",
            "open the sidebar", "open my downloads folder", "open a new tab", "open settings",
            "set a timer", "volume", "turn it", "set the brightness", "dark", "alarm", "set an alarm for later",
            "tell me a joke", "stop talking about that", "next week I travel to Cairo",
            "workspace", "go back to what we were saying about the budget", "can you explain dark mode",
        ):
            self.assertIsNone(vr.match(text), text)


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

"""Contract tests for the battery-full announcement.

The island draws its own battery banner, and the desktop notification used to say the same
thing on top of it. One event, one announcement - and a refusal (the quiet window after a
boot, a reload or an unlock) may not swallow it.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
BATTERY = ROOT / "services/Battery.qml"
SOURCE = ROOT / "modules/ii/dynamicIsland/core/sources/BatterySource.qml"
POLICY = ROOT / "modules/ii/dynamicIsland/core/IslandPolicy.qml"
STATES = ROOT / "GlobalStates.qml"


class BatteryIslandNotificationTest(unittest.TestCase):
    def setUp(self):
        self.battery = BATTERY.read_text(encoding="utf-8")
        self.source = SOURCE.read_text(encoding="utf-8")
        self.policy = POLICY.read_text(encoding="utf-8")
        self.states = STATES.read_text(encoding="utf-8")

    def test_ownership_is_published_by_the_policy(self):
        # Read from the island's own answer rather than re-derived in the service.
        self.assertIn('property: "islandOwnsBattery"', self.policy)
        self.assertIn("property bool islandOwnsBattery: false", self.states)

    def test_a_full_charge_is_offered_to_the_island_first(self):
        self.assertIn("signal chargedReached(string title, string body, string icon)", self.battery)
        self.assertIn("GlobalStates.islandOwnsBattery", self.battery)
        # The island has to be on screen: a fullscreen window hides it, and its banner then
        # goes unread, so the notification stays.
        self.assertIn("!Notifications.focusedWindowFullscreen", self.battery)
        # And its surface has to exist at all (the Tablet shell draws none).
        self.assertIn("StartupState.islandReady", self.battery)

    def test_the_island_hands_the_event_back_when_it_refuses(self):
        self.assertIn("function announce(reason): bool", self.source)
        self.assertIn("function onChargedReached(title, body, icon)", self.source)
        handler = self.source.split("function onChargedReached", 1)[1].split("}", 1)[0]
        self.assertIn("Battery.notify(", handler)

    def test_the_end_of_charge_is_not_announced_twice(self):
        # The banner must be spent on the service's announcement alone: a second one here
        # would hit the cooldown and push the event into a notification as a duplicate.
        self.assertIn("if (Battery.isFullyCharged || Battery.chargeLimitReached)", self.source)

    def test_the_soft_reminder_stays_a_notification(self):
        # The island's banner reads "Charging" below the end of charge, so the "consider
        # unplugging" level has nothing on the island to say it.
        reminder = self.battery.split("if (opts.full <= 100 && level >= opts.full)", 1)[1].split("}", 1)[0]
        self.assertIn("root.chargedArmed = false;", reminder)
        self.assertNotIn(", true)", reminder)


if __name__ == "__main__":
    unittest.main()

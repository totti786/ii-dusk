"""Contract tests for which paired phone the shell treats as "the" phone.

`peers.json` has no order: re-pairing the same phone appends a new entry and leaves the
old one first (the helper knows a device only by the id it minted). Reading `peers[0]`
therefore named a phone that was not connected - the Phone sidebar said "No device
connected" while the phone was linked, and the gallery, camera and mic opened on the
stale entry.
"""
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[2]
LINK = ROOT / "services/IiLinkService.qml"
SERVICES = ROOT / "services"


class PrimaryPhoneTest(unittest.TestCase):
    def setUp(self):
        self.link = LINK.read_text(encoding="utf-8")

    def test_a_live_connection_wins_over_the_list_order(self):
        primary = self.link.split("readonly property var primaryPeer:", 1)[1]
        self.assertLess(primary.index("Object.keys(root.connections"), primary.index("for (const p of root.peers)"),
                        "the connected phone must be preferred before the recently-seen one")

    def test_the_fallback_is_the_most_recently_seen_peer(self):
        primary = self.link.split("readonly property var primaryPeer:", 1)[1]
        self.assertIn("lastSeen", primary)
        self.assertIn("> Number(best.lastSeen", primary)

    def test_the_device_the_sidebar_gets_is_the_primary_peer(self):
        device = self.link.split("readonly property var phoneDevice:", 1)[1].split("function ", 1)[0]
        self.assertIn("root.primaryPeer", device)
        self.assertIn("root.connections[peer.id]", device)

    def test_nothing_reads_the_list_position_as_a_device(self):
        for path in SERVICES.glob("*.qml"):
            text = path.read_text(encoding="utf-8")
            with self.subTest(file=path.name):
                self.assertNotIn("peers[0]", text,
                                 "peers.json is unordered; use IiLinkService.primaryPeer/primaryDev")


if __name__ == "__main__":
    unittest.main()

"""Regression contract for CD media artwork and its unclipped shadow."""

import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CD_MEDIA = ROOT / "modules/ii/background/widgets/media/CdMediaWidget.qml"


class CdMediaWidgetContractTests(unittest.TestCase):
    def setUp(self):
        self.source = CD_MEDIA.read_text(encoding="utf-8")

    def test_artwork_comes_from_the_shared_cover_art_service(self):
        # CoverArt.source() starts the download itself the first time a binding reads it, so a
        # track that is already playing when the widget loads is fetched without a local refresh.
        self.assertIn("CoverArt.source(root.rawArtUrl)", self.source)

    def test_artwork_shadow_has_room_to_fade_below_the_viewport(self):
        self.assertIn("id: albumArtShadow", self.source)
        self.assertIn("source: circleMaskArea", self.source)
        self.assertIn("transparentBorder: true", self.source)
        self.assertIn("z: -1", self.source)


if __name__ == "__main__":
    unittest.main()

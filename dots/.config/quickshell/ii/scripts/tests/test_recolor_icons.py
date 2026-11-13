#!/usr/bin/env python3
"""Tests for scripts/colors/recolor_icons.py: folder icons recoloured into an overlay theme."""

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
_argv = sys.argv
sys.argv = [_argv[0]]
_spec = importlib.util.spec_from_file_location("recolor_icons", ROOT / "scripts/colors/recolor_icons.py")
recolor = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(recolor)
sys.argv = _argv

SVG = '<svg><path style="fill:#5294e2"/><path style="fill:#4877b1"/><path style="fill:#1D344F"/><path style="fill:#fff"/></svg>'
INDEX = """[Icon Theme]
Name=Mock
Directories=48x48/places,48x48/apps

[48x48/places]
Size=48
Type=Fixed
Context=Places

[48x48/apps]
Size=48
Type=Fixed
Context=Applications
"""


def make_base(root):
    base = Path(root) / "Mock"
    places = base / "48x48/places"
    places.mkdir(parents=True)
    (base / "48x48/apps").mkdir(parents=True)
    (base / "index.theme").write_text(INDEX)
    (places / "folder-blue.svg").write_text(SVG)
    (places / "user-blue-desktop.svg").write_text(SVG)
    (places / "folder-red.svg").write_text(SVG)  # another colour: not touched
    os.symlink("folder-blue.svg", places / "folder.svg")
    os.symlink("user-blue-desktop.svg", places / "user-desktop.svg")
    os.symlink("user-desktop.svg", places / "desktop.svg")  # alias of an alias
    (base / "48x48/apps/app.svg").write_text(SVG)
    return base


class RecolorIconsTest(unittest.TestCase):
    def test_darker_clamps_each_channel(self):
        self.assertEqual(recolor.darker("102030", 0x20), "000010")
        self.assertEqual(recolor.darker("ffffff", 20), "ebebeb")

    def test_overlay_recolors_blue_folders_and_links_aliases(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = make_base(tmp)
            staging = Path(tmp) / "out"
            staging.mkdir()
            recolored, linked = recolor.build_overlay(str(base), "Mock", "d4bbff", str(staging))
            places = staging / "48x48/places"
            self.assertEqual(recolored, 2)
            self.assertEqual(linked, 3)
            text = (places / "folder-blue.svg").read_text()
            self.assertIn("#" + recolor.darker("d4bbff", recolor.FOLDER_DARKEN), text)
            self.assertNotIn("#d4bbff", text.lower())
            self.assertNotIn("5294e2", text.lower())
            self.assertNotIn("1d344f", text.lower())
            self.assertIn("#fff", text)
            # Aliases resolve inside the overlay, including the alias of an alias.
            for name, target in (("folder.svg", "folder-blue.svg"),
                                 ("user-desktop.svg", "user-blue-desktop.svg"),
                                 ("desktop.svg", "user-blue-desktop.svg")):
                self.assertTrue((places / name).is_symlink(), name)
                self.assertEqual(Path(os.path.realpath(places / name)), places / target, name)
            self.assertFalse((places / "folder-red.svg").exists())
            self.assertFalse((staging / "48x48/apps").exists())

    def test_index_inherits_the_base_and_declares_only_filled_dirs(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = make_base(tmp)
            staging = Path(tmp) / "out"
            staging.mkdir()
            recolor.build_overlay(str(base), "Mock", "d4bbff", str(staging))
            index = recolor.read_index(str(staging))
            self.assertEqual(index.get("Icon Theme", "Name"), "DynamicTheme")
            self.assertEqual(index.get("Icon Theme", "Inherits"), "Mock,hicolor")
            self.assertEqual(index.get("Icon Theme", "Directories"), "48x48/places")
            self.assertEqual(index.get("48x48/places", "Context"), "Places")

    def test_base_without_blue_folders_gives_an_empty_overlay(self):
        with tempfile.TemporaryDirectory() as tmp:
            base = Path(tmp) / "Plain"
            (base / "48x48/places").mkdir(parents=True)
            (base / "index.theme").write_text(INDEX)
            (base / "48x48/places/folder.svg").write_text("<svg/>")
            staging = Path(tmp) / "out"
            staging.mkdir()
            self.assertEqual(recolor.build_overlay(str(base), "Plain", "d4bbff", str(staging)), (0, 0))
            self.assertEqual(recolor.read_index(str(staging)).get("Icon Theme", "Directories"), "")


if __name__ == "__main__":
    unittest.main()

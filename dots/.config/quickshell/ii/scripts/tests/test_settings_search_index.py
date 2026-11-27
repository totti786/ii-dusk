#!/usr/bin/env python3
"""The Settings search index: what is extracted from a page, and when the cache is reused."""

import json
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "settings"))

import search_index  # noqa: E402

PAGE = r'''import QtQuick
import qs.modules.common.widgets

ContentPage {
    ContentSection {
        // The user's { prose } is not code.
        icon: "bolt"
        title: Translation.tr("Power")

        ConfigSwitch {
            text: Translation.tr("Show \"Locked\" text")
            description: Translation.tr("Write it under the clock.")
        }
        ContentSubsection {
            title: Translation.tr("Idle")
            ConfigSpinBox { text: Translation.tr("Minutes") }
            ConfigSubpageRow { title: Translation.tr("Closure only"); onClicked: open() }
        }
    }
    ContentSection {
        title: modelData.name
        ConfigSwitch { text: Translation.tr("Under a computed heading") }
    }
}
'''


class Extraction(unittest.TestCase):
    def test_sections_subsections_and_controls(self):
        [section] = search_index.index_file(PAGE, "/p/Page.qml", "power", "")
        self.assertEqual((section["pageId"], section["title"], section["icon"]), ("power", "Power", "bolt"))
        [item] = section["items"]
        self.assertEqual(item["text"], 'Show "Locked" text')
        self.assertEqual(item["extra"], ["Write it under the clock."])
        self.assertEqual(item["source"], PAGE[item["sourceStart"]:item["sourceEnd"]])
        self.assertTrue(item["source"].startswith("ConfigSwitch {"))
        self.assertTrue(item["source"].endswith("}"))
        [sub] = section["subsections"]
        self.assertEqual(sub["title"], "Idle")
        self.assertEqual([i["text"] for i in sub["items"]], ["Minutes"])


class ListRows(unittest.TestCase):
    def test_delegates_are_not_cloned(self):
        page = (
            'ContentSection { title: Translation.tr("Saved")\n Repeater { model: 3\n'
            ' delegate: ColumnLayout {\n ConfigSwitch { required property int index; text: "Row" }\n'
            ' ConfigSpinBox { text: modelData.name } } }\n'
            ' ConfigComboBox { text: "Own"; model: list.map(modelData => modelData.name) } }')
        [section] = search_index.index_file(page, "Page.qml", "p", "")
        self.assertEqual([i["text"] for i in section["items"]], ["Own"])


class Cache(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name) / "shell"
        configs = self.root / "modules/settings/configs"
        configs.mkdir(parents=True)
        self.page = configs / "Page.qml"
        self.page.write_text(PAGE, encoding="utf-8")
        self.cache = Path(self.tmp.name) / "cache" / "search.json"
        self.pages = json.dumps([{"id": "power", "component": "modules/settings/configs/Page.qml"}])

    def index(self, pages=None):
        return search_index.cached_index(str(self.root), pages or self.pages, self.cache)

    def test_reused_until_a_page_changes(self):
        first = self.index()
        self.assertEqual(json.loads(first)["sections"][0]["title"], "Power")
        with mock.patch.object(search_index, "build", side_effect=AssertionError("rebuilt")):
            self.assertEqual(self.index(), first)
        self.page.write_text(PAGE.replace('"Power"', '"Energy"'), encoding="utf-8")
        os.utime(self.page, ns=(1, 1))
        self.assertEqual(json.loads(self.index())["sections"][0]["title"], "Energy")

    def test_page_list_is_part_of_the_key(self):
        self.index()
        other = json.dumps([{"id": "renamed", "component": "modules/settings/configs/Page.qml"}])
        self.assertEqual(json.loads(self.index(other))["sections"][0]["pageId"], "renamed")

    def test_damaged_cache_is_rebuilt(self):
        first = self.index()
        self.cache.write_text(self.cache.read_text(encoding="utf-8")[:-20], encoding="utf-8")
        self.assertEqual(self.index(), first)

    def test_unwritable_cache_still_answers(self):
        self.cache.parent.write_text("a file where the folder should be", encoding="utf-8")
        with mock.patch("sys.stderr"):
            self.assertIn("Power", self.index())


if __name__ == "__main__":
    unittest.main()

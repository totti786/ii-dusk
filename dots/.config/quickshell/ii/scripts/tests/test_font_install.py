"""font_install.py: local installs, archive safety, and that remove only touches its own folders."""
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "fonts" / "font_install.py"
SYSTEM_FONT = next((p for p in Path("/usr/share/fonts").rglob("*.ttf")), None)


def run(root, *args):
    env = dict(os.environ, II_FONT_DIR=str(root))
    done = subprocess.run([sys.executable, str(SCRIPT), *args], env=env, capture_output=True, text=True)
    last = [l for l in done.stdout.splitlines() if l.startswith("RESULT ")]
    return json.loads(last[-1][7:]) if last else {"ok": False, "raw": done.stdout + done.stderr}


@unittest.skipIf(SYSTEM_FONT is None, "no system .ttf to use as a sample")
class Install(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "fonts"
        self.work = Path(self.tmp.name) / "work"
        self.work.mkdir()
        self.data = SYSTEM_FONT.read_bytes()

    def tearDown(self):
        self.tmp.cleanup()

    def test_single_file_installs_lists_and_removes(self):
        f = self.work / "Sample.ttf"
        f.write_bytes(self.data)
        r = run(self.root, "file", str(f))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["files"], 1)
        self.assertTrue((self.root / "ii-installed" / r["folder"] / ".ii-font.json").exists())
        self.assertEqual([i["folder"] for i in run(self.root, "list")["items"]], [r["folder"]])
        self.assertTrue(run(self.root, "remove", r["folder"])["ok"])
        self.assertEqual(run(self.root, "list")["items"], [])

    def test_zip_is_flattened_and_non_fonts_are_ignored(self):
        z = self.work / "pack.zip"
        with zipfile.ZipFile(z, "w") as archive:
            archive.writestr("deep/dir/A.ttf", self.data)
            archive.writestr("../../escape.ttf", self.data)
            archive.writestr("readme.txt", b"hi")
        r = run(self.root, "file", str(z))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["files"], 2)
        folder = self.root / "ii-installed" / r["folder"]
        self.assertTrue((folder / "A.ttf").exists() and (folder / "escape.ttf").exists())
        self.assertFalse((Path(self.tmp.name) / "escape.ttf").exists())
        self.assertFalse((folder / "readme.txt").exists())

    def test_folder_install(self):
        d = self.work / "MyFonts"
        (d / "sub").mkdir(parents=True)
        (d / "sub" / "B.ttf").write_bytes(self.data)
        r = run(self.root, "file", str(d))
        self.assertTrue(r["ok"], r)
        self.assertEqual(r["files"], 1)

    def test_a_renamed_non_font_is_refused(self):
        f = self.work / "fake.ttf"
        f.write_bytes(b"not a font at all")
        r = run(self.root, "file", str(f))
        self.assertFalse(r["ok"])
        self.assertFalse((self.root / "ii-installed").exists() and any((self.root / "ii-installed").iterdir()))

    def test_remove_refuses_foreign_and_traversing_names(self):
        (self.root / "Mine").mkdir(parents=True)
        (self.root / "Mine" / "keep.ttf").write_bytes(self.data)
        (self.root / "ii-installed" / "Unmarked").mkdir(parents=True)
        for name in ("..", "../Mine", "Unmarked", "Missing", "a/b"):
            self.assertFalse(run(self.root, "remove", name)["ok"], name)
        self.assertTrue((self.root / "Mine" / "keep.ttf").exists())
        self.assertTrue((self.root / "ii-installed" / "Unmarked").exists())

    def test_non_http_links_are_refused(self):
        self.assertFalse(run(self.root, "file", "ftp://example.com/a.ttf")["ok"])
        self.assertFalse(run(self.root, "file", "")["ok"])

    def test_google_name_is_validated_before_any_request(self):
        r = run(self.root, "google", "../../etc")
        self.assertFalse(r["ok"])
        self.assertIn("family name", r["error"])


if __name__ == "__main__":
    unittest.main()

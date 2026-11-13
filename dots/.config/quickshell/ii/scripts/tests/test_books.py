import json
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "books" / "books.py"


class BooksScanTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.home = root / "home"
        self.library = self.home / "Books"
        (self.library / "Arabic").mkdir(parents=True)
        (self.library / "Arabic" / "كتاب.pdf").write_bytes(b"%PDF-1.4\n")
        (self.library / "novel.epub").write_bytes(b"PK")
        (self.library / "notes.txt").write_text("not a book")
        (self.library / ".hidden.pdf").write_bytes(b"%PDF-1.4\n")
        outside = root / "elsewhere"
        outside.mkdir()
        self.outside = outside / "remembered.pdf"
        self.outside.write_bytes(b"%PDF-1.4\n")
        zathura = self.home / ".local/share/zathura"
        zathura.mkdir(parents=True)
        db = sqlite3.connect(zathura / "bookmarks.sqlite")
        db.execute("CREATE TABLE fileinfo (file TEXT PRIMARY KEY,page INTEGER,offset INTEGER,zoom FLOAT,"
                   "rotation INTEGER,pages_per_row INTEGER,first_page_column TEXT,position_x FLOAT,"
                   "position_y FLOAT,time TIMESTAMP,page_right_to_left INTEGER, hash BLOB)")
        db.execute("INSERT INTO fileinfo (file, page, time) VALUES (?, 41, '2024-04-12 04:20:42')",
                   (str(self.library / "Arabic" / "كتاب.pdf"),))
        db.execute("INSERT INTO fileinfo (file, page, time) VALUES (?, 3, '2024-05-01 10:00:00')",
                   (str(self.outside),))
        db.commit()
        db.close()

    def run_books(self, *args):
        env = dict(os.environ, HOME=str(self.home), XDG_DATA_HOME=str(self.home / ".local/share"),
                   XDG_CACHE_HOME=str(self.home / ".cache"))
        return subprocess.run([sys.executable, "-I", str(SCRIPT), *args], env=env,
                              capture_output=True, text=True, timeout=30)

    def scan(self):
        result = self.run_books("scan", "--dir", str(self.library))
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout)

    def test_finds_books_and_ignores_the_rest(self):
        data = self.scan()
        titles = sorted(book["title"] for book in data["books"])
        self.assertEqual(titles, ["novel", "remembered", "كتاب"])
        self.assertTrue(data["exists"])

    def test_history_gives_page_and_time(self):
        by_title = {book["title"]: book for book in self.scan()["books"]}
        self.assertEqual(by_title["كتاب"]["page"], 41)
        self.assertIsNotNone(by_title["كتاب"]["lastRead"])
        self.assertIsNone(by_title["novel"]["page"])
        self.assertEqual(by_title["كتاب"]["folder"], "Arabic")

    def test_books_the_viewer_remembers_from_elsewhere_are_listed(self):
        by_title = {book["title"]: book for book in self.scan()["books"]}
        self.assertTrue(by_title["remembered"]["known"])
        self.assertEqual(by_title["remembered"]["page"], 3)

    def test_forget_clears_progress_but_keeps_a_library_book(self):
        book = str(self.library / "Arabic" / "كتاب.pdf")
        result = self.run_books("forget", "--path", book)
        self.assertEqual(result.returncode, 0, result.stderr)
        by_title = {b["title"]: b for b in self.scan()["books"]}
        self.assertIsNone(by_title["كتاب"]["page"])
        self.assertTrue(book and (self.library / "Arabic" / "كتاب.pdf").exists())

    def test_forget_hides_a_remembered_book_until_read_again(self):
        self.assertEqual(self.run_books("forget", "--path", str(self.outside)).returncode, 0)
        self.assertNotIn("remembered", [b["title"] for b in self.scan()["books"]])
        db = sqlite3.connect(self.home / ".local/share/zathura/bookmarks.sqlite")
        db.execute("INSERT INTO fileinfo (file, page, time) VALUES (?, 9, '2024-06-01 10:00:00')", (str(self.outside),))
        db.commit()
        db.close()
        self.assertIn("remembered", [b["title"] for b in self.scan()["books"]])

    def test_restore_lists_forgotten_sioyek_books_again(self):
        self.run_books("forget", "--path", str(self.outside))
        self.assertEqual(self.run_books("restore").returncode, 0)
        hidden = self.home / ".cache/ii-books/hidden.json"
        self.assertEqual(json.loads(hidden.read_text()), [])

    def test_missing_library_is_reported_not_fatal(self):
        result = self.run_books("scan", "--dir", str(self.home / "nope"))
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertFalse(data["exists"])

    def test_cbz_cover_comes_from_the_first_image(self):
        archive = self.library / "comic.cbz"
        with zipfile.ZipFile(archive, "w") as z:
            z.writestr("002.png", b"second")
            z.writestr("001.png", b"first")
        result = self.run_books("covers", "--dir", str(self.library))
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        covers = [line["cover"] for line in lines if "cover" in line]
        cbz_covers = [c for c in covers if c.endswith(".png") and Path(c).read_bytes() == b"first"]
        self.assertEqual(len(cbz_covers), 1)
        self.assertTrue(lines[-1].get("done"))


if __name__ == "__main__":
    unittest.main()

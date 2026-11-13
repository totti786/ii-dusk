"""Tests for the Z-Library source adapter (scripts/books/zlib_source.py)."""

import json
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "books"))

import zlib_source  # noqa: E402

STATUS_OK = {"ok": True, "loggedIn": True, "reason": "", "quota": 9,
             "domain": "mirror.example"}
STATUS_OUT = {"ok": True, "loggedIn": False, "reason": "no_tokens", "quota": None,
              "domain": "mirror.example", "message": "no tokens stored"}


def book(book_id="1", book_hash="h", ext="epub", **extra):
    data = {"id": book_id, "hash": book_hash, "title": "Dune",
            "author": "Frank Herbert", "extension": ext, "filesize": 123,
            "cover": "https://covers.example/dune.jpg", "description": "Sand."}
    data.update(extra)
    return data


class FakeCli:
    def __init__(self, responses):
        self.responses = responses
        self.calls = []

    def __call__(self, args, stdin_text=None, timeout=60):
        self.calls.append({"args": list(args), "stdin": stdin_text, "timeout": timeout})
        data = self.responses[args[0]]
        if callable(data):
            data = data(args)
        return 0, data


class ZlibSourceTest(unittest.TestCase):
    def fake(self, responses):
        fake = FakeCli(responses)
        patcher = mock.patch.object(zlib_source, "_run", fake)
        patcher.start()
        self.addCleanup(patcher.stop)
        return fake

    def test_root_logged_in_title_and_quota(self):
        self.fake({"status": STATUS_OK})
        page = zlib_source.browse()
        self.assertEqual(page["title"], "Z-Library · 9 left today")
        self.assertTrue(page["search"])
        self.assertTrue(page["loggedIn"])
        self.assertEqual(page["entries"], [])

    def test_logged_out_page_disables_search(self):
        self.fake({"status": STATUS_OUT})
        page = zlib_source.browse()
        self.assertFalse(page["search"])
        self.assertFalse(page["loggedIn"])
        self.assertEqual(page["title"], "Z-Library · sign in")
        self.assertIn("sign in", page["title"])

    def test_unreachable_mirror_raises(self):
        self.fake({"status": {"ok": True, "loggedIn": False, "reason": "unreachable",
                              "quota": None, "domain": "d", "message": "no route"}})
        with self.assertRaises(zlib_source.SourceError) as caught:
            zlib_source.browse()
        self.assertEqual(caught.exception.code, "mirror")

    def test_search_normalizes_and_filters_formats(self):
        books = [book("1", "h1", "epub"),
                 book("2", "h2", "mobi"),
                 {"id": "3", "title": "No hash", "extension": "pdf"}]
        self.fake({"status": STATUS_OK,
                   "search": {"ok": True, "query": "dune", "page": 1,
                              "limit": 20, "count": 3, "books": books}})
        page = zlib_source.browse("dune")
        self.assertEqual(len(page["entries"]), 1)
        entry = page["entries"][0]
        self.assertEqual(entry["title"], "Dune")
        self.assertEqual(entry["author"], "Frank Herbert")
        self.assertEqual(entry["formats"][0]["ext"], "epub")
        self.assertEqual(entry["formats"][0]["label"], "EPUB")
        self.assertEqual(entry["formats"][0]["size"], 123)
        self.assertEqual(entry["formats"][0]["href"], "zlib://1/h1")
        self.assertEqual(entry["thumb"], "https://covers.example/dune.jpg")
        self.assertEqual(entry["summary"], "Sand.")
        self.assertEqual(page["next"], "")

    def test_next_page_and_page_url(self):
        books = [book(str(n), f"h{n}") for n in range(1, 21)]
        fake = self.fake({"status": STATUS_OK,
                          "search": {"ok": True, "books": books}})
        page = zlib_source.browse("dune")
        self.assertEqual(page["next"], "zlib://search?q=dune&page=2")

        zlib_source.browse(url=page["next"])
        searches = [c for c in fake.calls if c["args"][0] == "search"]
        args = searches[-1]["args"]
        self.assertIn("--page", args)
        self.assertIn("2", args)
        self.assertEqual(args[-1], "dune")
        self.assertIn("--", args)

    def test_download_success(self):
        fake = self.fake({"fetch": {"ok": True, "path": "/tmp/x.epub", "size": 5}})
        out = zlib_source.download("zlib://42/abc", "/tmp", "Dune", "Frank Herbert", "epub")
        self.assertEqual(out, {"done": True, "path": "/tmp/x.epub", "size": 5})
        args = fake.calls[0]["args"]
        self.assertIn("--id=42", args)
        self.assertIn("--hash=abc", args)
        self.assertIn("--dir=/tmp", args)
        self.assertIn("--ext=epub", args)

    def test_download_skipped_is_still_done(self):
        self.fake({"fetch": {"ok": True, "path": "/tmp/x.epub", "size": 5, "skipped": True}})
        out = zlib_source.download("zlib://42/abc", "/tmp", "Dune", "F", "epub")
        self.assertTrue(out["done"])
        self.assertEqual(out["path"], "/tmp/x.epub")

    def test_download_rejects_bad_link(self):
        with self.assertRaises(zlib_source.SourceError) as caught:
            zlib_source.download("https://not-zlib/x", "/tmp", "T", "A", "epub")
        self.assertEqual(caught.exception.code, "bad_link")

    def test_download_maps_auth_and_failure(self):
        self.fake({"fetch": {"ok": False, "error": "auth", "message": "sign in"}})
        with self.assertRaises(zlib_source.SourceError) as caught:
            zlib_source.download("zlib://1/h", "/tmp", "T", "A", "epub")
        self.assertEqual(caught.exception.code, "auth")

        self.fake({"fetch": {"ok": False, "error": "download", "message": "quota"}})
        with self.assertRaises(zlib_source.SourceError) as caught:
            zlib_source.download("zlib://1/h", "/tmp", "T", "A", "epub")
        self.assertEqual(caught.exception.code, "download")

    def test_login_passes_credentials_over_stdin(self):
        fake = self.fake({"login": {"ok": True, "message": "hi"}})
        out = zlib_source.login({"email": "e@x.y", "password": "pw", "domain": ""})
        self.assertTrue(out["ok"])
        call = fake.calls[0]
        self.assertEqual(call["args"], ["login", "--json"])
        self.assertEqual(json.loads(call["stdin"])["password"], "pw")

    def test_settings_read_and_save(self):
        fake = self.fake({"config": {"ok": True, "domain": "mirror.example",
                                     "downloadDir": "/tmp", "hasTokens": True}})
        out = zlib_source.settings()
        self.assertEqual(out["domain"], "mirror.example")
        self.assertEqual(fake.calls[0]["args"], ["config", "--json"])

        zlib_source.settings("new.example")
        self.assertIn("--domain=new.example", fake.calls[1]["args"])

    def test_settings_failure_raises(self):
        self.fake({"config": {"ok": False, "error": "input", "message": "bad domain"}})
        with self.assertRaises(zlib_source.SourceError) as caught:
            zlib_source.settings("bad domain")
        self.assertEqual(caught.exception.code, "settings")

    def test_missing_cli_is_reported(self):
        with mock.patch.object(zlib_source, "PYTHON", Path("/nonexistent/python")), \
                mock.patch.object(zlib_source, "SCRIPT", Path("/nonexistent/zlib.py")):
            with self.assertRaises(zlib_source.SourceError) as caught:
                zlib_source.status()
        self.assertEqual(caught.exception.code, "missing")


if __name__ == "__main__":
    unittest.main()

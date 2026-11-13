"""Tests for the OPDS provider helper, against a throwaway local catalogue."""

import argparse
import base64
import io
import json
import os
import subprocess
import sys
import tempfile
import threading
import unittest
from contextlib import redirect_stdout
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from unittest import mock

SCRIPT = Path(__file__).resolve().parents[1] / "books" / "opds.py"
sys.path.insert(0, str(SCRIPT.parent))
import opds  # noqa: E402 — routing tests import the module directly
EPUB_BYTES = b"PK\x03\x04" + b"x" * 5000
LOG: list[tuple[str, str]] = []  # (path, Authorization)


def feed(body: str, title: str = "Test") -> bytes:
    return (f'<?xml version="1.0"?><feed xmlns="http://www.w3.org/2005/Atom">'
            f"<title>{title}</title>{body}</feed>").encode()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        auth = self.headers.get("Authorization", "")
        LOG.append((self.path, auth))
        host = f"http://127.0.0.1:{self.server.server_port}"
        if self.path.startswith("/secure/") and auth != "Basic " + base64.b64encode(b"reader:hunter2").decode():
            self.send_response(401)
            self.end_headers()
            return
        if self.path in ("/root", "/secure/root"):
            prefix = "/secure" if self.path.startswith("/secure") else ""
            body = feed(
                f'<link rel="search" type="application/atom+xml" href="{host}{prefix}/search?q={{searchTerms}}"/>'
                f'<entry><title>Fiction</title><content type="text">Novels</content>'
                f'<link rel="subsection" type="application/atom+xml;profile=opds-catalog" href="{prefix}/fiction"/></entry>')
        elif self.path.startswith("/search"):
            body = feed(
                f'<entry><title>Dune</title><author><name>Frank Herbert</name></author>'
                f'<summary>Sand.</summary>'
                f'<link rel="http://opds-spec.org/acquisition" type="application/epub+zip" href="/files/dune.epub" length="5004"/>'
                f'<link rel="http://opds-spec.org/acquisition" type="application/x-mobipocket-ebook" href="/files/dune.mobi"/>'
                f'<link rel="http://opds-spec.org/image/thumbnail" type="image/jpeg" href="/cover.jpg"/></entry>'
                f'<link rel="next" type="application/atom+xml" href="/search?page=2"/>')
        elif self.path == "/book":
            edition = ('<entry><title>Same Book</title><author><name>A. Writer</name></author>'
                       '<link rel="http://opds-spec.org/acquisition" type="application/pdf" href="/files/{n}.pdf"/>'
                       '<link rel="http://opds-spec.org/acquisition" type="text/html" href="/files/{n}.html"/></entry>')
            body = feed(edition.format(n=1) + edition.format(n=2))
        elif self.path == "/files/dune.epub" or self.path == "/secure/files/x.epub":
            self.send_response(200)
            self.send_header("Content-Type", "application/epub+zip")
            self.send_header("Content-Length", str(len(EPUB_BYTES)))
            self.end_headers()
            self.wfile.write(EPUB_BYTES)
            return
        elif self.path == "/files/dune.mobi":
            self.send_response(200)
            self.send_header("Content-Type", "application/x-mobipocket-ebook")
            self.end_headers()
            self.wfile.write(b"mobi")
            return
        elif self.path == "/secure/redirect":
            # A login-protected catalogue sending the browser to another host: the password
            # must not follow.
            self.send_response(302)
            self.send_header("Location", f"http://localhost:{self.server.server_port}/files/dune.epub")
            self.end_headers()
            return
        else:
            self.send_response(404)
            self.end_headers()
            return
        self.send_response(200)
        self.send_header("Content-Type", "application/atom+xml")
        self.end_headers()
        self.wfile.write(body)


class OpdsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = HTTPServer(("127.0.0.1", 0), Handler)
        cls.host = f"http://127.0.0.1:{cls.server.server_port}"
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.config = Path(self.tmp.name) / "config"
        LOG.clear()

    def run_opds(self, *args, stdin="", password=None):
        env = dict(os.environ, XDG_CONFIG_HOME=str(self.config))
        if password is not None:
            env["II_BOOKS_PASSWORD"] = password
        return subprocess.run([sys.executable, "-I", str(SCRIPT), *args], env=env, input=stdin,
                              capture_output=True, text=True, timeout=30)

    def json_of(self, result):
        lines = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        return lines[-1] if lines else {}

    def add_source(self, path="/root", user=""):
        args = ["source-add", "--name", "Test Shelf", "--url", self.host + path]
        if user:
            args += ["--user", user]
        # The keyring is not touched when II_BOOKS_PASSWORD is set only for lookups; adding with a
        # user would call secret-tool, so tests that need a user write the file directly.
        return self.json_of(self.run_opds(*args))

    def test_builtin_source_is_listed_and_user_sources_round_trip(self):
        names = [s["name"] for s in self.json_of(self.run_opds("sources"))["sources"]]
        self.assertEqual(names, ["Project Gutenberg", "Z-Library"])
        added = self.add_source()
        self.assertEqual(added["id"], "test-shelf")
        listed = self.json_of(self.run_opds("sources"))["sources"]
        self.assertEqual([s["id"] for s in listed], ["gutenberg", "zlib", "test-shelf"])
        self.assertTrue(self.json_of(self.run_opds("source-remove", "--id", "test-shelf"))["ok"])
        self.assertEqual(len(self.json_of(self.run_opds("sources"))["sources"]), 2)

    def test_builtin_source_cannot_be_removed_and_bad_urls_are_refused(self):
        self.assertFalse(self.json_of(self.run_opds("source-remove", "--id", "gutenberg"))["ok"])
        bad = self.json_of(self.run_opds("source-add", "--name", "x", "--url", "file:///etc/passwd"))
        self.assertEqual(bad["error"], "bad_url")

    def test_browse_lists_navigation_entries(self):
        self.add_source()
        page = self.json_of(self.run_opds("browse", "--id", "test-shelf"))
        self.assertTrue(page["search"])
        self.assertEqual([(e["kind"], e["title"]) for e in page["entries"]], [("nav", "Fiction")])
        self.assertEqual(page["entries"][0]["href"], self.host + "/fiction")

    def test_search_returns_books_with_only_supported_formats(self):
        self.add_source()
        page = self.json_of(self.run_opds("browse", "--id", "test-shelf", "--query", "dune"))
        book = page["entries"][0]
        self.assertEqual((book["kind"], book["title"], book["author"]), ("book", "Dune", "Frank Herbert"))
        self.assertEqual([f["ext"] for f in book["formats"]], ["epub"])
        self.assertEqual(book["thumb"], self.host + "/cover.jpg")
        self.assertEqual(page["next"], self.host + "/search?page=2")

    def test_editions_of_one_book_merge_into_a_detail(self):
        self.add_source()
        page = self.json_of(self.run_opds("browse", "--id", "test-shelf", "--url", self.host + "/book"))
        self.assertEqual(page["detail"]["kind"], "detail")
        self.assertEqual([f["href"] for f in page["detail"]["formats"]],
                         [self.host + "/files/1.pdf", self.host + "/files/2.pdf"])

    def test_download_streams_into_the_folder_and_names_the_file(self):
        self.add_source()
        dest = Path(self.tmp.name) / "lib" / "Downloaded"
        result = self.run_opds("download", "--id", "test-shelf", "--url", self.host + "/files/dune.epub",
                               "--dest", str(dest), "--title", "Dune: Messiah/Part 1", "--author", "Frank Herbert")
        final = self.json_of(result)
        self.assertTrue(final["done"], result.stdout)
        path = Path(final["path"])
        self.assertEqual(path.read_bytes(), EPUB_BYTES)
        self.assertEqual(path.name, "Frank Herbert - Dune Messiah Part 1.epub")
        self.assertEqual(list(dest.glob("*.part")), [])
        # A second download never overwrites the first.
        again = self.json_of(self.run_opds("download", "--id", "test-shelf", "--url", self.host + "/files/dune.epub",
                                           "--dest", str(dest), "--title", "Dune: Messiah/Part 1",
                                           "--author", "Frank Herbert"))
        self.assertNotEqual(again["path"], final["path"])

    def test_download_refuses_formats_the_viewers_cannot_open(self):
        self.add_source()
        dest = Path(self.tmp.name) / "out"
        result = self.json_of(self.run_opds("download", "--id", "test-shelf", "--url", self.host + "/files/dune.mobi",
                                            "--dest", str(dest), "--title", "Dune"))
        self.assertEqual(result["error"], "unsupported")
        self.assertEqual(list(dest.glob("*")), [])

    def write_secure_source(self):
        self.config.joinpath("ii-books").mkdir(parents=True)
        (self.config / "ii-books" / "sources.json").write_text(json.dumps(
            [{"id": "vault", "name": "Vault", "url": self.host + "/secure/root", "user": "reader"}]))

    def test_login_is_sent_to_its_own_server_and_wrong_passwords_are_reported(self):
        self.write_secure_source()
        ok = self.json_of(self.run_opds("browse", "--id", "vault", password="hunter2"))
        self.assertTrue(ok["ok"])
        bad = self.json_of(self.run_opds("browse", "--id", "vault", password="wrong"))
        self.assertEqual(bad["error"], "auth")

    def test_password_does_not_follow_a_redirect_to_another_host(self):
        self.write_secure_source()
        self.run_opds("download", "--id", "vault", "--url", self.host + "/secure/redirect",
                      "--dest", str(Path(self.tmp.name) / "o"), "--title", "x", password="hunter2")
        followed = [auth for path, auth in LOG if path == "/files/dune.epub"]
        self.assertEqual(followed, [""])


if __name__ == "__main__":
    unittest.main()


class ZlibRoutingTest(unittest.TestCase):
    def test_sources_include_the_zlib_builtin(self):
        ids = [source["id"] for source in opds.all_sources()]
        self.assertIn("gutenberg", ids)
        self.assertIn("zlib", ids)
        self.assertEqual(opds.find_source("zlib")["kind"], "zlib")

    def test_browse_routes_to_the_zlib_adapter(self):
        args = argparse.Namespace(id="zlib", url="", query="dune")
        page = {"ok": True, "title": "Z-Library", "entries": [], "detail": None,
                "next": "", "search": True}
        with mock.patch.object(opds.zlib_source, "browse", return_value=page) as browse:
            with redirect_stdout(io.StringIO()) as out:
                opds.cmd_browse(args)
        self.assertTrue(json.loads(out.getvalue())["ok"])
        browse.assert_called_once_with(query="dune", url="")

    def test_download_routes_to_the_zlib_adapter(self):
        args = argparse.Namespace(id="zlib", url="zlib://1/h", dest="/tmp",
                                  title="Dune", author="Frank Herbert", ext="epub")
        result = {"done": True, "path": "/tmp/x.epub", "size": 5}
        with mock.patch.object(opds.zlib_source, "download", return_value=result):
            with redirect_stdout(io.StringIO()) as out:
                opds.cmd_download(args)
        self.assertEqual(json.loads(out.getvalue()), result)

    def test_login_reads_stdin_and_routes_to_the_adapter(self):
        args = argparse.Namespace(id="zlib")
        with mock.patch.object(opds.zlib_source, "login",
                               return_value={"ok": True, "message": "hi"}) as login, \
                mock.patch.object(sys, "stdin", io.StringIO('{"email":"e","password":"p"}')):
            with redirect_stdout(io.StringIO()) as out:
                opds.cmd_login(args)
        self.assertTrue(json.loads(out.getvalue())["ok"])
        login.assert_called_once_with({"email": "e", "password": "p"})

    def test_settings_routes_to_the_adapter(self):
        args = argparse.Namespace(id="zlib", domain="new.example")
        with mock.patch.object(opds.zlib_source, "settings",
                               return_value={"ok": True, "domain": "new.example"}):
            with redirect_stdout(io.StringIO()) as out:
                opds.cmd_settings(args)
        self.assertEqual(json.loads(out.getvalue())["domain"], "new.example")


if __name__ == "__main__":
    unittest.main()

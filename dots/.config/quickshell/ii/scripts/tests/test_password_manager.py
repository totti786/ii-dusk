"""End-to-end tests for scripts/password_manager.py against a fake `bw`.

The fake CLI keeps its vault state in a temp dir and checks the session key it
gets through BW_SESSION, so these cover the real contract: secrets never come
out on stdout, the session never travels in argv, copies go to wl-copy.
"""

import json
import os
import stat
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "password_manager.py"

FAKE_BW = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import json, os, sys
    state_dir = os.environ["FAKE_STATE"]
    log = open(os.path.join(state_dir, "argv.log"), "a")
    log.write(json.dumps(sys.argv[1:]) + "\n")
    unlocked_file = os.path.join(state_dir, "unlocked")
    SESSION = "fake-session-key"
    def unlocked():
        return os.path.exists(unlocked_file) and os.environ.get("BW_SESSION") == SESSION
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    items = [
        {"id": "a1", "type": 1, "name": "GitHub", "favorite": True, "folderId": "f1",
         "login": {"username": "octo", "password": "hunter2", "totp": "JBSWY3DP",
                   "uris": [{"uri": "https://www.github.com/login"}]}},
        {"id": "b2", "type": 1, "name": "Mail", "folderId": None,
         "login": {"username": "me@mail.test", "password": "s3cret", "uris": []}},
        {"id": "n3", "type": 2, "name": "A note", "notes": "private"},
    ]
    if cmd == "status":
        print(json.dumps({"status": "unlocked" if unlocked() else "locked",
                          "userEmail": "me@mail.test", "serverUrl": None}))
    elif cmd == "unlock":
        if os.environ.get("BW_PASSWORD") == "correct horse":
            open(unlocked_file, "w").close(); print(SESSION)
        else:
            print("Invalid master password.", file=sys.stderr); sys.exit(1)
    elif cmd == "lock":
        if os.path.exists(unlocked_file): os.remove(unlocked_file)
        print("Your vault is locked.")
    elif not unlocked():
        print("Vault is locked.", file=sys.stderr); sys.exit(1)
    elif cmd == "list" and sys.argv[2] == "items":
        print(json.dumps(items))
    elif cmd == "list" and sys.argv[2] == "folders":
        print(json.dumps([{"id": "f1", "name": "Dev"}]))
    elif cmd == "get":
        field, item_id = sys.argv[2], sys.argv[3]
        item = next(i for i in items if i["id"] == item_id)
        value = {"password": item["login"]["password"], "username": item["login"]["username"],
                 "totp": "123456"}[field]
        sys.stdout.write(value)
    elif cmd == "sync":
        print("Syncing complete.")
''').lstrip()

FAKE_WL_COPY = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import json, os, sys
    data = sys.stdin.read()
    with open(os.path.join(os.environ["FAKE_STATE"], "clipboard.json"), "w") as f:
        json.dump({"argv": sys.argv[1:], "data": data}, f)
''').lstrip()


FAKE_FPRINTD_VERIFY = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import os, sys
    print("Verify started!")
    print("Verify result: " + os.environ.get("FAKE_FP", "verify-match") + " (done)")
    sys.exit(0 if os.environ.get("FAKE_FP", "verify-match") == "verify-match" else 1)
''').lstrip()

FAKE_FPRINTD_LIST = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import os
    if os.environ.get("FAKE_FP_ENROLLED", "1") == "1":
        print("found 1 devices\nFingerprints for user x on sensor:\n - #0: right-thumb")
    else:
        print("User x has no fingers enrolled for sensor.")
''').lstrip()

# secret-tool keeps one secret in a file; argv is logged so a test can prove the secret never is.
FAKE_SECRET_TOOL = textwrap.dedent(r'''
    #!/usr/bin/env python3
    import json, os, sys
    state = os.environ["FAKE_STATE"]
    store = os.path.join(state, "stash")
    open(os.path.join(state, "secret-argv.log"), "a").write(json.dumps(sys.argv[1:]) + "\n")
    cmd = sys.argv[1]
    if cmd == "store":
        open(store, "w").write(sys.stdin.read())
    elif cmd == "lookup":
        if not os.path.exists(store): sys.exit(1)
        sys.stdout.write(open(store).read())
    elif cmd == "clear":
        if os.path.exists(store): os.remove(store)
''').lstrip()


def write_exec(path: Path, body: str) -> None:
    path.write_text(body)
    path.chmod(path.stat().st_mode | stat.S_IEXEC)


class BitwardenBridgeTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        self.bin = root / "bin"
        self.bin.mkdir()
        self.state = root / "state"
        self.state.mkdir()
        self.runtime = root / "run"
        self.runtime.mkdir(mode=0o700)
        write_exec(self.bin / "bw", FAKE_BW)
        write_exec(self.bin / "wl-copy", FAKE_WL_COPY)
        write_exec(self.bin / "fprintd-verify", FAKE_FPRINTD_VERIFY)
        write_exec(self.bin / "fprintd-list", FAKE_FPRINTD_LIST)
        write_exec(self.bin / "secret-tool", FAKE_SECRET_TOOL)
        # timeout is a real coreutil; keep the system PATH after our fakes.
        self.env = dict(os.environ, PATH=f"{self.bin}:/usr/bin:/bin",
                        FAKE_STATE=str(self.state), XDG_RUNTIME_DIR=str(self.runtime))

    def tearDown(self):
        self.tmp.cleanup()

    def call(self, *args, stdin=None):
        result = subprocess.run([sys.executable, str(SCRIPT), *args, "--provider", "bitwarden"],
                                input=stdin, capture_output=True, text=True, env=self.env,
                                timeout=30)
        self.assertEqual(result.returncode, 0, result.stderr)
        return json.loads(result.stdout), result.stdout

    def unlock(self):
        out, _ = self.call("unlock", stdin="correct horse\n")
        self.assertTrue(out["ok"], out)

    def test_starts_locked(self):
        out, _ = self.call("status")
        self.assertEqual(out["state"], "locked")
        self.assertEqual(out["account"], "me@mail.test")

    def test_wrong_password_is_an_auth_error(self):
        out, _ = self.call("unlock", stdin="nope\n")
        self.assertFalse(out["ok"])
        self.assertEqual(out["code"], "auth")

    def test_unlock_stores_a_private_session(self):
        self.unlock()
        session = self.runtime / "ii-passwords" / "bw-session"
        self.assertEqual(stat.S_IMODE(session.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(session.parent.stat().st_mode), 0o700)
        out, _ = self.call("status")
        self.assertEqual(out["state"], "unlocked")

    def test_session_and_password_never_in_argv(self):
        self.unlock()
        self.call("list")
        log = (self.state / "argv.log").read_text()
        self.assertNotIn("fake-session-key", log)
        self.assertNotIn("correct horse", log)
        self.assertNotIn("--session", log)

    def test_list_has_no_secrets(self):
        self.unlock()
        out, raw = self.call("list")
        self.assertEqual([i["name"] for i in out["items"]], ["GitHub", "Mail"])
        github = out["items"][0]
        self.assertEqual(github["host"], "github.com")
        self.assertEqual(github["folder"], "Dev")
        self.assertTrue(github["totp"])
        self.assertFalse(out["items"][1]["totp"])
        for secret in ("hunter2", "s3cret", "JBSWY3DP", "private"):
            self.assertNotIn(secret, raw)

    def test_copy_goes_to_wl_copy_not_stdout(self):
        self.unlock()
        out, raw = self.call("copy", "--id", "a1", "--field", "password", "--clear", "30")
        self.assertTrue(out["ok"], out)
        self.assertNotIn("hunter2", raw)
        clip = self.wait_clipboard()
        self.assertEqual(clip["data"], "hunter2")
        self.assertIn("--sensitive", clip["argv"])
        self.assertIn("--foreground", clip["argv"])

    def test_copy_totp(self):
        self.unlock()
        self.call("copy", "--id", "a1", "--field", "totp")
        self.assertEqual(self.wait_clipboard()["data"], "123456")

    def test_stale_session_is_dropped(self):
        self.unlock()
        (self.state / "unlocked").unlink()  # locked behind our back
        out, _ = self.call("status")
        self.assertEqual(out["state"], "locked")
        self.assertFalse((self.runtime / "ii-passwords" / "bw-session").exists())

    def test_lock_removes_session(self):
        self.unlock()
        out, _ = self.call("lock")
        self.assertEqual(out["state"], "locked")
        self.assertFalse((self.runtime / "ii-passwords" / "bw-session").exists())
        out, _ = self.call("list")
        self.assertFalse(out["ok"])
        self.assertEqual(out["code"], "locked")

    def test_missing_cli_reports_missing_state(self):
        # A fake HOME too: the helper also looks in ~/.nvm, ~/.cargo/bin…
        env = dict(self.env, PATH="/nonexistent", HOME=self.tmp.name, NVM_DIR=self.tmp.name)
        result = subprocess.run([sys.executable, str(SCRIPT), "status"], capture_output=True,
                                text=True, env=env, timeout=30)
        self.assertEqual(json.loads(result.stdout)["state"], "missing")

    def wait_clipboard(self):
        path = self.state / "clipboard.json"
        for _ in range(100):
            if path.exists() and path.stat().st_size > 0:
                try:
                    return json.loads(path.read_text())
                except json.JSONDecodeError:
                    pass
            subprocess.run(["sleep", "0.05"])
        self.fail("wl-copy was never called")

    # ── Fingerprint ──────────────────────────────────────────────────────────

    def lock(self):
        self.call("lock")

    def test_fingerprint_needs_a_remembered_password_first(self):
        out, _ = self.call("fingerprint")
        self.assertFalse(out["ok"])
        self.assertEqual(out["code"], "fp_stash")

    def test_unlock_without_remember_keeps_nothing(self):
        self.unlock()
        self.assertFalse((self.state / "stash").exists())
        out, _ = self.call("fp-status")
        self.assertFalse(out["stashed"])

    def test_remember_then_fingerprint_unlocks_after_a_lock(self):
        out, _ = self.call("unlock", "--remember", stdin="correct horse\n")
        self.assertTrue(out["ok"], out)
        self.assertEqual((self.state / "stash").read_text(), "correct horse")
        self.lock()
        status, _ = self.call("status")
        self.assertEqual(status["state"], "locked")
        out, _ = self.call("fingerprint")
        self.assertTrue(out["ok"], out)
        status, _ = self.call("status")
        self.assertEqual(status["state"], "unlocked")

    def test_the_master_password_never_goes_through_argv(self):
        self.call("unlock", "--remember", stdin="correct horse\n")
        for log in ("secret-argv.log", "argv.log"):
            self.assertNotIn("correct horse", (self.state / log).read_text())

    def test_no_match_does_not_unlock(self):
        self.call("unlock", "--remember", stdin="correct horse\n")
        self.lock()
        self.env["FAKE_FP"] = "verify-no-match"
        out, _ = self.call("fingerprint")
        self.assertFalse(out["ok"])
        self.assertEqual(out["code"], "fp_nomatch")
        status, _ = self.call("status")
        self.assertEqual(status["state"], "locked")

    def test_no_enrolled_finger_is_reported(self):
        self.call("unlock", "--remember", stdin="correct horse\n")
        self.lock()
        self.env["FAKE_FP_ENROLLED"] = "0"
        out, _ = self.call("fingerprint")
        self.assertEqual(out["code"], "fp_missing")
        status, _ = self.call("fp-status")
        self.assertFalse(status["enrolled"])

    def test_forget_drops_the_password(self):
        self.call("unlock", "--remember", stdin="correct horse\n")
        out, _ = self.call("fp-status")
        self.assertTrue(out["stashed"])
        self.call("fp-forget")
        out, _ = self.call("fp-status")
        self.assertFalse(out["stashed"])
        self.lock()
        out, _ = self.call("fingerprint")
        self.assertEqual(out["code"], "fp_stash")

    def test_a_wrong_password_is_never_remembered(self):
        out, _ = self.call("unlock", "--remember", stdin="nope\n")
        self.assertFalse(out["ok"])
        self.assertFalse((self.state / "stash").exists())


class HelperTests(unittest.TestCase):
    def setUp(self):
        import importlib.util
        spec = importlib.util.spec_from_file_location("password_manager", SCRIPT)
        self.mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.mod)

    def test_host_of(self):
        self.assertEqual(self.mod.host_of("https://www.example.com/a"), "example.com")
        self.assertEqual(self.mod.host_of("example.org"), "example.org")
        self.assertEqual(self.mod.host_of(""), "")

    def test_control_chars_are_refused(self):
        self.assertTrue(self.mod.has_control_chars("a\tb"))
        self.assertFalse(self.mod.has_control_chars("pässwörd!"))


if __name__ == "__main__":
    unittest.main()

"""End-to-end tests for scripts/syncplay/syncplay_bridge.py.

A throwaway syncplay-server on a loopback port and two real bridge sessions
(upstream's client driving a headless mpv: no video, no audio, no window, and no
display variables in the environment, so nothing can open on screen). Never talks
to a public server and never touches the user's syncplay.ini: every session gets
its own HOME.
"""

import json
import os
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

BRIDGE = Path(__file__).resolve().parents[1] / "syncplay" / "syncplay_bridge.py"
HAVE = bool(shutil.which("syncplay-server")) and bool(shutil.which("mpv")) \
    and Path("/usr/lib/syncplay/syncplay").is_dir()


def free_port() -> int:
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class Peer:
    """A shell-side connection to one session's socket."""

    def __init__(self, path: Path):
        self.sock = socket.socket(socket.AF_UNIX)
        self.sock.settimeout(0.3)
        self.sock.connect(str(path))
        self.buf = b""
        self.events: list = []
        self._id = 0
        self.state: dict = {}

    def pump(self, seconds: float = 0.5) -> None:
        end = time.time() + seconds
        while time.time() < end:
            try:
                data = self.sock.recv(1 << 16)
            except socket.timeout:
                continue
            if not data:
                return
            self.buf += data
            while b"\n" in self.buf:
                line, self.buf = self.buf.split(b"\n", 1)
                event = json.loads(line)
                self.events.append(event)
                if event.get("type") == "state":
                    self.state = event
                elif event.get("type") == "tick" and self.state:
                    self.state.update({k: v for k, v in event.items() if k != "type"})

    def send(self, cmd: str, **fields) -> int:
        self._id += 1
        self.sock.sendall((json.dumps(dict(cmd=cmd, id=self._id, **fields)) + "\n").encode())
        return self._id

    def wait(self, predicate, timeout: float = 12.0, step: float = 0.3):
        end = time.time() + timeout
        while time.time() < end:
            self.pump(step)
            if predicate(self.state):
                return True
        return False

    def messages(self, kind: str) -> list:
        return [e for e in self.events if e.get("type") == "msg" and e.get("kind") == kind]

    def close(self) -> None:
        self.sock.close()


class Helpers(unittest.TestCase):
    """A loopback server and throwaway sessions; not collected on its own."""
    password = ""

    @classmethod
    def setUpClass(cls):
        # Short paths: mpv's IPC socket path must stay under the 107-byte limit.
        cls.root = Path(tempfile.mkdtemp(prefix="spt-", dir="/tmp"))
        cls.port = free_port()
        cmd = ["syncplay-server", "--port", str(cls.port), "--isolate-rooms"]
        if cls.password:
            cmd += ["--password", cls.password]
        cls.server = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(1.5)
        cls.media = cls.root / "clip.wav"
        if shutil.which("ffmpeg"):
            subprocess.run(["ffmpeg", "-loglevel", "quiet", "-f", "lavfi", "-i", "sine=d=40",
                            "-ac", "1", str(cls.media)], check=False)
        cls.users: dict = {}

    @classmethod
    def tearDownClass(cls):
        for user in list(cls.users):
            cls.kill_session(user)
        cls.server.kill()
        cls.server.wait()
        shutil.rmtree(cls.root, ignore_errors=True)

    # ── helpers ──────────────────────────────────────────────────────────────
    @classmethod
    def env(cls, user: str) -> dict:
        home = cls.root / user
        for sub in ("run", "tmp", "home"):
            (home / sub).mkdir(parents=True, exist_ok=True)
        (home / "run").chmod(0o700)
        # No display variables: nothing can open a window.
        return {"PATH": os.environ["PATH"], "HOME": str(home / "home"),
                "XDG_CONFIG_HOME": str(home / "home" / ".config"),
                "XDG_RUNTIME_DIR": str(home / "run"), "TMPDIR": str(home / "tmp")}

    @classmethod
    def bridge(cls, user: str, *args: str, stdin: str = "", extra_env: dict | None = None):
        env = cls.env(user)
        env.update(extra_env or {})
        return subprocess.run([sys.executable, str(BRIDGE), *args], input=stdin, text=True,
                              capture_output=True, env=env, timeout=40)

    @classmethod
    def start_session(cls, user: str, room: str = "testroom", password: str = "", extra=()):
        result = cls.bridge(user, "start", "--host", "127.0.0.1", "--port", str(cls.port),
                            "--name", user, "--room", room, "--player-path", shutil.which("mpv"),
                            "--player-arg=--force-window=no", "--player-arg=--vo=null",
                            "--player-arg=--ao=null", *extra, stdin=password + "\n" if password else "")
        out = json.loads(result.stdout.strip().splitlines()[-1])
        cls.users[user] = True
        return out

    @classmethod
    def kill_session(cls, user: str) -> None:
        run = str(cls.root / user / "run")
        for entry in Path("/proc").iterdir():
            if not entry.name.isdigit():
                continue
            try:
                cmdline = (entry / "cmdline").read_bytes().split(b"\0")
                environ = (entry / "environ").read_bytes()
            except OSError:
                continue
            if f"XDG_RUNTIME_DIR={run}".encode() in environ and (
                    b"syncplay_bridge.py" in b" ".join(cmdline) or b"mpv" in cmdline[0]):
                try:
                    os.kill(int(entry.name), signal.SIGKILL)
                except OSError:
                    pass
        cls.users.pop(user, None)

    def peer(self, user: str) -> Peer:
        p = Peer(self.root / user / "run" / "ii-syncplay.sock")
        self.addCleanup(p.close)
        return p

    def pair(self, room: str):
        a, b = f"a{room}", f"b{room}"
        self.assertTrue(self.start_session(a, room)["ok"])
        self.assertTrue(self.start_session(b, room)["ok"])
        self.addCleanup(self.kill_session, a)
        self.addCleanup(self.kill_session, b)
        pa, pb = self.peer(a), self.peer(b)
        both = lambda s: s.get("connected") and len([u for u in s.get("users", []) if u["inRoom"]]) == 2
        self.assertTrue(pa.wait(both), pa.state)
        self.assertTrue(pb.wait(both), pb.state)
        return pa, pb


@unittest.skipUnless(HAVE, "needs syncplay, syncplay-server and mpv")
class SyncplayBridgeTests(Helpers):
    def test_users_see_each_other(self):
        pa, pb = self.pair("users")
        mine = [u for u in pa.state["users"] if u["me"]]
        self.assertEqual(len(mine), 1)
        self.assertEqual(mine[0]["name"], "ausers")
        self.assertEqual(sorted(u["name"] for u in pb.state["users"]), ["ausers", "busers"])
        self.assertEqual(pa.state["room"], "users")

    def test_chat_arrives_as_chat_not_as_a_system_line(self):
        pa, pb = self.pair("chat")
        pb.send("chat", text="hello there")
        pa.pump(2.0)
        chat = pa.messages("chat")
        self.assertEqual([(m["user"], m["text"]) for m in chat], [("bchat", "hello there")])
        self.assertFalse([m for m in pa.messages("system") if "hello there" in m["text"]])

    def test_ready_state_reaches_the_other_user(self):
        pa, pb = self.pair("ready")
        pb.send("ready", value=True)
        self.assertTrue(pa.wait(lambda s: any(u["name"] == "bready" and u["ready"] for u in s["users"])))
        pb.send("ready", value=False)
        self.assertTrue(pa.wait(lambda s: any(u["name"] == "bready" and u["ready"] is False for u in s["users"])))

    @unittest.skipUnless(shutil.which("ffmpeg"), "needs ffmpeg to make a test clip")
    def test_a_loaded_file_is_shared_with_its_duration(self):
        pa, pb = self.pair("file")
        pa.send("open", path=str(self.media))
        self.assertTrue(pb.wait(lambda s: any(u["name"] == "afile" and u["file"] for u in s["users"])), pb.state)
        theirs = [u for u in pb.state["users"] if u["name"] == "afile"][0]
        self.assertEqual(theirs["file"]["name"], "clip.wav")
        self.assertAlmostEqual(theirs["file"]["duration"], 40, delta=1)
        self.assertFalse(theirs["sameFile"])  # B has no file yet

    @unittest.skipUnless(shutil.which("ffmpeg"), "needs ffmpeg to make a test clip")
    def test_pause_and_seek_follow_the_room(self):
        pa, pb = self.pair("sync")
        pa.send("open", path=str(self.media))
        pb.send("open", path=str(self.media))
        both = lambda s: s.get("file") is not None
        self.assertTrue(pa.wait(both) and pb.wait(both))
        pa.send("pause", value=True)
        self.assertTrue(pb.wait(lambda s: s.get("globalPaused") is True), pb.state)
        pa.send("seek", position=20)
        self.assertTrue(pb.wait(lambda s: abs(s.get("globalPosition", 0) - 20) < 3), pb.state)

    def test_shared_playlist_add_and_remove(self):
        pa, pb = self.pair("list")
        pa.send("playlist-add", item="one.mkv")
        pa.send("playlist-add", item="two.mkv")
        self.assertTrue(pb.wait(lambda s: s["playlist"]["items"] == ["one.mkv", "two.mkv"]), pb.state)
        pb.send("playlist-remove", index=0)
        self.assertTrue(pa.wait(lambda s: s["playlist"]["items"] == ["two.mkv"]), pa.state)
        pa.send("playlist-set", items=["two.mkv", "three.mkv"])
        self.assertTrue(pb.wait(lambda s: s["playlist"]["items"] == ["two.mkv", "three.mkv"]), pb.state)

    def test_a_session_from_the_window_has_no_owner_and_names_missing_files(self):
        pa, _pb = self.pair("miss")
        self.assertEqual(pa.state.get("owner"), "")
        pa.send("playlist-add", item="clip.wav")
        pa.send("playlist-add", item="not-on-this-machine.mkv")
        ok = pa.wait(lambda s: len(s.get("playlist", {}).get("items", [])) == 2)
        self.assertTrue(ok, pa.state)
        missing = pa.state["playlist"]["missing"]
        self.assertIn(1, missing)

    def test_links_added_with_trust_play_and_the_room_advances_to_the_next(self):
        """What Mediator relies on: stream links in the shared playlist, host vouched for."""
        second = self.root / "clip2.wav"
        shutil.copy(self.media, second)
        hport = free_port()
        http = subprocess.Popen([sys.executable, "-m", "http.server", str(hport), "--bind", "127.0.0.1",
                                 "--directory", str(self.root)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (http.kill(), http.wait()))
        time.sleep(1.0)
        first_url, second_url = (f"http://127.0.0.1:{hport}/clip.wav", f"http://127.0.0.1:{hport}/clip2.wav")
        env = self.env("trustA")
        # Nothing trusted in either user's settings: the host has to be vouched for per item.
        for user in ("trustA", "trustB"):
            cfg = Path(self.env(user)["XDG_CONFIG_HOME"])
            cfg.mkdir(parents=True, exist_ok=True)
            (cfg / "syncplay.ini").write_text("[client_settings]\nonlyswitchtotrusteddomains = True\ntrusteddomains = []\n")
        proc = subprocess.Popen(
            [sys.executable, str(BRIDGE), "compat", "--host", f"127.0.0.1:{self.port}", "--name", "trustA",
             "--room", "trustroom", "--player-path", shutil.which("mpv"), first_url, "--",
             "--force-window=no", "--vo=null", "--ao=null"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (proc.kill(), proc.wait(), self.kill_session("trustA")))
        self.assertTrue(self.start_session("trustB", "trustroom")["ok"])
        self.addCleanup(self.kill_session, "trustB")
        sock = self.root / "trustA" / "run" / "ii-syncplay.sock"
        for _ in range(100):
            if sock.exists():
                break
            time.sleep(0.1)
        pa, pb = self.peer("trustA"), self.peer("trustB")
        both = lambda s: s.get("connected") and len([u for u in s.get("users", []) if u["inRoom"]]) == 2
        self.assertTrue(pa.wait(both), pa.state)
        self.assertTrue(pb.wait(both), pb.state)
        pb.send("trust", item=first_url)  # the friend's own side
        pb.send("trust", item=second_url)
        pa.send("playlist-add", item=first_url, trust=True)   # the one playing goes in first
        pa.send("playlist-add", item=second_url, trust=True)
        self.assertTrue(pa.wait(lambda s: s.get("playlist", {}).get("items") == [first_url, second_url]), pa.state)
        self.assertEqual(pa.state["playlist"]["index"], 0, "seeding the playing link must not switch")
        self.assertTrue(pb.wait(lambda s: s.get("playlist", {}).get("index") == 0 and bool(s.get("file"))), pb.state)
        pa.send("ready", value=True)
        pb.send("ready", value=True)
        self.assertTrue(pa.wait(lambda s: s.get("ready") and all(u["ready"] for u in s.get("users", []))), pa.state)
        pa.send("pause", value=False)
        self.assertTrue(pa.wait(lambda s: s.get("paused") is False and s.get("position", 0) > 0.5), pa.state)
        pa.send("seek", position=36.0)  # the file is 40 s: Syncplay advances near the end
        advanced = lambda s: s.get("playlist", {}).get("index") == 1
        if not pa.wait(advanced, timeout=15):
            # Two players ending together can both miss Syncplay's own advance (seen in this
            # test about one run in three). Mediator's feeder nudges the room on when its player
            # sits at the end of a file; this is that nudge.
            pa.send("playlist-play", index=1)
        self.assertTrue(pa.wait(advanced, timeout=15), pa.state)
        self.assertTrue(pb.wait(advanced, timeout=30), pb.state)
        self.assertEqual(pa.state["file"]["name"], second_url)

    def test_changing_room_moves_the_user(self):
        pa, pb = self.pair("move")
        pb.send("room", name="elsewhere")
        # Rooms are isolated: someone who leaves yours is gone from your list, and B now sees only itself.
        self.assertTrue(pa.wait(lambda s: [u["name"] for u in s["users"]] == ["amove"]), pa.state)
        self.assertTrue(pb.wait(lambda s: s["room"] == "elsewhere"), pb.state)

    def test_unknown_and_early_commands_are_refused_not_fatal(self):
        pa, _ = self.pair("bad")
        ident = pa.send("frobnicate")
        pa.pump(1.0)
        ack = [e for e in pa.events if e.get("type") == "ack" and e["id"] == ident][0]
        self.assertFalse(ack["ok"])
        pa.send("room", name="")
        pa.send("seek", position="nope")
        pa.pump(1.0)
        acks = [e for e in pa.events if e.get("type") == "ack"]
        self.assertTrue(all(not a["ok"] for a in acks[1:]))
        self.assertTrue(pa.wait(lambda s: s.get("connected")))  # the session survived

    def test_second_start_is_refused_and_stop_ends_the_session(self):
        pa, _ = self.pair("life")
        again = self.start_session("alife", "life")
        self.assertFalse(again["ok"])
        self.assertEqual(again["code"], "running")
        self.bridge("alife", "stop")
        deadline = time.time() + 6
        sock = self.root / "alife" / "run" / "ii-syncplay.sock"
        while sock.exists() and time.time() < deadline:
            time.sleep(0.2)
        self.assertFalse(sock.exists())

    def test_start_rejects_a_bad_address_and_empty_name(self):
        out = json.loads(self.bridge("x", "start", "--host", "bad host/x", "--name", "n").stdout)
        self.assertEqual(out["code"], "host")
        out = json.loads(self.bridge("x", "start", "--host", "127.0.0.1", "--name", "  ").stdout)
        self.assertEqual(out["code"], "name")

    def test_compat_runs_in_the_foreground_like_syncplay_for_mediator(self):
        """Mediator starts `syncplay <opts> <file> -- <mpv opts>` and owns that process."""
        env = self.env("compat")
        mpv = shutil.which("mpv")
        ipc = self.root / "m.sock"
        proc = subprocess.Popen(
            [sys.executable, str(BRIDGE), "compat", "--host", f"127.0.0.1:{self.port}", "--name", "compat",
             "--room", "compatroom", "--player-path", mpv, str(self.media), "--",
             "--force-window=no", "--vo=null", "--ao=null", f"--input-ipc-server={ipc}"],
            env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.addCleanup(lambda: (proc.kill(), proc.wait(), self.kill_session("compat")))
        sock = self.root / "compat" / "run" / "ii-syncplay.sock"
        for _ in range(100):
            if sock.exists() or proc.poll() is not None:
                break
            time.sleep(0.1)
        self.assertIsNone(proc.poll(), "compat exited early")
        p = self.peer("compat")
        self.assertTrue(p.wait(lambda s: s.get("connected") and s.get("room") == "compatroom"), p.state)
        self.assertTrue(p.wait(lambda s: bool(s.get("file"))), p.state)
        self.assertEqual(p.state.get("owner"), "mediator", "the window must know Mediator owns the list")
        self.assertIsNone(proc.poll(), "stays in the foreground while the room is open")
        self.assertTrue(ipc.exists(), "mpv got Mediator's IPC socket")
        p.send("quit")
        proc.wait(timeout=15)

    def test_compat_without_a_server_or_name_fails_fast(self):
        result = self.bridge("nocfg", "compat")
        self.assertEqual(result.returncode, 2)


@unittest.skipUnless(HAVE, "needs syncplay, syncplay-server and mpv")
class SyncplayPasswordTests(Helpers):
    password = "s3cret-pass"


    def test_right_password_connects_and_never_appears_in_argv(self):
        self.assertTrue(self.start_session("pw_ok", "pw", password=self.password)["ok"])
        self.addCleanup(self.kill_session, "pw_ok")
        p = self.peer("pw_ok")
        self.assertTrue(p.wait(lambda s: s.get("connected")), p.events[-3:])
        run = str(self.root / "pw_ok" / "run").encode()
        checked = 0
        for entry in Path("/proc").iterdir():
            if entry.name.isdigit():
                try:
                    cmdline = (entry / "cmdline").read_bytes()
                    environ = (entry / "environ").read_bytes()
                except OSError:
                    continue
                if b"XDG_RUNTIME_DIR=" + run in environ:  # the session and its mpv only
                    checked += 1
                    self.assertNotIn(self.password.encode(), cmdline)
        self.assertGreaterEqual(checked, 1)

    def test_wrong_password_never_connects(self):
        self.assertTrue(self.start_session("pw_bad", "pw", password="wrong")["ok"])
        self.addCleanup(self.kill_session, "pw_bad")
        p = self.peer("pw_bad")
        p.pump(5.0)
        self.assertFalse(p.state.get("connected"))
        # The error happened before this peer connected: it is replayed, and kept in the state.
        self.assertTrue(p.messages("error"), p.events[-4:])
        self.assertTrue(p.state.get("error"))


class DefaultsTests(unittest.TestCase):
    def run_defaults(self, ini: str | None):
        with tempfile.TemporaryDirectory() as tmp:
            if ini is not None:
                (Path(tmp) / "syncplay.ini").write_text(ini, encoding="utf-8-sig")
            result = subprocess.run([sys.executable, str(BRIDGE), "defaults"], capture_output=True,
                                    text=True, env={"PATH": os.environ["PATH"], "HOME": tmp,
                                                    "XDG_CONFIG_HOME": tmp}, timeout=20)
        return json.loads(result.stdout)

    def test_reads_the_users_own_settings_and_never_a_password(self):
        out = self.run_defaults("[server_data]\nhost = example.test\nport = 8996\npassword = hunter2\n"
                                "[client_settings]\nname = Me\nroom = R1\nroomlist = ['R1', 'R2']\n"
                                "publicservers = ['a.test:1']\nmediasearchdirectories = ['/v']\n")
        self.assertEqual((out["host"], out["port"], out["name"], out["room"]), ("example.test", 8996, "Me", "R1"))
        self.assertEqual(out["rooms"], ["R1", "R2"])
        self.assertEqual(out["publicServers"], ["a.test:1"])
        self.assertEqual(out["mediaDirs"], ["/v"])
        self.assertNotIn("hunter2", json.dumps(out))

    def test_a_missing_or_broken_file_gives_blanks_not_an_error(self):
        for ini in (None, "not an ini at all", "[client_settings]\nroomlist = [unclosed\n"):
            out = self.run_defaults(ini)
            self.assertTrue(out["ok"])
            self.assertEqual(out["rooms"], [])


if __name__ == "__main__":
    unittest.main()

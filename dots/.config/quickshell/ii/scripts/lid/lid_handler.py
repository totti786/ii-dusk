#!/usr/bin/env python3
"""Lid policy daemon for Hyprland on any laptop.

Why a daemon and not `switch:on:Lid Switch` binds + a script:
  * It takes logind's `handle-lid-switch` *block* inhibitor itself, so no root-owned
    HandleLidSwitch=ignore drop-in is needed, and if this process dies the inhibitor goes
    with it and logind's own default (suspend) is back. The lid can never end up unhandled.
  * It reads the lid from logind (LidClosed), not from a Hyprland switch device whose name
    differs between laptops.
  * It re-evaluates on every change (lid, charger, keep-awake, monitors, config reload),
    not once at the moment of closing, so unplugging with the lid closed still suspends.

Policy (closed lid):
  external screen connected  -> disable the internal panel (workspaces move over), never suspend
  keep-awake or another app's lid inhibitor -> blank the panel, stay awake
  on a charger               -> on_ac      (default "blank": panel off, keep running)
  on battery                 -> on_battery (default "suspend")
Open lid: everything is put back.

Config (optional): ~/.config/ii-lid.json
  {"on_ac": "blank|suspend|nothing", "on_battery": "suspend|blank|nothing",
   "ignore_inhibitors": ["powerdevil", ...]}

Testing without closing the lid:
  lid_handler.py --simulate lid=closed ac=0 keep=0 inhibited=0 outputs=eDP-1,HDMI-A-1
  II_LID_FAKE_FILE=/path (a file holding "closed" or "open") replaces logind's lid state.
  II_LID_INTERNAL=PREFIX,PREFIX replaces the internal-panel connector prefixes.

Note: "hyprctl eval" below is Hyprland's own Lua command (the same one the shell uses for
monitor rules). Nothing here calls Python's eval(); monitor names go through lua_str().
"""
from __future__ import annotations

import fcntl
import glob
import json
import os
import signal
import subprocess
import sys
import time

DEFAULT_INTERNAL = ("eDP", "LVDS", "DSI")
DEFAULT_POLICY = {
    "on_ac": "blank",
    "on_battery": "suspend",
    # Power managers that also hold handle-lid-switch must not count as "someone wants the
    # lid ignored": they are the very thing this daemon replaces.
    "ignore_inhibitors": ["powerdevil", "org_kde_powerdevil", "gsd-power", "gnome-settings-daemon",
                          "xfce4-power-manager", "ii-lid", "UPower"],
}
SELF_WHO = "ii-lid"
POLL_SECONDS = 3
RESUME_GRACE = 20


# ── Pure decision logic (unit-tested) ────────────────────────────────────────

def internal_prefixes() -> tuple:
    env = os.environ.get("II_LID_INTERNAL", "")
    return tuple(p for p in env.split(",") if p) or DEFAULT_INTERNAL


def classify(monitors: list) -> list:
    """Monitors (hyprctl monitors all -j) -> [{name, internal, headless, enabled}]."""
    prefixes = internal_prefixes()
    out = []
    for m in monitors:
        name = str(m.get("name", ""))
        # A headless output (the phone as a monitor, a virtual display) has no make, model
        # or description: it is not a screen anyone is looking at, so it must not count as
        # "docked".
        headless = not (m.get("make") or m.get("model") or m.get("description"))
        out.append({
            "name": name,
            "internal": name.startswith(prefixes),
            "headless": headless and not name.startswith(prefixes),
            "enabled": not m.get("disabled", False),
        })
    return out


def decide(lid_closed: bool, on_ac: bool, keep_awake: bool, inhibited: bool, outputs: list, policy: dict) -> dict:
    """What to do right now. action: none | blank | disable | suspend."""
    plan = {"action": "none", "wake_inputs": True}
    if not lid_closed:
        return plan
    internals = [o for o in outputs if o["internal"]]
    externals = [o for o in outputs if not o["internal"] and not o["headless"] and o["enabled"]]
    if not internals:
        # No internal panel to deal with (a desktop, or a laptop whose panel Hyprland does
        # not know): only suspend is meaningful.
        action = "none" if (externals or keep_awake or inhibited or on_ac) else policy["on_battery"]
        action = {"blank": "none", "nothing": "none"}.get(action, action)
    elif externals:
        # Docked: the lid is just a closed lid. Disabling (not just blanking) moves the
        # workspaces to the external screen. Never the last enabled output.
        action = "disable"
    elif keep_awake or inhibited:
        action = "blank"
    else:
        action = policy["on_ac"] if on_ac else policy["on_battery"]
        action = {"nothing": "none"}.get(action, action)
    if action not in ("none", "blank", "disable", "suspend"):
        action = "none"
    plan["action"] = action
    # With the panel off, a key or mouse event would turn it back on (a closed laptop in a
    # bag): not while the lid is closed.
    plan["wake_inputs"] = action not in ("blank", "disable")
    return plan


def load_policy(path: str) -> dict:
    policy = {k: (list(v) if isinstance(v, list) else v) for k, v in DEFAULT_POLICY.items()}
    try:
        with open(path) as f:
            user = json.load(f)
        for k in ("on_ac", "on_battery"):
            if user.get(k) in ("blank", "suspend", "nothing"):
                policy[k] = user[k]
        if isinstance(user.get("ignore_inhibitors"), list):
            policy["ignore_inhibitors"] += [str(x) for x in user["ignore_inhibitors"]]
    except (OSError, ValueError):
        pass
    return policy


# ── System probes ────────────────────────────────────────────────────────────

def on_ac_power(root: str = "/sys/class/power_supply") -> bool:
    """True on a charger, or when there is no battery at all (a desktop)."""
    has_battery = False
    for supply in sorted(glob.glob(os.path.join(root, "*"))):
        def read(name, supply=supply):
            try:
                with open(os.path.join(supply, name)) as f:
                    return f.read().strip()
            except OSError:
                return ""
        kind = read("type")
        if read("scope") == "Device":
            continue  # a wireless mouse, a phone being charged: not this machine's power
        if kind == "Battery":
            has_battery = True
        elif kind in ("Mains", "Wireless") or kind.startswith("USB"):
            if read("online") == "1":
                return True
    return not has_battery


def keep_awake_active(states_path: str) -> bool:
    """The shell's keep-awake toggle (it only blocks idle, so the lid has to read it)."""
    if subprocess.run(["pidof", "qs", "quickshell"], capture_output=True).returncode != 0:
        return False  # a stale file from a shell that is no longer running
    try:
        with open(states_path) as f:
            idle = json.load(f).get("idle", {})
    except (OSError, ValueError):
        return False
    if not idle.get("inhibit"):
        return False
    expires = idle.get("expiresAt", 0) or 0
    return expires == 0 or expires > time.time() * 1000


def hyprctl(*args: str, timeout: float = 4) -> str:
    try:
        r = subprocess.run(["hyprctl", *args], capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def monitors_now() -> list:
    try:
        return json.loads(hyprctl("monitors", "all", "-j") or "[]")
    except ValueError:
        return []


def getoption_bool(option: str):
    first = hyprctl("getoption", option).splitlines()[:1]
    if first and first[0].startswith("bool:"):
        return first[0].split(":", 1)[1].strip() == "true"
    return None


def lua_str(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'") + "'"


# ── The daemon ───────────────────────────────────────────────────────────────

class Handler:
    def __init__(self, policy: dict, log):
        self.policy = policy
        self.log = log
        self.applied = {"action": "none", "wake_inputs": True}
        self.snapshots: dict = {}      # internal outputs this daemon disabled -> their rule
        self.saved_wake: dict = {}     # misc options before they were turned off
        self.suspend_sent = False
        self.resume_until = 0.0
        self.states_path = os.path.expanduser("~/.local/state/quickshell/states.json")

    # -- applying -----------------------------------------------------------
    def _lua(self, lua: str) -> None:
        hyprctl("eval", lua)

    def _dpms(self, action: str, names: list) -> None:
        for name in names:
            hyprctl("dispatch", 'hl.dsp.dpms({ action = "%s", monitor = %s })' % (action, lua_str(name)))

    def _set_wake(self, allow: bool) -> None:
        opts = ("key_press_enables_dpms", "mouse_move_enables_dpms")
        if allow:
            for o, v in self.saved_wake.items():
                self._lua("hl.config({ misc = { %s = %s } })" % (o, "true" if v else "false"))
            self.saved_wake = {}
        else:
            for o in opts:
                if o not in self.saved_wake:
                    cur = getoption_bool("misc:" + o)
                    self.saved_wake[o] = True if cur is None else cur
                self._lua("hl.config({ misc = { %s = false } })" % o)

    def restore(self) -> None:
        for name, rule in list(self.snapshots.items()):
            self._lua("hl.monitor({ output = %s, disabled = false, mode = %s, position = %s, scale = %s, transform = %d })"
                      % (lua_str(name), lua_str(rule["mode"]), lua_str(rule["position"]), rule["scale"], rule["transform"]))
        names = [o["name"] for o in classify(monitors_now()) if o["internal"]]
        self.snapshots = {}
        if names:
            self._dpms("on", names)
        self._set_wake(True)
        self.applied = {"action": "none", "wake_inputs": True}
        self.suspend_sent = False

    def apply(self, plan: dict, outputs: list, monitors: list) -> None:
        action = plan["action"]
        internal_enabled = [o["name"] for o in outputs if o["internal"] and o["enabled"]]
        if action == "blank":
            self._dpms("off", internal_enabled)
        elif action == "disable":
            by_name = {m.get("name"): m for m in monitors}
            for name in internal_enabled:
                m = by_name.get(name, {})
                self.snapshots.setdefault(name, {
                    "mode": "%dx%d@%.3f" % (m.get("width", 0), m.get("height", 0), m.get("refreshRate", 60)),
                    "position": "%dx%d" % (m.get("x", 0), m.get("y", 0)),
                    "scale": m.get("scale", 1),
                    "transform": int(m.get("transform", 0)),
                })
                self._lua("hl.monitor({ output = %s, disabled = true })" % lua_str(name))
        elif action == "suspend":
            if not self.suspend_sent and time.time() >= self.resume_until:
                self.suspend_sent = True
                self.log("suspending (lid closed, no reason to stay awake)")
                self.do_suspend()
        self._set_wake(plan["wake_inputs"])
        self.applied = plan

    # -- evaluating ---------------------------------------------------------
    def do_suspend(self) -> None:
        subprocess.Popen(["systemctl", "suspend"])

    def evaluate(self, lid_closed: bool, inhibited: bool, reapply: bool = False) -> None:
        monitors = monitors_now()
        on_ac = on_ac_power()
        keep = keep_awake_active(self.states_path) if lid_closed else False
        outputs = classify(monitors)
        # A panel this daemon disabled is still "an internal panel" for the decision.
        known = {o["name"] for o in outputs}
        for name in self.snapshots:
            if name not in known:
                outputs.append({"name": name, "internal": True, "headless": False, "enabled": False})
        plan = decide(lid_closed, on_ac, keep, inhibited, outputs, self.policy)
        if plan == self.applied and not reapply:
            return
        if plan["action"] != self.applied["action"] or not lid_closed:
            self.log("lid %s ac=%s keep=%s inhibited=%s -> %s" % (
                "closed" if lid_closed else "open", on_ac, keep, inhibited, plan["action"]))
            self.restore()
        if plan["action"] != "none":
            self.apply(plan, classify(monitors_now()), monitors_now())


def inhibited_by_others(manager, policy: dict) -> bool:
    ignore = {x.lower() for x in policy["ignore_inhibitors"]}
    try:
        items = manager.ListInhibitors()
    except Exception:
        return False
    for what, who, _why, mode, _uid, pid in items:
        if "handle-lid-switch" not in str(what) or str(mode) != "block":
            continue
        if int(pid) == os.getpid() or str(who).lower() in ignore:
            continue
        return True
    return False


def read_lid(manager_props) -> bool:
    fake = os.environ.get("II_LID_FAKE_FILE")
    if fake:
        try:
            with open(fake) as f:
                return f.read().strip() == "closed"
        except OSError:
            return False
    try:
        return bool(manager_props.Get("org.freedesktop.login1.Manager", "LidClosed"))
    except Exception:
        return False


def single_instance():
    lock = os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "ii-lid.lock")
    fd = os.open(lock, os.O_CREAT | os.O_RDWR, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        return None
    return fd


def run_daemon() -> int:
    import dbus
    import dbus.mainloop.glib
    from gi.repository import GLib

    lock = single_instance()
    if lock is None:
        print("ii-lid: already running", file=sys.stderr)
        return 0
    state_dir = os.path.expanduser("~/.local/state/quickshell/user")
    os.makedirs(state_dir, exist_ok=True)
    log_path = os.path.join(state_dir, "lid.log")
    try:
        if os.path.getsize(log_path) > 200_000:
            os.truncate(log_path, 0)
    except OSError:
        pass

    def log(msg: str) -> None:
        line = time.strftime("%F %T ") + msg
        print(line, file=sys.stderr, flush=True)
        try:
            with open(log_path, "a") as f:
                f.write(line + "\n")
        except OSError:
            pass

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SystemBus()
    login = bus.get_object("org.freedesktop.login1", "/org/freedesktop/login1")
    manager = dbus.Interface(login, "org.freedesktop.login1.Manager")
    props = dbus.Interface(login, "org.freedesktop.DBus.Properties")

    # Held for the life of the process. When it dies the fd closes and logind handles the lid
    # itself again.
    inhibit_fd = manager.Inhibit("handle-lid-switch", SELF_WHO, "Lid policy is handled by ii", "block")
    keep_fd = inhibit_fd.take() if hasattr(inhibit_fd, "take") else inhibit_fd

    policy = load_policy(os.path.expanduser("~/.config/ii-lid.json"))
    handler = Handler(policy, log)
    pending = {"id": 0}
    loop = GLib.MainLoop()

    def evaluate(reapply: bool = False) -> None:
        handler.evaluate(read_lid(props), inhibited_by_others(manager, policy), reapply)

    def schedule(reapply: bool = False) -> None:
        # Hyprland emits bursts (a monitor change, then a reload): settle first.
        if pending["id"]:
            GLib.source_remove(pending["id"])

        def fire():
            pending["id"] = 0
            evaluate(reapply)
            return False
        pending["id"] = GLib.timeout_add(400, fire)

    def on_props(_iface, changed, _inv):
        if "LidClosed" in changed:
            schedule()
    bus.add_signal_receiver(on_props, "PropertiesChanged", "org.freedesktop.DBus.Properties",
                            "org.freedesktop.login1", "/org/freedesktop/login1")

    def on_sleep(starting):
        if not starting:
            handler.resume_until = time.time() + RESUME_GRACE
            handler.suspend_sent = False
            schedule(True)
    bus.add_signal_receiver(on_sleep, "PrepareForSleep", "org.freedesktop.login1.Manager",
                            "org.freedesktop.login1", "/org/freedesktop/login1")

    def tick():
        # Charger, keep-awake and hotplug changes have no signal worth trusting: look every
        # few seconds, but only while the lid is closed (nothing to do otherwise).
        lid = read_lid(props)
        if lid or handler.applied["action"] != "none" or os.environ.get("II_LID_FAKE_FILE"):
            handler.evaluate(lid, inhibited_by_others(manager, policy))
        return True
    GLib.timeout_add_seconds(POLL_SECONDS, tick)

    # Hyprland events: a config reload drops everything applied through `hyprctl eval`.
    def hypr_socket_path():
        sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE", "")
        return os.path.join(os.environ.get("XDG_RUNTIME_DIR", "/tmp"), "hypr", sig, ".socket2.sock")

    def connect_events():
        import socket
        path = hypr_socket_path()
        if not os.path.exists(path):
            if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and not os.path.isdir(os.path.dirname(path)):
                log("Hyprland is gone, exiting")
                loop.quit()
                return False
            return True  # try again later
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            s.connect(path)
        except OSError:
            return True
        s.setblocking(False)
        buf = {"data": b""}

        def on_data(_fd, cond):
            if cond & (GLib.IO_HUP | GLib.IO_ERR):
                log("Hyprland event socket closed, exiting")
                loop.quit()
                return False
            try:
                chunk = s.recv(65536)
            except BlockingIOError:
                return True
            if not chunk:
                loop.quit()
                return False
            buf["data"] += chunk
            *lines, buf["data"] = buf["data"].split(b"\n")
            for line in lines:
                ev = line.split(b">>", 1)[0]
                if ev == b"configreloaded":
                    schedule(True)
                elif ev.startswith((b"monitoradded", b"monitorremoved")):
                    schedule()
            return True
        GLib.io_add_watch(s.fileno(), GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_data)
        connect_events.sock = s
        return False
    if connect_events():
        GLib.timeout_add_seconds(5, connect_events)

    def stop(*_):
        log("stopping")
        loop.quit()
    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)

    log("started (inhibitor held, fd %s, internal=%s)" % (keep_fd, ",".join(internal_prefixes())))
    evaluate()
    loop.run()
    handler.restore()
    if isinstance(keep_fd, int):
        os.close(keep_fd)
    return 0


def simulate(args: list) -> int:
    kv = dict(a.split("=", 1) for a in args)
    names = [n for n in kv.get("outputs", "").split(",") if n]
    prefixes = internal_prefixes()
    outputs = []
    for n in names:
        headless = n.startswith("HEADLESS") or n.startswith("II-")
        outputs.append({"name": n, "internal": n.startswith(prefixes), "headless": headless, "enabled": True})
    plan = decide(kv.get("lid", "closed") == "closed", kv.get("ac", "1") == "1", kv.get("keep", "0") == "1",
                  kv.get("inhibited", "0") == "1", outputs, load_policy(os.path.expanduser("~/.config/ii-lid.json")))
    print(json.dumps(plan))
    return 0


def main(argv: list) -> int:
    if argv and argv[0] == "--simulate":
        return simulate(argv[1:])
    return run_daemon()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

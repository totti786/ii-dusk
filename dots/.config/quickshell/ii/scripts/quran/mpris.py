#!/usr/bin/env python3
"""MPRIS server for the Quran reader, named "Quran" (mpv's own plugin is hard-wired to "mpv").

QML feeds it state as JSON lines on stdin and receives the desktop's commands as JSON lines on
stdout. It owns org.mpris.MediaPlayer2.quran and exits when stdin closes.
  in : {"title","artist","album","artUrl","lengthUs","positionUs","playing","rate","volume","active"}
  out: {"cmd": "PlayPause"|"Play"|"Pause"|"Next"|"Previous"|"Stop"|"Seek"|"SetPosition"|"SetVolume", "value": n}
"""
import json
import os
import sys
import time

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib

XML = """
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/><method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/><method name="Previous"/><method name="Pause"/><method name="PlayPause"/>
    <method name="Stop"/><method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition"><arg direction="in" name="TrackId" type="o"/><arg direction="in" name="Position" type="x"/></method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>
"""

PATH = "/org/mpris/MediaPlayer2"
ROOT = "org.mpris.MediaPlayer2"
PLAYER = "org.mpris.MediaPlayer2.Player"

state = {"title": "", "artist": "", "album": "", "artUrl": "", "lengthUs": 0, "positionUs": 0,
         "playing": False, "rate": 1.0, "volume": 1.0, "active": False}
stamp = time.monotonic()
conn = None


def position() -> int:
    if state["playing"]:
        return int(state["positionUs"] + (time.monotonic() - stamp) * 1e6 * state["rate"])
    return int(state["positionUs"])


def metadata() -> GLib.Variant:
    d = {"mpris:trackid": GLib.Variant("o", "/org/quran/track"),
         "mpris:length": GLib.Variant("x", int(state["lengthUs"])),
         "xesam:title": GLib.Variant("s", state["title"]),
         "xesam:artist": GLib.Variant("as", [state["artist"]]),
         "xesam:album": GLib.Variant("s", state["album"])}
    if state["artUrl"]:
        d["mpris:artUrl"] = GLib.Variant("s", state["artUrl"])
    return GLib.Variant("a{sv}", d)


def status() -> str:
    if not state["active"]:
        return "Stopped"
    return "Playing" if state["playing"] else "Paused"


def prop(iface: str, name: str):
    if iface == ROOT:
        return {"CanQuit": GLib.Variant("b", False), "CanRaise": GLib.Variant("b", False),
                "HasTrackList": GLib.Variant("b", False), "Identity": GLib.Variant("s", "Quran"),
                "DesktopEntry": GLib.Variant("s", "quran"),
                "SupportedUriSchemes": GLib.Variant("as", []),
                "SupportedMimeTypes": GLib.Variant("as", [])}.get(name)
    return {"PlaybackStatus": GLib.Variant("s", status()), "LoopStatus": GLib.Variant("s", "None"),
            "Rate": GLib.Variant("d", state["rate"]), "Shuffle": GLib.Variant("b", False),
            "Metadata": metadata(), "Volume": GLib.Variant("d", state["volume"]),
            "Position": GLib.Variant("x", position()), "MinimumRate": GLib.Variant("d", 0.5),
            "MaximumRate": GLib.Variant("d", 2.0), "CanGoNext": GLib.Variant("b", True),
            "CanGoPrevious": GLib.Variant("b", True), "CanPlay": GLib.Variant("b", True),
            "CanPause": GLib.Variant("b", True), "CanSeek": GLib.Variant("b", True),
            "CanControl": GLib.Variant("b", True)}.get(name)


def send(cmd: str, value=None) -> None:
    sys.stdout.write(json.dumps({"cmd": cmd, "value": value}) + "\n")
    sys.stdout.flush()


def on_method(connection, sender, path, iface, method, params, invocation):
    args = params.unpack()
    if iface == PLAYER:
        if method == "Seek":
            send("Seek", args[0])
        elif method == "SetPosition":
            send("SetPosition", args[1])
        elif method in ("Next", "Previous", "Pause", "PlayPause", "Stop", "Play"):
            send(method)
    invocation.return_value(None)


def on_get(connection, sender, path, iface, name):
    return prop(iface, name)


def on_set(connection, sender, path, iface, name, value):
    if iface == PLAYER and name == "Volume":
        send("SetVolume", value.get_double())
    elif iface == PLAYER and name == "Rate":
        send("SetRate", value.get_double())
    return True


def changed(names) -> None:
    if conn is None:
        return
    conn.emit_signal(None, PATH, "org.freedesktop.DBus.Properties", "PropertiesChanged",
                     GLib.Variant("(sa{sv}as)", (PLAYER, {n: prop(PLAYER, n) for n in names}, [])))


buf = b""


def apply(new) -> None:
    global stamp
    before = dict(state)
    state.update(new)
    stamp = time.monotonic()
    names = []
    if before["playing"] != state["playing"] or before["active"] != state["active"]:
        names.append("PlaybackStatus")
    if any(before[k] != state[k] for k in ("title", "artist", "album", "artUrl", "lengthUs")):
        names.append("Metadata")
    if before["rate"] != state["rate"]:
        names.append("Rate")
    if before["volume"] != state["volume"]:
        names.append("Volume")
    if conn is not None and abs(before["positionUs"] - state["positionUs"]) > 2_000_000 and before["playing"] == state["playing"]:
        conn.emit_signal(None, PATH, PLAYER, "Seeked", GLib.Variant("(x)", (int(state["positionUs"]),)))
    if names:
        changed(names)


def on_line(source, condition, loop=None):
    """Drain the pipe with os.read: a buffered readline() leaves further lines unseen until the
    next wake-up, and the state then lags (or never catches up)."""
    global buf
    chunk = os.read(sys.stdin.fileno(), 65536)
    if chunk == b"":
        main.quit()
        return False
    buf += chunk
    *lines, buf = buf.split(b"\n")
    for line in lines:
        try:
            apply(json.loads(line))
        except ValueError:
            pass
    return True


def acquired(connection, name):
    global conn
    conn = connection
    info = Gio.DBusNodeInfo.new_for_xml(XML)
    for iface in info.interfaces:
        connection.register_object(PATH, iface, on_method, on_get, on_set)


main = GLib.MainLoop()
Gio.bus_own_name(Gio.BusType.SESSION, "org.mpris.MediaPlayer2.quran", Gio.BusNameOwnerFlags.REPLACE | Gio.BusNameOwnerFlags.ALLOW_REPLACEMENT,
                 acquired, None, lambda *a: main.quit())
GLib.io_add_watch(sys.stdin.fileno(), GLib.IO_IN | GLib.IO_HUP, on_line)
main.run()

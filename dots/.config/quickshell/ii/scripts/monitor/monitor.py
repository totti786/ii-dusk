#!/usr/bin/env python3
"""monitor: the sampler behind the shell's Monitor app, a btop-like view plus internet latency.

    monitor watch [--interval S]     stream one JSON object per line, for as long as it runs
    monitor signal PID [--sig NAME]  send TERM (default), KILL, STOP or CONT to a process of yours
    monitor config [show|set]        the latency targets (patch for `set` in $MONITOR_CONFIG_PATCH)

It reads /proc and /sys directly, so there is nothing to install, and it only runs while the
window is open. Latency is one ICMP echo a second per target, in threads, sent from an
unprivileged ping socket (net.ipv4.ping_group_range) and from `ping` where that is not allowed.
The full process table is sent only while the window shows it ("procs full" on stdin; "procs top"
goes back to the busiest few). Targets are
the default gateway, 1.1.1.1 and 8.8.8.8 unless ~/.config/monitor/config.json has a "targets"
list of {"name", "host"} (a host of "gateway" means the current default gateway).
All subprocesses are started from argument lists, never through a shell.
"""
import argparse
import fcntl
import glob
import json
import os
import pwd
import re
import select
import signal
import socket
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

CONFIG = Path.home() / ".config" / "monitor" / "config.json"
DEFAULT_TARGETS = [{"name": "Gateway", "host": "gateway"},
                   {"name": "Cloudflare", "host": "1.1.1.1"},
                   {"name": "Google", "host": "8.8.8.8"}]
TICKS = os.sysconf("SC_CLK_TCK")
PAGE = os.sysconf("SC_PAGE_SIZE")
HOST_RE = re.compile(r"^[A-Za-z0-9._:-]{1,253}$")
TOP_PROCS = 12  # what the overview's process list needs
SIGNALS = {"TERM": signal.SIGTERM, "KILL": signal.SIGKILL, "STOP": signal.SIGSTOP, "CONT": signal.SIGCONT,
           "INT": signal.SIGINT, "HUP": signal.SIGHUP}


def read(path, default=""):
    try:
        return Path(path).read_text()
    except OSError:
        return default


def load_targets():
    try:
        got = json.loads(CONFIG.read_text()).get("targets")
        if isinstance(got, list):
            ok = [t for t in got if isinstance(t, dict) and HOST_RE.match(str(t.get("host", "")))]
            if ok:
                return [{"name": str(t.get("name") or t["host"]), "host": t["host"]} for t in ok]
    except (OSError, ValueError):
        pass
    return DEFAULT_TARGETS


def default_gateway():
    try:
        out = subprocess.run(["ip", "-4", "route", "show", "default"], capture_output=True, text=True, timeout=2).stdout
        m = re.search(r"default via (\S+)", out)
        return m.group(1) if m else ""
    except (OSError, subprocess.SubprocessError):
        return ""


# ── latency ─────────────────────────────────────────────────────────────────────────────

class Pinger:
    """Latest round trip per target, measured in the background (None means it was lost)."""

    def __init__(self, targets):
        self.targets = targets
        self.latest = {t["name"]: None for t in targets}
        self.gateway = default_gateway()
        self.stop = False
        for t in targets:
            threading.Thread(target=self.loop, args=(t,), daemon=True).start()
        threading.Thread(target=self.watch_gateway, daemon=True).start()

    def watch_gateway(self):
        while not self.stop:
            time.sleep(10)
            self.gateway = default_gateway()

    def host_of(self, t):
        return self.gateway if t["host"] == "gateway" else t["host"]

    def loop(self, t):
        seq = 0
        while not self.stop:
            started = time.time()
            host = self.host_of(t)
            seq = (seq + 1) & 0xFFFF
            self.latest[t["name"]] = self.echo(host, seq) if host and HOST_RE.match(host) else None
            time.sleep(max(0.0, 1.0 - (time.time() - started)))

    def echo(self, host, seq):
        """Round trip in ms, or None when lost. A ping socket where the kernel allows one,
        so a sample does not cost a process; `ping` otherwise."""
        try:
            family, _, _, _, addr = socket.getaddrinfo(host, None, type=socket.SOCK_DGRAM)[0]
        except (OSError, IndexError):
            return None
        v6 = family == socket.AF_INET6
        try:
            sock = socket.socket(family, socket.SOCK_DGRAM, socket.IPPROTO_ICMPV6 if v6 else socket.IPPROTO_ICMP)
        except OSError:
            return ping_command(host)
        request, reply = (128, 129) if v6 else (8, 0)
        payload = b"ii-monitor"
        # The kernel puts its own identifier in and recomputes the checksum
        header = struct.pack("!BBHHH", request, 0, 0, 0, seq)
        packet = struct.pack("!BBHHH", request, 0, icmp_checksum(header + payload), 0, seq) + payload
        with sock:
            start = time.perf_counter()
            try:
                sock.sendto(packet, addr)
            except OSError:
                return None
            while (left := start + 1.0 - time.perf_counter()) > 0:
                sock.settimeout(left)
                try:
                    data = sock.recv(512)
                except OSError:
                    return None
                if len(data) >= 8:
                    kind, _, _, _, got = struct.unpack("!BBHHH", data[:8])
                    if kind == reply and got == seq:
                        return round((time.perf_counter() - start) * 1000, 2)
        return None


def icmp_checksum(data):
    if len(data) % 2:
        data += b"\0"
    total = sum(struct.unpack(f"!{len(data) // 2}H", data))
    total = (total >> 16) + (total & 0xFFFF)
    total += total >> 16
    return ~total & 0xFFFF


def ping_command(host):
    try:
        out = subprocess.run(["ping", "-n", "-c", "1", "-W", "1", host], capture_output=True,
                             text=True, timeout=3).stdout
        m = re.search(r"time[=<]([\d.]+)\s*ms", out)
        return float(m.group(1)) if m else None
    except (OSError, subprocess.SubprocessError):
        return None


# ── system numbers ──────────────────────────────────────────────────────────────────────

def iface_address(name):
    """The IPv4 address of an interface, or "" when it has none."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as s:
            packed = fcntl.ioctl(s.fileno(), 0x8915, struct.pack("256s", name[:15].encode()))  # SIOCGIFADDR
        return socket.inet_ntoa(packed[20:24])
    except OSError:
        return ""


def battery():
    """The first battery as {percent, status, watts, seconds, plugged}, or None without one.
    `seconds` is the time to empty while discharging and to full while charging."""
    base = Path("/sys/class/power_supply")
    for d in sorted(base.glob("BAT*")):
        def num(name):
            try:
                return int(read(d / name).strip())
            except ValueError:
                return None
        status = read(d / "status").strip()
        # Batteries report either energy and power or charge and current (µWh/µW or µAh/µA)
        if num("energy_now") is not None:
            now, full, rate = num("energy_now"), num("energy_full"), num("power_now")
            watts = (rate or 0) / 1e6
        else:
            now, full, rate = num("charge_now"), num("charge_full"), num("current_now")
            volt = num("voltage_now")
            watts = (rate or 0) * (volt or 0) / 1e12
        seconds = None
        if rate and rate > 0 and now is not None and full:
            if status == "Discharging":
                seconds = round(3600 * now / rate)
            elif status == "Charging":
                seconds = round(3600 * max(0, full - now) / rate)
        plugged = any(read(p).strip() == "1" for p in glob.glob("/sys/class/power_supply/A*/online"))
        return {"percent": num("capacity") or 0, "status": status, "watts": round(watts, 2),
                "seconds": seconds, "plugged": plugged}
    return None


def cpu_freqs(count):
    """Current clock of each logical CPU in MHz, and the highest the processor can reach.
    Both are 0 where the kernel does not expose cpufreq (a virtual machine, say)."""
    freqs = []
    for i in range(count):
        try:
            freqs.append(round(int(read(f"/sys/devices/system/cpu/cpu{i}/cpufreq/scaling_cur_freq").strip()) / 1000))
        except ValueError:
            freqs.append(0)
    try:
        top = round(int(read("/sys/devices/system/cpu/cpu0/cpufreq/cpuinfo_max_freq").strip()) / 1000)
    except ValueError:
        top = 0
    return freqs, top


def cpu_times():
    """[(busy, total)] for the whole CPU first, then each core."""
    rows = []
    for line in read("/proc/stat").splitlines():
        if line.startswith("cpu"):
            f = [int(x) for x in line.split()[1:]]
            idle = f[3] + (f[4] if len(f) > 4 else 0)
            total = sum(f[:8])
            rows.append((total - idle, total))
    return rows


def meminfo():
    d = {}
    for line in read("/proc/meminfo").splitlines():
        k, _, v = line.partition(":")
        d[k] = int(v.split()[0]) * 1024 if v.strip() else 0
    total = d.get("MemTotal", 1)
    avail = d.get("MemAvailable", d.get("MemFree", 0))
    return {"total": total, "used": total - avail, "cached": d.get("Cached", 0) + d.get("SReclaimable", 0),
            "buffers": d.get("Buffers", 0), "free": d.get("MemFree", 0),
            "swap_total": d.get("SwapTotal", 0), "swap_used": d.get("SwapTotal", 0) - d.get("SwapFree", 0)}


_sensors = {"at": -1e9, "files": []}


def sensor_files():
    """(value file, chip, label) for every temperature sensor. Finding them takes globbing
    and a read per label, so the list is kept for half a minute and only the values are read."""
    if time.monotonic() - _sensors["at"] > 30:
        files = []
        for hw in sorted(Path("/sys/class/hwmon").glob("hwmon*")):
            chip = read(hw / "name").strip()
            for f in sorted(hw.glob("temp*_input")):
                label = read(str(f).replace("_input", "_label")).strip() or f.name.split("_")[0]
                files.append((str(f), chip, label))
        _sensors.update(at=time.monotonic(), files=files)
    return _sensors["files"]


def temperatures():
    """Hardware sensors as [{"name", "temp"}], the CPU's first."""
    found = []
    for path, chip, label in sensor_files():
        try:
            v = int(read(path).strip()) / 1000
        except ValueError:
            continue
        found.append({"name": f"{chip} {label}", "temp": round(v, 1), "chip": chip})
    cpu = [t for t in found if t["chip"] in ("coretemp", "k10temp", "zenpower", "cpu_thermal")]
    pkg = next((t for t in cpu if "Package" in t["name"] or "Tctl" in t["name"] or "Tdie" in t["name"]), None)
    return {"cpu": (pkg or (max(cpu, key=lambda t: t["temp"]) if cpu else None) or {}).get("temp", 0),
            "sensors": [{"name": t["name"], "temp": t["temp"]} for t in found][:14]}


def mounts():
    seen, out = set(), []
    for line in read("/proc/mounts").splitlines():
        dev, mp, fs = line.split()[:3]
        if not dev.startswith("/dev/") or fs in ("squashfs", "iso9660") or dev in seen or "/snap/" in mp:
            continue
        seen.add(dev)
        try:
            st = os.statvfs(mp)
        except OSError:
            continue
        total = st.f_blocks * st.f_frsize
        if total > 0:
            out.append({"mount": mp, "dev": dev, "fs": fs, "total": total, "used": total - st.f_bfree * st.f_frsize})
    return out


def diskstats():
    """Bytes read and written per whole disk since boot."""
    total_r = total_w = 0
    for line in read("/proc/diskstats").splitlines():
        f = line.split()
        name = f[2]
        if re.match(r"^(loop|ram|zram|dm-|sr|md)", name) or re.search(r"(p?\d+)$", name) and not re.match(r"^(nvme\d+n\d+|mmcblk\d+)$", name):
            continue
        total_r += int(f[5]) * 512
        total_w += int(f[9]) * 512
    return total_r, total_w


def netstats():
    out = {}
    for line in read("/proc/net/dev").splitlines()[2:]:
        name, _, rest = line.partition(":")
        name = name.strip()
        if name == "lo" or not rest:
            continue
        f = rest.split()
        up = read(f"/sys/class/net/{name}/operstate").strip()
        out[name] = (int(f[0]), int(f[8]), up)
    return out


_users = {}


def user_name(uid):
    if uid not in _users:
        try:
            _users[uid] = pwd.getpwuid(uid).pw_name
        except KeyError:
            _users[uid] = str(uid)
    return _users[uid]


def process_table():
    """pid -> (cpu ticks, name, uid, state, rss bytes, threads, parent)."""
    # Plain strings and os calls: this runs over every process each second
    table = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/stat", "rb") as fh:
                raw = fh.read().decode(errors="replace")
            # comm may hold spaces and parentheses: split on the last ")"
            head, _, tail = raw.rpartition(")")
            name = head[head.index("(") + 1:]
            f = tail.split()
            uid = os.stat(f"/proc/{pid}").st_uid
            table[int(pid)] = (int(f[11]) + int(f[12]), name, uid, f[0], int(f[21]) * PAGE, int(f[17]), int(f[1]))
        except (OSError, ValueError, IndexError):
            continue
    return table


def cmdline(pid):
    try:
        return Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode(errors="replace").strip()[:240]
    except OSError:
        return ""


def hello():
    model = ""
    for line in read("/proc/cpuinfo").splitlines():
        if line.startswith("model name"):
            model = line.split(":", 1)[1].strip()
            break
    return {"event": "hello", "cpu_model": model, "cores": os.cpu_count() or 1, "host": os.uname().nodename,
            "kernel": os.uname().release, "targets": [t["name"] for t in load_targets()]}


def cmd_watch(args):
    out = sys.stdout
    out.write(json.dumps(hello()) + "\n")
    out.flush()
    pinger = Pinger(load_targets())
    prev_cpu, prev_procs = cpu_times(), process_table()
    prev_net, prev_disk = netstats(), diskstats()
    prev_t = time.time()
    disks, disk_at, cmd_cache = [], 0.0, {}
    full = args.procs == "full"
    stdin_open = True
    while True:
        # Wait out the interval, listening for "procs full" / "procs top" from the window
        deadline = time.monotonic() + args.interval
        while (left := deadline - time.monotonic()) > 0:
            if not stdin_open:
                time.sleep(left)
                break
            ready, _, _ = select.select([sys.stdin], [], [], left)
            if not ready:
                break
            line = sys.stdin.readline()
            if not line:
                stdin_open = False
            elif line.strip() in ("procs full", "procs top"):
                full = line.strip() == "procs full"
                if full:
                    break  # the process list is on show now: fill it at once
        now = time.time()
        dt = max(now - prev_t, 0.001)
        cpu = cpu_times()
        pct = [round(100 * (b - pb) / (t - pt), 1) if t > pt else 0.0 for (b, t), (pb, pt) in zip(cpu, prev_cpu)]
        procs = process_table()
        usage_of = {}
        for pid, (ticks, name, *_rest) in procs.items():
            before = prev_procs.get(pid)
            usage_of[pid] = round(100 * (ticks - before[0]) / TICKS / dt, 1) if before and before[1] == name else 0.0
        # The whole table is ~50 kB of JSON a second for the shell to parse; outside the
        # process list only the busiest few are shown
        shown = procs if full else sorted(procs, key=lambda p: usage_of[p], reverse=True)[:TOP_PROCS]
        rows = []
        for pid in shown:
            ticks, name, uid, state, rss, threads, ppid = procs[pid]
            if pid not in cmd_cache:
                cmd_cache[pid] = cmdline(pid) or f"[{name}]"
            rows.append([pid, name, user_name(uid), usage_of[pid], rss, state, threads, cmd_cache[pid], ppid])
        for gone in set(cmd_cache) - set(procs):
            del cmd_cache[gone]
        net = netstats()
        nets = []
        for name, (rx, tx, up) in net.items():
            if name in prev_net:
                nets.append({"name": name, "rx": max(0, (rx - prev_net[name][0]) / dt),
                             "tx": max(0, (tx - prev_net[name][1]) / dt), "up": up, "ip": iface_address(name), "rx_total": rx, "tx_total": tx})
        dr, dw = diskstats()
        if now - disk_at > 15:
            disks, disk_at = mounts(), now
        load = os.getloadavg()
        mem = meminfo()
        freqs, freq_max = cpu_freqs(len(pct) - 1 if pct else 0)
        msg = {"event": "tick", "t": round(now, 2), "cpu": pct[0] if pct else 0, "cores": pct[1:],
               "freq": freqs, "freq_max": freq_max, "battery": battery(),
               "load": [round(x, 2) for x in load], "uptime": float(read("/proc/uptime").split()[0] or 0),
               "mem": mem, "temps": temperatures(), "disks": disks,
               "io": {"read": max(0, (dr - prev_disk[0]) / dt), "write": max(0, (dw - prev_disk[1]) / dt)},
               "net": nets, "procs": rows, "procs_full": full, "tasks": len(procs),
               "threads": sum(p[5] for p in procs.values()),
               "ping": [{"name": t["name"], "host": pinger.host_of(t), "ms": pinger.latest.get(t["name"])}
                        for t in pinger.targets]}
        prev_cpu, prev_procs, prev_net, prev_disk, prev_t = cpu, procs, net, (dr, dw), now
        try:
            out.write(json.dumps(msg, ensure_ascii=False, separators=(",", ":")) + "\n")
            out.flush()
        except (BrokenPipeError, OSError):
            return


def cmd_signal(args):
    sig = SIGNALS.get(args.sig.upper())
    if sig is None:
        print(json.dumps({"ok": False, "error": "signal must be one of " + ", ".join(SIGNALS)}))
        sys.exit(1)
    if args.pid <= 1 or args.pid == os.getpid():
        print(json.dumps({"ok": False, "error": "not a process to signal"}))
        sys.exit(1)
    try:
        os.kill(args.pid, sig)
    except ProcessLookupError:
        print(json.dumps({"ok": False, "error": "that process is already gone"}))
        sys.exit(1)
    except PermissionError:
        print(json.dumps({"ok": False, "error": "it belongs to another user, so it needs root"}))
        sys.exit(1)
    print(json.dumps({"ok": True}))


def cmd_config(args):
    if args.action == "set":
        try:
            patch = json.loads(os.environ.get("MONITOR_CONFIG_PATCH", "{}"))
            targets = patch.get("targets")
            if targets is not None:
                clean = []
                for t in targets[:6]:
                    host = str(t.get("host", "")).strip()
                    if host and not HOST_RE.match(host):
                        raise ValueError(f"not a host name or address: {host}")
                    if host:
                        clean.append({"name": str(t.get("name") or host).strip()[:24], "host": host})
                if not clean:
                    raise ValueError("keep at least one target")
                CONFIG.parent.mkdir(parents=True, exist_ok=True)
                CONFIG.write_text(json.dumps({"targets": clean}, indent=2))
        except (ValueError, OSError, AttributeError) as e:
            print(json.dumps({"ok": False, "error": str(e)}))
            sys.exit(1)
    print(json.dumps({"ok": True, "targets": load_targets(), "gateway": default_gateway(),
                      "path": str(CONFIG), "defaults": DEFAULT_TARGETS}))


def main():
    ap = argparse.ArgumentParser(prog="monitor")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("watch")
    p.add_argument("--interval", type=float, default=1.0)
    p.add_argument("--procs", choices=["full", "top"], default="full")
    p.set_defaults(fn=cmd_watch)
    p = sub.add_parser("signal")
    p.add_argument("pid", type=int)
    p.add_argument("--sig", default="TERM")
    p.set_defaults(fn=cmd_signal)
    p = sub.add_parser("config")
    p.add_argument("action", nargs="?", default="show", choices=["show", "set"])
    p.set_defaults(fn=cmd_config)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""A light feed for the network desktop widget: once a second, the busiest interface's
download and upload rates and the round trip to the monitor's first targets.

    netwatch.py watch [--target HOST ...] [--iface NAME]

Each --target is a host name, an address, or "gateway" for the default route; two are used. Without
any, the first two targets of the Monitor app's own list are pinged. --iface limits the rates to one
interface; without it the busiest one that is up is used.

It borrows the Monitor app's own ping and interface code (scripts/monitor/monitor.py) but none of
its per-second CPU, memory, disk and process work, so a widget that stays on the desktop is cheap.
"""

import json
import re
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "monitor"))
import monitor  # noqa: E402

TARGETS = 2
IFACE_RE = re.compile(r"^[A-Za-z0-9._@:-]{1,32}$")


def chosen_targets(hosts):
    """Targets from the command line, named for what they are; anything that is not a plausible
    host is dropped rather than handed to the pinger."""
    out = []
    for host in hosts:
        if host != "gateway" and not monitor.HOST_RE.match(host):
            continue
        out.append({"name": "Gateway" if host == "gateway" else host, "host": host})
    return out[:TARGETS]


def main(hosts, only=""):
    pinger = monitor.Pinger(chosen_targets(hosts) or monitor.load_targets()[:TARGETS])
    prev, prev_at = monitor.netstats(), time.monotonic()
    try:
        while True:
            time.sleep(1.0)
            now_at = time.monotonic()
            net = monitor.netstats()
            dt = max(0.001, now_at - prev_at)
            best = None
            for name, (rx, tx, up) in net.items():
                if name not in prev or up != "up" or (only and name != only):
                    continue
                rate = (max(0, (rx - prev[name][0]) / dt), max(0, (tx - prev[name][1]) / dt))
                if best is None or sum(rate) > sum(best[1]):
                    best = (name, rate)
            prev, prev_at = net, now_at
            line = {"iface": best[0] if best else "", "rx": best[1][0] if best else 0, "tx": best[1][1] if best else 0,
                    "ping": [{"name": t["name"], "ms": pinger.latest.get(t["name"])} for t in pinger.targets]}
            try:
                print(json.dumps(line), flush=True)
            except BrokenPipeError:
                return
    finally:
        pinger.stop = True


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["watch"]:
        hosts = [args[i + 1] for i, a in enumerate(args) if a == "--target" and i + 1 < len(args)]
        iface = next((args[i + 1] for i, a in enumerate(args) if a == "--iface" and i + 1 < len(args)), "")
        main(hosts, iface if IFACE_RE.match(iface) else "")
    else:
        sys.exit(__doc__)

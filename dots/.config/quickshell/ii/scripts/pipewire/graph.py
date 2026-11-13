#!/usr/bin/env python3
"""The PipeWire graph for the Patchbay app, as one JSON object per line.

    graph.py snapshot            print the graph once
    graph.py watch               print it again, debounced, whenever anything in it changes
    graph.py link OUT_PORT IN_PORT   connect two ports (their PipeWire ids)
    graph.py unlink LINK_ID      remove a link

A graph is {"nodes": [...], "links": [...]}. Each node carries its ports; a port is typed
"audio", "midi" or "video" from the format PipeWire reports for it.
"""

import json
import re
import subprocess
import sys
import threading
import time

NODE, PORT, LINK = "PipeWire:Interface:Node", "PipeWire:Interface:Port", "PipeWire:Interface:Link"


def port_kind(props):
    fmt = (props.get("format.dsp") or "").lower()
    if "midi" in fmt or "midi" in (props.get("port.name") or "").lower():
        return "midi"
    if "video" in fmt or "rgb" in fmt:
        return "video"
    return "audio"


def to_graph(objects):
    nodes, ports_by_node = {}, {}
    for obj in objects.values():
        info = obj.get("info") or {}
        props = info.get("props") or {}
        if obj.get("type") == NODE:
            nodes[obj["id"]] = {
                "id": obj["id"],
                "name": props.get("node.name", ""),
                "title": props.get("node.description") or props.get("node.nick") or props.get("application.name") or props.get("node.name", ""),
                "app": props.get("application.name", ""),
                "mediaClass": props.get("media.class", ""),
                "icon": props.get("application.icon-name") or props.get("device.icon-name") or "",
                "ports": [],
            }
        elif obj.get("type") == PORT:
            node_id = props.get("node.id")
            if node_id is None:
                continue
            ports_by_node.setdefault(node_id, []).append({
                "id": obj["id"],
                "name": props.get("port.alias") or props.get("port.name", ""),
                "short": props.get("port.name", ""),
                "channel": props.get("audio.channel", ""),
                "direction": "out" if info.get("direction") == "output" or props.get("port.direction") == "out" else "in",
                "kind": port_kind(props),
                "physical": props.get("port.physical") in (True, "true"),
                "monitor": props.get("port.monitor") in (True, "true"),
                "order": props.get("port.id", 0),
            })
    for node_id, ports in ports_by_node.items():
        if node_id in nodes:
            klass = nodes[node_id]["mediaClass"]
            # A port with no format of its own is the kind its node says it is
            for port in ports:
                if port["kind"] == "audio" and klass.startswith("Video"):
                    port["kind"] = "video"
                elif port["kind"] == "audio" and klass.startswith("Midi"):
                    port["kind"] = "midi"
            nodes[node_id]["ports"] = sorted(ports, key=lambda p: (p["direction"] != "in", p["monitor"], p["order"] if isinstance(p["order"], int) else 0, p["name"]))
    links = []
    for obj in objects.values():
        if obj.get("type") != LINK:
            continue
        info = obj.get("info") or {}
        props = info.get("props") or {}
        try:
            links.append({
                "id": obj["id"],
                "outNode": props["link.output.node"], "outPort": props["link.output.port"],
                "inNode": props["link.input.node"], "inPort": props["link.input.port"],
                "state": info.get("state", ""),
            })
        except KeyError:
            continue
    return {"nodes": sorted((n for n in nodes.values() if n["ports"]), key=lambda n: n["id"]), "links": links}


def decode_stream(stream):
    """The arrays `pw-dump -m` prints one after another, as they complete."""
    import codecs

    decoder = json.JSONDecoder()
    text = codecs.getincrementaldecoder("utf-8")(errors="replace")
    buffer = ""
    while True:
        # read1 returns what has arrived; read(n) would wait for n bytes
        chunk = stream.read1(65536)
        if not chunk:
            break
        buffer += text.decode(chunk)
        while True:
            buffer = buffer.lstrip()
            if not buffer:
                break
            try:
                value, end = decoder.raw_decode(buffer)
            except json.JSONDecodeError:
                break
            buffer = buffer[end:]
            yield value


def emit(graph):
    sys.stdout.write(json.dumps(graph, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def cmd_snapshot():
    done = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=20)
    objects = {obj["id"]: obj for obj in json.loads(done.stdout)}
    emit(to_graph(objects))


def cmd_watch():
    # pw-dump block-buffers a pipe, which would hold every update back; stdbuf keeps lines flowing
    proc = subprocess.Popen(["stdbuf", "-o0", "pw-dump", "-m"], stdout=subprocess.PIPE)
    objects = {}
    lock = threading.Lock()
    dirty = threading.Event()

    def reader():
        for batch in decode_stream(proc.stdout):
            with lock:
                for obj in batch:
                    if obj.get("info") is None:
                        objects.pop(obj.get("id"), None)
                        continue
                    old = objects.get(obj["id"])
                    if old:
                        # An update carries only what changed; keep the rest
                        obj.setdefault("type", old.get("type"))
                        merged = dict(old.get("info") or {})
                        merged.update(obj["info"])
                        merged["props"] = dict((old.get("info") or {}).get("props") or {}, **(obj["info"].get("props") or {}))
                        obj["info"] = merged
                    objects[obj["id"]] = obj
            dirty.set()
        dirty.set()

    threading.Thread(target=reader, daemon=True).start()
    last = None
    try:
        while proc.poll() is None or dirty.is_set():
            dirty.wait()
            time.sleep(0.12)
            dirty.clear()
            with lock:
                graph = to_graph(dict(objects))
            # Volume moves, node state flips and clock updates arrive as changes too, but
            # leave the nodes, ports and links as they were: the window need not rebuild
            line = json.dumps(graph, separators=(",", ":"))
            if line != last:
                last = line
                sys.stdout.write(line + "\n")
                sys.stdout.flush()
            if proc.poll() is not None:
                break
    finally:
        proc.terminate()


def valid_id(text):
    return re.fullmatch(r"\d{1,10}", text) is not None


def main(argv):
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "snapshot":
        cmd_snapshot()
    elif cmd == "watch":
        cmd_watch()
    elif cmd == "link" and len(argv) == 4 and valid_id(argv[2]) and valid_id(argv[3]):
        return subprocess.run(["pw-link", argv[2], argv[3]]).returncode
    elif cmd == "unlink" and len(argv) == 3 and valid_id(argv[2]):
        return subprocess.run(["pw-link", "-d", argv[2]]).returncode
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

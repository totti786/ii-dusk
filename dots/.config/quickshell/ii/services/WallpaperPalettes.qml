pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

/**
 * The colour scheme each wallpaper would give the desktop, for the deck picker's cards.
 *
 * One long-lived worker (scripts/colors/wallpaper_palettes.py) runs matugen as a dry run
 * with the type and mode switchwall.sh would use, caches the result on disk and answers
 * as it goes. It runs only while something holds it (`acquire` / `release`), and a
 * request moves those wallpapers to the front of its queue, so the cards in view are
 * read first.
 *
 *   palettes[path] = { primary: "#rrggbb", ... }     sizes[path] = { w, h }
 */
Singleton {
    id: root

    property var palettes: ({})
    property var sizes: ({})
    // Paths matugen could not read (videos, broken files).
    property var unreadable: ({})

    property int holders: 0
    function acquire() { root.holders++; }
    function release() { root.holders = Math.max(0, root.holders - 1); }

    // What switchwall.sh would hand matugen: "scheme-intense" is matugen's fidelity scheme, and
    // "auto" is picked from the image there; tonal spot is its usual answer, and what a card shows.
    readonly property string schemeType: {
        const t = String(Config.options?.appearance?.palette?.type ?? "");
        if (t === "scheme-intense") return "scheme-fidelity";
        if (t === "" || t === "auto" || t === "scheme-auto") return "scheme-tonal-spot";
        return t;
    }
    readonly property string schemeMode: Appearance.m3colors.darkmode ? "dark" : "light"
    readonly property string schemeKey: root.schemeType + "|" + root.schemeMode

    // Paths asked for before the worker is up.
    property var _pending: []
    property var _incoming: []

    // Priority: these go to the front of the queue. Everything else is read after, in order.
    function request(paths) {
        if (!paths || paths.length === 0)
            return;
        if (worker.running && worker.stdinEnabled) {
            worker.write(paths.join("\t") + "\n");
        } else {
            root._pending = root._pending.concat(paths);
        }
    }

    function _restart() {
        root.palettes = ({});
        root.sizes = ({});
        root.unreadable = ({});
        if (worker.running) {
            worker.running = false;
            restartTimer.restart();
        }
    }
    onSchemeKeyChanged: root._restart()
    Timer {
        id: restartTimer
        interval: 150
        onTriggered: worker.running = root.holders > 0
    }

    // Results arrive one line at a time; merge them in batches so a burst of cached
    // answers is one change of `palettes`, not hundreds.
    Timer {
        id: flushTimer
        interval: 60
        onTriggered: {
            if (root._incoming.length === 0)
                return;
            const palettes = Object.assign({}, root.palettes);
            const sizes = Object.assign({}, root.sizes);
            const unreadable = Object.assign({}, root.unreadable);
            for (let i = 0; i < root._incoming.length; i++) {
                const r = root._incoming[i];
                if (r.c) {
                    palettes[r.p] = r.c;
                    sizes[r.p] = { "w": r.w || 0, "h": r.h || 0 };
                } else {
                    unreadable[r.p] = true;
                }
            }
            root._incoming = [];
            root.palettes = palettes;
            root.sizes = sizes;
            root.unreadable = unreadable;
        }
    }

    Process {
        id: worker
        running: root.holders > 0
        stdinEnabled: true
        command: ["python3", "-I", `${FileUtils.trimFileProtocol(Directories.scriptPath)}/colors/wallpaper_palettes.py`,
            "--cache", `${FileUtils.trimFileProtocol(Directories.cache)}/wallpaper_palettes.json`,
            "--type", root.schemeType, "--mode", root.schemeMode, "--workers", "2"]
        onStarted: {
            if (root._pending.length > 0) {
                worker.write(root._pending.join("\t") + "\n");
                root._pending = [];
            }
        }
        stdout: SplitParser {
            onRead: line => {
                try {
                    root._incoming.push(JSON.parse(line));
                    if (!flushTimer.running) flushTimer.start();
                } catch (e) {
                    console.log("[WallpaperPalettes] bad line:", line);
                }
            }
        }
        onExited: root._pending = []
    }
}

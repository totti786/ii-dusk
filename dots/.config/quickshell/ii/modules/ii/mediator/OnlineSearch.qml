pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.services

/**
 * What the online sources have for the words typed on the All tab: movies and series from
 * Cinemeta and anime from AniList, shaped like library rows so the grid can show them beside
 * the local titles. It asks only after a short pause in typing, and never touches the Streaming
 * tab's own state.
 */
Item {
    id: root
    visible: false

    property string query: ""
    property bool active: false

    readonly property string needle: root.query.trim()
    readonly property bool wanted: root.active && root.needle.length >= 2
    readonly property bool busy: root.wanted && (debounce.running || stremioProc.running || animeProc.running)
    /// Library-shaped rows, empty unless something was asked and answered
    readonly property var results: root.wanted && root._answered === root.needle ? root._merged() : []

    property string _answered: ""
    property var _stremio: []
    property var _anime: []

    onNeedleChanged: root._restart()
    onWantedChanged: root._restart()

    function _restart(): void {
        if (!root.wanted) {
            debounce.stop();
            stremioProc.running = false;
            animeProc.running = false;
            root._answered = "";
            root._stremio = [];
            root._anime = [];
            return;
        }
        debounce.restart();
    }

    function _merged(): var {
        const out = [];
        const stremio = root._stremio;
        const movies = stremio.filter(c => c.type === "movie").slice(0, 8);
        const series = stremio.filter(c => c.type !== "movie").slice(0, 8);
        for (const c of movies.concat(series)) {
            out.push({
                "id": `online:stremio:${c.type}:${c.id}`,
                "name": String(c.name ?? ""),
                "display": String(c.name ?? ""),
                "poster": String(c.poster ?? ""),
                "rating": Number(c.rating) || 0,
                "lib": c.type === "movie" ? "movies" : "shows",
                "online": true,
                "statusText": [c.type === "movie" ? "Movie" : "Series", c.year].filter(x => x).join(" · "),
                "stremio": c
            });
        }
        for (const a of root._anime.slice(0, 6)) {
            out.push({
                "id": `online:anime:${a.id}`,
                "name": String(a.title ?? ""),
                "display": String(a.title ?? ""),
                "poster": String(a.poster ?? ""),
                "rating": Number(a.rating) || 0,
                "lib": "anime",
                "online": true,
                "statusText": ["Anime", a.year].filter(x => x).join(" · "),
                "anime": a
            });
        }
        return out;
    }

    function _parse(text): var {
        try {
            const r = JSON.parse(text);
            return Array.isArray(r) ? r : [];
        } catch (e) {
            return [];
        }
    }

    function _settle(): void {
        if (!stremioProc.running && !animeProc.running && root.wanted)
            root._answered = root._asked;
    }

    property string _asked: ""

    Timer {
        id: debounce
        interval: 500
        onTriggered: {
            if (!root.wanted)
                return;
            root._asked = root.needle;
            root._stremio = [];
            root._anime = [];
            stremioProc.command = [MediatorService.binary, "stremio", "search", root.needle];
            animeProc.command = [MediatorService.binary, "anime-browse", "search", root.needle];
            stremioProc.running = true;
            animeProc.running = true;
        }
    }

    Process {
        id: stremioProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root._asked === root.needle)
                    root._stremio = root._parse(text);
            }
        }
        onRunningChanged: if (!running) root._settle()
    }

    Process {
        id: animeProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                if (root._asked === root.needle)
                    root._anime = root._parse(text);
            }
        }
        onRunningChanged: if (!running) root._settle()
    }

    onResultsChanged: MediatorService.warmImages(root.results.map(r => r.poster))
}

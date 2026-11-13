pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common
import qs.services

/**
 * YouTube discovery, search and playback.
 *
 * yt-dlp is used only for public metadata. Playback stays detached in mpv, so the
 * shell never embeds a browser, reads browser cookies, or needs an API key.
 */
Singleton {
    id: root

    property string query: ""
    property var results: []
    property var homeResults: []
    property string homeTopic: "Documentaries"
    property string homeSource: "topic"
    property bool searching: false
    property bool homeLoading: false
    property string error: ""
    property string homeError: ""
    property var lastPlayed: null
    /// The app consumes this when an IPC caller asks for a search view.
    property string requestedTab: ""

    // Every process captures the generation at creation time. A late onExited from a
    // canceled process can therefore never update a newer request.
    property int _generation: 0
    property var _activeRunners: []

    readonly property int requestTimeoutMs: 25000
    readonly property var topicOptions: [
        { "id": "Documentaries", "label": Translation.tr("Documentaries"), "symbol": "movie" },
        { "id": "Science and technology", "label": Translation.tr("Science & technology"), "symbol": "science" },
        { "id": "Music", "label": Translation.tr("Music"), "symbol": "music_note" },
        { "id": "Gaming", "label": Translation.tr("Gaming"), "symbol": "sports_esports" },
        { "id": "News", "label": Translation.tr("News"), "symbol": "newspaper" }
    ]

    readonly property string homeSubtitle: root.homeSource === "recommended"
        ? Translation.tr("Anonymous recommendations · not personalized")
        : Translation.tr("Topic discovery · %1 · public results, not personalized").arg(root.homeTopic)

    function formatDuration(seconds): string {
        const total = Math.max(0, Math.floor(Number(seconds) || 0));
        if (total === 0)
            return "";
        const h = Math.floor(total / 3600);
        const m = Math.floor((total % 3600) / 60);
        const s = total % 60;
        if (h > 0)
            return h + ":" + (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s;
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    function formatViews(count): string {
        const value = Number(count) || 0;
        if (value <= 0)
            return "";
        if (value >= 1000000000)
            return (value / 1000000000).toFixed(1).replace(/\.0$/, "") + "B views";
        if (value >= 1000000)
            return (value / 1000000).toFixed(1).replace(/\.0$/, "") + "M views";
        if (value >= 1000)
            return (value / 1000).toFixed(1).replace(/\.0$/, "") + "K views";
        return value + " views";
    }

    function _validVideoId(value): bool {
        return /^[A-Za-z0-9_-]{11}$/.test(String(value ?? ""));
    }

    /** Returns an id only for a complete YouTube video URL or an exact id. */
    function videoIdFromText(text): string {
        const value = String(text ?? "").trim();
        if (root._validVideoId(value))
            return value;

        const host = /^(?:https?:\/\/)?(?:www\.)?(?:youtube\.com|youtu\.be)(?:[/?#]|$)/i;
        if (!host.test(value))
            return "";

        let match = value.match(/youtu\.be\/([A-Za-z0-9_-]{11})(?:[/?#&]|$)/i);
        if (!match)
            match = value.match(/(?:watch\?(?:[^#]*&)?v=|[?&]v=|(?:shorts|embed|live|v)\/)([A-Za-z0-9_-]{11})(?:[/?#&]|$)/i);
        return match && root._validVideoId(match[1]) ? match[1] : "";
    }

    function isExternalUrl(text): bool {
        return /^[a-z][a-z0-9+.-]*:\/\//i.test(String(text ?? "").trim());
    }

    function _isCurrentRequest(token): bool {
        return Number(token) === root._generation;
    }

    function _bestThumbnail(entry): string {
        const list = Array.isArray(entry?.thumbnails) ? entry.thumbnails.slice() : [];
        list.sort((a, b) => Number(a?.width ?? 0) - Number(b?.width ?? 0));
        const hit = list.find(item => Number(item?.width ?? 0) >= 480)
            ?? list[list.length - 1] ?? null;
        const id = root.videoIdFromText(entry?.id ?? entry?.url ?? "");
        return String(hit?.url ?? (id.length > 0 ? "https://i.ytimg.com/vi/" + id + "/mqdefault.jpg" : ""));
    }

    function _parsePlaylist(text): var {
        const raw = String(text ?? "").trim();
        if (raw.length === 0)
            return [];

        try {
            const parsed = JSON.parse(raw);
            return Array.isArray(parsed?.entries) ? parsed.entries : (Array.isArray(parsed) ? parsed : [parsed]);
        } catch (e) {
            // Keep a fixture or a future yt-dlp warning from making an otherwise useful
            // response unusable. --dump-single-json normally emits one object.
            const lines = raw.split("\n").filter(line => line.trim().length > 0);
            for (let i = lines.length - 1; i >= 0; i--) {
                try {
                    const parsed = JSON.parse(lines[i]);
                    return Array.isArray(parsed?.entries) ? parsed.entries : (Array.isArray(parsed) ? parsed : [parsed]);
                } catch (lineError) {
                }
            }
        }
        return [];
    }

    function _mapEntries(text): var {
        const seen = ({});
        const mapped = [];
        for (const entry of root._parsePlaylist(text)) {
            if (!entry)
                continue;
            const id = root.videoIdFromText(entry.id ?? entry.url ?? "");
            if (!root._validVideoId(id) || seen[id])
                continue;
            seen[id] = true;
            mapped.push({
                "id": id,
                "title": String(entry.title ?? entry.fulltitle ?? Translation.tr("Untitled video")),
                "channel": String(entry.channel ?? entry.uploader ?? entry.playlist_uploader ?? ""),
                "duration": Number(entry.duration ?? 0),
                "views": Number(entry.view_count ?? 0),
                "thumbnail": root._bestThumbnail(entry)
            });
        }
        return mapped;
    }

    function _ytDlpPrefix(): var {
        // Ignore per-user config so cookies, aliases, or output templates cannot leak into
        // the JSON contract. No cookie or account flags are ever supplied by this service.
        return ["yt-dlp", "--ignore-config", "--no-cache-dir", "--flat-playlist",
            "--dump-single-json", "--no-warnings", "--ignore-errors", "--playlist-end", "24",
            "--socket-timeout", "8"];
    }

    function _rememberRunner(runner): void {
        const active = root._activeRunners.slice();
        active.push(runner);
        root._activeRunners = active;
    }

    function _forgetRunner(runner): void {
        root._activeRunners = root._activeRunners.filter(item => item !== runner);
    }

    function _cancelActiveRequests(): void {
        const runners = root._activeRunners.slice();
        root._activeRunners = [];
        for (const runner of runners) {
            runner.retired = true;
            runner.handler = null;
            if (runner.running)
                runner.running = false;
            Qt.callLater(() => runner.destroy());
        }
    }

    function _run(command, kind, token, handler, timeoutMs = root.requestTimeoutMs): void {
        const runner = runnerComponent.createObject(root, {
            "command": command,
            "kind": kind,
            "requestToken": token,
            "handler": handler,
            "timeoutMs": timeoutMs
        });
        root._rememberRunner(runner);
        runner.running = true;
    }

    function _beginRequest(): int {
        root._generation++;
        root._cancelActiveRequests();
        root.searching = false;
        root.homeLoading = false;
        return root._generation;
    }

    function _searchFinished(token, stdout, stderr, code, timedOut): void {
        if (!root._isCurrentRequest(token))
            return;
        root.searching = false;
        if (timedOut) {
            root.error = Translation.tr("The YouTube search timed out. Try again.");
            return;
        }
        if (code !== 0) {
            const message = String(stderr ?? "").trim().split("\n").filter(line => line.length > 0).pop() ?? "";
            root.error = message.length > 0 ? message : Translation.tr("The YouTube search failed. Try again.");
            return;
        }
        root.results = root._mapEntries(stdout);
        if (root.results.length === 0)
            root.error = Translation.tr("No videos matched that search.");
    }

    function _homeFinished(token, source, topic, stdout, stderr, code, timedOut): void {
        if (!root._isCurrentRequest(token))
            return;

        const entries = !timedOut && code === 0 ? root._mapEntries(stdout) : [];
        if (entries.length > 0) {
            root.homeResults = entries;
            root.homeSource = source;
            root.homeLoading = false;
            root.homeError = "";
            return;
        }

        // Anonymous recommendations are useful when the endpoint responds, but it can
        // legitimately return an empty playlist. Fall back to a public topic search while
        // keeping the copy honest about what the user is seeing.
        if (source === "recommended") {
            root.homeTopic = root.homeTopic.length > 0 ? root.homeTopic : "Documentaries";
            root.homeSource = "topic";
            root.homeError = "";
            root._runHomeTopic(token, root.homeTopic);
            return;
        }

        root.homeLoading = false;
        const detail = String(stderr ?? "").trim().split("\n").filter(line => line.length > 0).pop() ?? "";
        root.homeError = timedOut
            ? Translation.tr("Discovery timed out. Try again or choose another topic.")
            : detail.length > 0 && code !== 0
                ? detail
                : Translation.tr("No public videos were found for this topic.");
    }

    function _runHomeTopic(token, topic): void {
        root.homeLoading = true;
        root._run(root._ytDlpPrefix().concat(["ytsearch24:" + topic]), "home", token,
            (stdout, stderr, code, timedOut) => root._homeFinished(token, "topic", topic,
                stdout, stderr, code, timedOut));
    }

    function loadHome(topic = root.homeTopic): void {
        const selected = String(topic ?? "").trim() || "Documentaries";
        const token = root._beginRequest();
        root.homeTopic = selected;
        root.homeSource = "topic";
        root.homeResults = [];
        root.homeError = "";
        root._runHomeTopic(token, selected);
    }

    /**
     * Try yt-dlp's anonymous recommendation playlist. It is intentionally not the default
     * because some networks return an empty playlist; the handler falls back to topic Home.
     */
    function loadRecommendedHome(): void {
        const token = root._beginRequest();
        root.homeResults = [];
        root.homeSource = "recommended";
        root.homeError = "";
        root.homeLoading = true;
        root._run(root._ytDlpPrefix().concat([":ytrec"]), "recommended", token,
            (stdout, stderr, code, timedOut) => root._homeFinished(token, "recommended", "",
                stdout, stderr, code, timedOut));
    }

    function retryHome(): void {
        if (root.homeSource === "recommended")
            root.loadRecommendedHome();
        else
            root.loadHome(root.homeTopic);
    }

    function search(text): void {
        const needle = String(text ?? "").trim();
        const token = root._beginRequest();
        root.query = needle;
        root.results = [];
        root.error = "";
        if (needle.length === 0) {
            root.error = Translation.tr("Enter a search term.");
            root.requestedTab = "search";
            return;
        }
        root.searching = true;
        root.requestedTab = "search";
        root._run(root._ytDlpPrefix().concat(["ytsearch24:" + needle]), "search", token,
            (stdout, stderr, code, timedOut) => root._searchFinished(token, stdout, stderr, code, timedOut));
    }

    /** Search or open a pasted video link, whichever the input contains. */
    function submit(text): void {
        const value = String(text ?? "").trim();
        const id = root.videoIdFromText(value);
        if (id.length > 0) {
            root.play({ "id": id, "title": Translation.tr("YouTube video"), "channel": "", "duration": 0, "views": 0, "thumbnail": "" });
            return;
        }
        if (root.isExternalUrl(value) || /(?:youtube\.com|youtu\.be)/i.test(value)) {
            root._cancelForInputError();
            root.error = Translation.tr("Paste a valid YouTube video link or search for a title.");
            root.requestedTab = "search";
            return;
        }
        root.search(value);
    }

    /** Open a link from the field or clipboard; plain search terms are rejected here. */
    function openLink(text): void {
        const value = String(text ?? "").trim();
        const id = root.videoIdFromText(value);
        if (id.length > 0) {
            root.play({ "id": id, "title": Translation.tr("YouTube video"), "channel": "", "duration": 0, "views": 0, "thumbnail": "" });
            return;
        }
        root._cancelForInputError();
        root.error = Translation.tr("Paste a valid YouTube video link first.");
    }

    function _cancelForInputError(): void {
        root._generation++;
        root._cancelActiveRequests();
        root.searching = false;
        root.homeLoading = false;
        root.results = [];
    }

    function play(item): void {
        const id = root.videoIdFromText(item?.id ?? item?.url ?? "");
        if (id.length === 0) {
            root.error = Translation.tr("That video link is not valid.");
            return;
        }
        root.lastPlayed = Object.assign({}, item, { "id": id });
        Quickshell.execDetached(["setsid", "-f", "mpv",
            "--force-media-title=" + String(item.title ?? Translation.tr("YouTube video")),
            "--ytdl-format=bestvideo*+bestaudio/best",
            "https://www.youtube.com/watch?v=" + id]);
    }

    /** Kept as the IPC-facing public API: links play, plain text searches. */
    function playFromText(text): void {
        const value = String(text ?? "").trim();
        if (value.length === 0)
            return;
        const id = root.videoIdFromText(value);
        if (id.length > 0) {
            root.play({ "id": id, "title": Translation.tr("YouTube video"), "channel": "", "duration": 0, "views": 0, "thumbnail": "" });
            return;
        }
        if (root.isExternalUrl(value) || /(?:youtube\.com|youtu\.be)/i.test(value)) {
            root._cancelForInputError();
            root.error = Translation.tr("Paste a valid YouTube video link or search for a title.");
            root.requestedTab = "search";
            return;
        }
        root.search(value);
    }

    function openExternal(item): void {
        const id = root.videoIdFromText(item?.id ?? item?.url ?? "");
        if (id.length === 0)
            return;
        Quickshell.execDetached(["xdg-open", "https://www.youtube.com/watch?v=" + id]);
    }

    function copyLink(item): void {
        const id = root.videoIdFromText(item?.id ?? item?.url ?? "");
        if (id.length === 0)
            return;
        Quickshell.clipboardText = "https://www.youtube.com/watch?v=" + id;
    }

    function cancel(): void {
        root._generation++;
        root._cancelActiveRequests();
        root.searching = false;
        root.homeLoading = false;
    }

    function clear(): void {
        root.cancel();
        root.results = [];
        root.homeResults = [];
        root.error = "";
        root.homeError = "";
        root.query = "";
        root.requestedTab = "";
    }

    Component {
        id: runnerComponent

        Scope {
            id: runner

            property alias command: process.command
            property alias running: process.running
            property var handler: null
            property string kind: ""
            property int requestToken: 0
            property int timeoutMs: 0
            property bool retired: false
            property bool timedOut: false

            Process {
                id: process

                stdout: StdioCollector {
                    id: runnerOut
                    waitForEnd: true
                }

                stderr: StdioCollector {
                    id: runnerErr
                    waitForEnd: true
                }

                onExited: (code, status) => runner.finish(code, false)
            }

            Timer {
                id: timeoutTimer
                interval: Math.max(1, runner.timeoutMs)
                running: !runner.retired && runner.timeoutMs > 0
                onTriggered: runner.finish(-1, true)
            }

            function finish(code, timedOut = false): void {
                if (runner.retired)
                    return;
                runner.retired = true;
                runner.timedOut = timedOut;
                const callback = runner.handler;
                runner.handler = null;
                const stdout = String(runnerOut.text ?? "");
                const stderr = String(runnerErr.text ?? "");
                root._forgetRunner(runner);
                if (timedOut && runner.running)
                    runner.running = false;
                if (callback)
                    callback(stdout, stderr, code, timedOut, runner.requestToken, runner.kind);
                Qt.callLater(() => runner.destroy());
            }
        }
    }
}

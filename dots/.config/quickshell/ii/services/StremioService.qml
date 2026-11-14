pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.services

/**
 * Stremio inside Mediator: catalogs, episodes and addon streams come from the public addon
 * protocol (`mediator stremio ...`) and play in mpv through Stremio's streaming server,
 * which the helper starts headless. The Stremio app is never opened.
 */
Singleton {
    id: root


    // The title page shows its "Stremio" button on this; the helper ships with the shell, so it is always there.
    readonly property bool available: true

    // "home" (catalog / search results) → "title" (details + episodes) → "streams"
    property string view: "home"
    property string kind: "movie"
    property var items: []
    property string heading: ""
    property var title: null
    property var streams: []
    property string pickedLabel: ""

    // Quality filter for the stream list ("all", "2160p", "1080p", "720p") and the rows it yields:
    // the direct stream pinned first when enabled, then torrents (most seeders first).
    property string streamFilter: "all"
    readonly property var streamSettings: MediatorService.settings?.streaming ?? ({ "hls": true, "stremio": true })
    readonly property var qualityOptions: {
        const seen = ({});
        for (const st of root.streams)
            seen[st.quality === "4k" ? "2160p" : (st.quality || "")] = true;
        return ["2160p", "1080p", "720p"].filter(q => seen[q]);
    }
    readonly property var streamRows: {
        const out = [];
        if (root.streamSettings.hls !== false)
            out.push({ "direct": true, "quality": "hls", "infoHash": "", "fileIdx": -1, "url": "",
                       "bingeGroup": "", "filename": "", "title": "", "seeds": 0, "size": "" });
        if (root.streamSettings.stremio !== false) {
            const f = root.streamFilter;
            root.streams.filter(st => f === "all" || (st.quality === "4k" ? "2160p" : st.quality) === f)
                .slice(0, 40).forEach(st => out.push(st));
        }
        return out;
    }
    // Which row to suggest: the direct stream unless torrents are preferred (or direct is off),
    // then the sharpest torrent that has at least 3 seeders
    readonly property int recommendedIndex: {
        const rows = root.streamRows;
        const rank = q => q === "2160p" || q === "4k" ? 3 : q === "1080p" ? 2 : q === "720p" ? 1 : 0;
        let best = -1;
        rows.forEach((r, i) => {
            if (r.direct || r.seeds < 3)
                return;
            if (best < 0 || rank(r.quality) > rank(rows[best].quality))
                best = i;
        });
        const directAt = rows.findIndex(r => r.direct);
        if (directAt >= 0 && !(root.streamSettings.prefer_stremio && best >= 0))
            return directAt;
        return best;
    }
    property string notice: ""
    readonly property bool busy: listProc.running || metaProc.running || streamsProc.running

    property bool starting: false

    onItemsChanged: MediatorService.warmImages(root.items.map(i => i.poster))
    onTitleChanged: MediatorService.warmImages([root.title?.poster, root.title?.background])
    property string pickedEpisodeId: ""
    property var _playPayload: null
    property string _lastQuery: ""

    function _run(proc, args, sub): void {
        proc.running = false;
        proc.command = [MediatorService.binary, sub ?? "stremio"].concat(args);
        proc.running = true;
    }

    // Browsing: sort is popular | top | year; genre holds a genre, or a year while sort is "year"
    property string sort: "popular"
    property string genre: ""
    property bool moreAvailable: false
    readonly property bool loadingMore: moreProc.running
    readonly property bool searching: root._lastQuery !== ""
    // A search returns movies and series together; the Movies/Series chips just filter them
    property var results: []
    /// Which of the results a search shows: "all", "movie" or "series". Separate from `kind`,
    /// which is the catalog being browsed, so leaving a search returns to where you were
    property string searchKind: "all"
    function _searchItems(): var {
        return root.searchKind === "all" ? root.results : root.results.filter(i => i.type === root.searchKind);
    }
    function setKind(kind): void {
        root.searchKind = kind;
        root.items = root._searchItems();
        root.notice = root.items.length === 0 ? Translation.tr("Nothing found.") : "";
    }

    readonly property var movieGenres: ["Action", "Adventure", "Animation", "Biography", "Comedy", "Crime",
        "Documentary", "Drama", "Family", "Fantasy", "History", "Horror", "Mystery", "Romance", "Sci-Fi",
        "Sport", "Thriller", "War", "Western"]
    readonly property var seriesGenres: root.movieGenres.concat(["Reality-TV", "Talk-Show", "Game-Show"])
    readonly property var genres: root.kind === "series" ? root.seriesGenres : root.movieGenres
    readonly property var years: {
        const out = [];
        for (let y = new Date().getFullYear(); y >= 1980; y--)
            out.push(String(y));
        return out;
    }

    function _heading(): string {
        const what = root.kind === "series" ? Translation.tr("series") : Translation.tr("movies");
        if (root.sort === "year")
            return root.genre !== "" ? Translation.tr("%1 from %2").arg(what).arg(root.genre)
                : Translation.tr("%1 by year").arg(what);
        const base = root.sort === "top" ? Translation.tr("Top rated %1").arg(what) : Translation.tr("Popular %1").arg(what);
        return root.genre !== "" ? base + " · " + root.genre : base;
    }

    function browse(kind, sort, filter): void {
        root.kind = kind;
        root.sort = sort;
        root.genre = filter;
        root.view = "home";
        root.heading = root._heading();
        root._lastQuery = "";
        root.notice = "";
        root.moreAvailable = false;
        root.items = [];
        moreProc.running = false;
        root._run(listProc, ["browse", kind, sort, filter, "0"]);
    }

    /// Leave a search: back to the catalog of the kind that was being looked at
    function clearSearch(): void {
        if (!root.searching)
            return;
        root.results = [];
        root.browse(root.kind, "popular", "");
    }

    function top(kind): void {
        root.browse(kind, "popular", "");
    }

    // The next page, appended below what is shown
    function more(): void {
        if (!root.moreAvailable || root.searching || moreProc.running || listProc.running)
            return;
        root._run(moreProc, ["browse", root.kind, root.sort, root.genre, String(root.items.length)]);
    }

    function search(query): void {
        const text = String(query ?? "").trim();
        if (text.length === 0)
            return;
        root.view = "home";
        root.heading = Translation.tr("Results for “%1”").arg(text);
        root._lastQuery = text;
        root.searchKind = "all";
        root.results = [];
        root.notice = "";
        root.moreAvailable = false;
        root.items = [];
        root._run(listProc, ["search", text]);
    }

    function openTitle(card): void {
        root.title = card;
        root.view = "title";
        root.notice = "";
        root._run(metaProc, ["meta", String(card.type), String(card.id)]);
    }

    function back(): void {
        root.notice = "";
        root.view = root.view === "streams" ? "title" : "home";
    }

    // videoId is "tt…" for a movie or "tt…:season:episode" for an episode
    function loadStreams(videoId, label): void {
        root.pickedLabel = label;
        root.pickedEpisodeId = String(videoId);
        root.streams = [];
        root.streamFilter = "all";
        root.view = "streams";
        root.notice = "";
        root._run(streamsProc, ["streams", String(root.title.type), String(videoId)]);
    }

    // Streams already played, newest first: the "continue watching" row and resume.
    readonly property var allHistory: (Array.isArray(MediatorService.streamHistory)
        ? MediatorService.streamHistory : []).filter(h => String(h?.show_id ?? "").startsWith("stremio:"))
        .slice().sort((x, y) => Number(y?.updated_at ?? 0) - Number(x?.updated_at ?? 0))
    // One entry per show: its latest episode
    readonly property var history: MediatorService.streamShows(root.allHistory)

    function episodeState(card, episodeId): var {
        const id = root.showId(card);
        return root.allHistory.find(h => h.show_id === id && h.episode_id === episodeId) ?? null;
    }

    function showId(card): string {
        return "stremio:" + (card.type === "series" ? "series" : "movie") + ":" + card.id;
    }

    function historyFor(card): var {
        const id = root.showId(card);
        return root.history.find(h => h.show_id === id) ?? null;
    }

    function loadHistory(): void {
        MediatorService.loadStreamHistory();
    }

    // What resuming an entry plays: the same episode, or the next one once it was finished.
    function resumeTarget(entry): var {
        if (!entry)
            return null;
        if (!entry.watched)
            return { "id": entry.episode_id, "number": entry.episode_number };
        const eps = entry.episodes ?? [];
        const i = eps.findIndex(e => e.id === entry.episode_id);
        return i >= 0 && i + 1 < eps.length ? eps[i + 1] : null;
    }

    function resume(entry): void {
        if (root.starting)
            return;
        const target = root.resumeTarget(entry);
        if (!target) {
            root.notice = Translation.tr("That was the last episode.");
            return;
        }
        root.starting = true;
        startGuard.restart();
        root._start(entry.show_id, String(target.id), String(entry.title), String(entry.poster ?? ""));
    }

    // Plain "Play": mediator picks the source from the settings (direct stream first, or
    // torrents when higher quality is preferred; a stream chosen by hand for it still wins).
    function playEpisode(videoId): void {
        if (root.starting || !root.title)
            return;
        root.starting = true;
        startGuard.restart();
        root._start(root.showId(root.title), String(videoId), String(root.title.name), String(root.title.poster ?? ""));
    }

    function _start(show, episode, name, poster): void {
        root.notice = Translation.tr("Starting %1…").arg(name);
        MediatorService.playProviderEpisode(show, episode, name, false, "best", poster, true);
    }

    // Remember the picked stream for this episode, then hand off to mediator's native
    // player so the position, the pill and resume all work.
    function play(stream): void {
        if (root.starting || !root.title)
            return;
        root.starting = true;
        startGuard.restart();
        const card = root.title;
        const show = root.showId(card);
        const episode = root.pickedEpisodeId !== "" ? root.pickedEpisodeId : String(card.id);
        root._playPayload = { "show": show, "episode": episode, "name": String(card.name),
            "poster": String(card.poster ?? "") };
        // The direct row carries no hash: clearing a hand-picked torrent lets mediator resolve
        // the direct stream first, with torrents only as its fallback.
        if (stream.direct) {
            root._run(chooseProc, ["choose", JSON.stringify({ "showId": show, "episodeId": episode, "clear": true })]);
            return;
        }
        root._run(chooseProc, ["choose", JSON.stringify({
            "showId": show, "episodeId": episode, "infoHash": stream.infoHash,
            "fileIdx": stream.fileIdx, "url": stream.url, "quality": stream.quality,
            "bingeGroup": stream.bingeGroup, "filename": stream.filename
        })]);
    }

    // Ignore repeat clicks while a player is starting
    Timer {
        id: startGuard
        interval: 6000
        onTriggered: root.starting = false
    }

    // ── Downloads (qBittorrent) ────────────────────────────────────────────
    property var downloads: ({})          // "<show>|<episode>" → { progress, state, speed }

    function downloadKey(card, episodeId): string {
        return root.showId(card) + "|" + episodeId;
    }

    function downloadState(card, episodeId): var {
        return card ? (root.downloads[root.downloadKey(card, episodeId)] ?? null) : null;
    }

    function refreshDownloads(): void {
        if (!statusProc.running) {
            statusProc.command = [MediatorService.binary, "download", "status"];
            statusProc.running = true;
        }
    }

    function _downloadArgs(card, videoId): var {
        const parts = String(videoId).split(":");
        const series = card.type === "series";
        return {
            "type": series ? "series" : "movie", "title": String(card.name), "year": String(card.year ?? ""),
            "season": series ? Number(parts[1] ?? 0) : 0, "showId": root.showId(card),
            "episodeId": String(videoId), "videoId": String(videoId)
        };
    }

    // The best healthy stream for this movie or episode, no picking
    function downloadBest(videoId): void {
        if (!root.title || downloadProc.running)
            return;
        root.notice = Translation.tr("Finding the best stream to download…");
        root._run(downloadProc, ["auto", JSON.stringify(root._downloadArgs(root.title, videoId))], "download");
    }

    /// Queue every aired episode of one season that is not already downloaded. Each job resolves
    /// its own link when it gets a Downloads slot, so a long queue never holds expired links.
    function downloadSeason(season): void {
        if (!root.title || root.title.type !== "series" || downloadProc.running)
            return;
        const today = new Date().toISOString().slice(0, 10);
        const ids = (root.title.videos ?? []).filter(v => v.season === season && (!v.released || v.released <= today)
            && !root.downloadState(root.title, v.id)).map(v => String(v.id));
        if (ids.length === 0) {
            root.notice = Translation.tr("Nothing left to download in this season.");
            return;
        }
        root.notice = Translation.tr("Queuing %1 episodes…").arg(ids.length);
        const a = root._downloadArgs(root.title, ids[0]);
        a.episodeIds = ids;
        root._run(downloadProc, ["batch", JSON.stringify(a)], "download");
    }

    // A stream picked from the list
    function download(stream): void {
        if (!root.title || downloadProc.running || root.pickedEpisodeId === "")
            return;
        const a = root._downloadArgs(root.title, root.pickedEpisodeId);
        if (stream.direct) {
            root.notice = Translation.tr("Queuing the direct stream…");
            root._run(downloadProc, ["hls", JSON.stringify(a)], "download");
            return;
        }
        a.infoHash = stream.infoHash;
        a.fileIdx = stream.fileIdx;
        a.sources = stream.sources ?? [];
        a.name = stream.filename || root.title.name;
        if (!a.infoHash) {
            root.notice = Translation.tr("That one is a direct link, which cannot be downloaded here.");
            return;
        }
        root.notice = Translation.tr("Adding to qBittorrent…");
        root._run(downloadProc, ["add", JSON.stringify(a)], "download");
    }

    Timer {
        interval: 5000
        repeat: true
        running: root.view !== "home" || Object.keys(root.downloads).length > 0
        onTriggered: root.refreshDownloads()
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const r = JSON.parse(String(text ?? "").trim());
                    if (r && !r.error)
                        root.downloads = r;
                } catch (e) {}
            }
        }
    }

    Process {
        id: downloadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                if (r.error) {
                    root.notice = r.error;
                    return;
                }
                if (r.total !== undefined) {
                    const bits = [Translation.tr("%1 queued").arg(r.started)];
                    if (r.active + r.have > 0)
                        bits.push(Translation.tr("%1 already there").arg(r.active + r.have));
                    if (r.failed > 0)
                        bits.push(Translation.tr("%1 not found").arg(r.failed));
                    root.notice = bits.join(" · ") + Translation.tr(" — follow them in Downloads.");
                    root.refreshDownloads();
                    return;
                }
                const where = String(r.path ?? "").replace(/^.*\/Videos\//, "");
                root.notice = r.result === "have" ? Translation.tr("Already in your library.") : Translation.tr("Downloading to %1 — follow it in Downloads.").arg(where);
                root.refreshDownloads();
            }
        }
    }

    function _parse(text) {
        try {
            return JSON.parse(String(text ?? "").trim());
        } catch (e) {
            return { "error": Translation.tr("Stremio helper returned nothing") };
        }
    }

    Process {
        id: chooseProc
        onExited: (code, status) => {
            const p = root._playPayload;
            root._playPayload = null;
            if (p)
                root._start(p.show, p.episode, p.name, p.poster);
        }
    }

    Connections {
        target: MediatorService
        function onProviderStreamStarted() {
            root.starting = false;
        }
        function onDirectFailedChanged() {
            if (MediatorService.directFailed) {
                root.notice = "";
                root.starting = false;
            }
        }
        function onStreamErrorChanged() {
            if (MediatorService.streamError !== "") {
                root.notice = MediatorService.streamError;
                root.starting = false;
            }
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                if (Array.isArray(r)) {
                    if (root.searching) {
                        root.results = r;
                        root.items = root._searchItems();
                    } else {
                        root.items = r;
                    }
                    root.moreAvailable = root._lastQuery === "" && r.length >= 40;
                    root.notice = r.length === 0 ? Translation.tr("Nothing found.") : "";
                } else {
                    root.items = [];
                    root.notice = r.error ?? "";
                }
            }
        }
    }

    Process {
        id: moreProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                if (!Array.isArray(r)) {
                    root.moreAvailable = false;
                    return;
                }
                const have = ({});
                root.items.forEach(i => have[i.id] = true);
                const fresh = r.filter(i => !have[i.id]);
                root.items = root.items.concat(fresh);
                root.moreAvailable = fresh.length >= 10;
            }
        }
    }

    Process {
        id: metaProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                if (r.error) {
                    root.notice = r.error;
                } else {
                    root.title = r;
                    root.loadSimilar();
                }
            }
        }
    }

    // More titles of the first genre, for the shelf under a title page
    property var similar: []
    function loadSimilar(): void {
        const t = root.title;
        const genre = (t?.genres ?? [])[0] ?? "";
        root.similar = [];
        root.topRated = [];
        if (!t || genre === "")
            return;
        root._run(similarProc, ["browse", String(t.type), "popular", String(genre), "0"]);
        root._run(topRatedProc, ["browse", String(t.type), "top", String(genre), "0"]);
    }
    property var topRated: []
    Process {
        id: topRatedProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                const me = String(root.title?.id ?? "");
                const seen = new Set(root.similar.map(i => String(i.id)));
                root.topRated = Array.isArray(r) ? r.filter(i => String(i.id) !== me && !seen.has(String(i.id))).slice(0, 14) : [];
            }
        }
    }
    Process {
        id: similarProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                const me = String(root.title?.id ?? "");
                root.similar = Array.isArray(r) ? r.filter(i => String(i.id) !== me).slice(0, 14) : [];
            }
        }
    }

    Process {
        id: streamsProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const r = root._parse(text);
                if (Array.isArray(r)) {
                    root.streams = r;
                    root.notice = r.length === 0 && (MediatorService.settings?.streaming?.hls === false) ? Translation.tr("No streams found for this one.") : "";
                } else {
                    root.streams = [];
                    root.notice = r.error ?? "";
                }
            }
        }
    }
}

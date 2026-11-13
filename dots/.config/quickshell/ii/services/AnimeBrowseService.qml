pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common

/**
 * Anime in the Streaming tab, shaped like the movies side: browse or search a catalog
 * (AniList), open a title page, and play an episode. The provider show and its episodes
 * are matched automatically from the catalog title, with the other candidates one click
 * away if the match is wrong.
 */
Singleton {
    id: root


    property string view: "home"          // "home" | "title"
    property string mode: "trending"
    property string heading: "Trending anime"
    property var items: []
    property string error: ""
    property var title: null
    property var chosen: null             // the provider show playing this title
    property bool matching: false
    property bool starting: false
    readonly property bool busy: listProc.running || mediaProc.running
    readonly property var candidates: Array.isArray(MediatorService.providerSearchResults)
        ? MediatorService.providerSearchResults : []
    readonly property var episodes: Array.isArray(MediatorService.providerEpisodes)
        ? MediatorService.providerEpisodes : []
    readonly property bool episodesBusy: MediatorService.providerEpisodesBusy
    readonly property string episodesError: String(MediatorService.providerEpisodesError ?? "")

    property string _tried: ""

    onItemsChanged: MediatorService.warmImages(root.items.map(i => i.poster))
    onTitleChanged: MediatorService.warmImages([root.title?.poster, root.title?.banner])

    function _run(proc, args): void {
        proc.running = false;
        proc.command = [MediatorService.binary, "anime-browse"].concat(args);
        proc.running = true;
    }

    function load(mode): void {
        root.mode = mode;
        root.view = "home";
        root.error = "";
        root.heading = ({ "trending": "Trending anime", "season": "Airing this season",
            "popular": "Most popular", "top": "Top rated" })[mode] ?? "Anime";
        root.items = [];
        root._run(listProc, [mode]);
    }

    function search(query): void {
        const text = String(query ?? "").trim();
        if (text === "")
            return;
        root.mode = "search";
        root.view = "home";
        root.error = "";
        root.heading = Translation.tr("Results for “%1”").arg(text);
        root.items = [];
        root._run(listProc, ["search", text]);
    }

    function openTitle(card): void {
        root.title = card;
        root.view = "title";
        root.chosen = null;
        root.error = "";
        root._tried = "";
        MediatorService.clearProviderSearch();
        if (!card.description && Number(card.id) > 0)
            root._run(mediaProc, ["media", String(card.id)]);
        root._match(String(card.search || card.title), card);
    }

    // From the AniList queue: only a title and ids are known, so fetch the rest
    function openQueued(query, anilistId, season, total): void {
        root.openTitle({ "id": anilistId, "title": query, "search": query, "poster": "",
            "format": season === 0 ? "MOVIE" : "TV", "season": season, "episodes": total, "year": "", "rating": "" });
    }

    function back(): void {
        root.view = "home";
        root.error = "";
    }

    function _norm(s): string {
        return String(s ?? "").toLowerCase().replace(/[^a-z0-9]+/g, " ").trim();
    }

    function _best(results, card): var {
        const wanted = [root._norm(card.search), root._norm(card.title)].filter(x => x);
        let best = null;
        let bestScore = -1;
        for (const r of results) {
            const t = root._norm(r.title);
            let score = 0;
            for (const w of wanted) {
                if (t === w)
                    score = Math.max(score, 100);
                else if (t.startsWith(w) || w.startsWith(t))
                    score = Math.max(score, 60 - Math.abs(t.length - w.length));
                else if (t.includes(w) || w.includes(t))
                    score = Math.max(score, 30 - Math.abs(t.length - w.length));
            }
            if (score > bestScore) {
                bestScore = score;
                best = r;
            }
        }
        return best ?? (results.length > 0 ? results[0] : null);
    }

    function _match(query, card): void {
        root.matching = true;
        root._tried = query;
        MediatorService.searchProvider(query);
    }

    function _settle(): void {
        if (MediatorService.providerSearchBusy || !root.matching || root.view !== "title")
            return;
        const results = MediatorService.providerSearchResults ?? [];
        if (results.length === 0) {
            // The catalog's other name sometimes matches where the first does not
            const alt = String(root.title?.title ?? "");
            if (alt !== "" && alt !== root._tried) {
                root._match(alt, root.title);
                return;
            }
            root.matching = false;
            return;
        }
        root.matching = false;
        root.choose(root._best(results, root.title));
    }

    function choose(show): void {
        root.chosen = show;
        MediatorService.loadProviderEpisodes(show);
    }

    function episodeState(episodeId): var {
        const show = String(root.chosen?.id ?? "");
        const list = Array.isArray(MediatorService.streamHistory) ? MediatorService.streamHistory : [];
        return list.find(h => h.show_id === show && h.episode_id === episodeId) ?? null;
    }

    function resumeEntry(): var {
        const show = String(root.chosen?.id ?? "");
        const list = MediatorService.streamShows(MediatorService.streamHistory, h => h.show_id === show);
        return list.length > 0 ? list[0] : null;
    }

    function play(episode): void {
        if (root.starting || !root.chosen || !episode?.id)
            return;
        root.starting = true;
        startGuard.restart();
        const card = root.title;
        MediatorService.playProviderEpisode(String(root.chosen.id), String(episode.id),
            String(root.chosen.title ?? card.title), false, "best",
            String(root.chosen.poster ?? card.poster ?? ""), true, Number(card.id ?? 0),
            card.format === "MOVIE" ? 0 : Math.max(1, Number(card.season ?? 1)), Number(card.episodes ?? 0));
    }

    // ── Downloads (through the Downloads app) ──────────────────────────────
    property var downloads: ({})          // episode id → { state, percent, error }
    property bool batchActive: false
    property string downloadNotice: ""
    readonly property int pad: root.episodes.length > 99 ? 3 : 2
    readonly property string fileTitle: String(root.title?.title ?? root.chosen?.title ?? "")

    function downloadState(episodeId): var {
        return root.downloads[String(episodeId)] ?? null;
    }

    function _episodeList(list): var {
        return list.map(e => ({ "id": String(e.id), "number": String(e.number) }));
    }

    function _request(list): string {
        return JSON.stringify({ "show": String(root.chosen?.id ?? ""), "title": root.fileTitle, "pad": root.pad,
            "dub": false, "quality": "best",
            "height": Number(Config.options.mediator.animeDownloadQuality ?? 1080), "episodes": root._episodeList(list) });
    }

    function refreshDownloads(): void {
        if (!root.chosen || statusProc.running || root.episodes.length === 0)
            return;
        statusProc.command = [MediatorService.binary, "download", "anime-status", root._request(root.episodes)];
        statusProc.running = true;
    }

    function downloadEpisode(episode): void {
        if (!root.chosen || downloadProc.running)
            return;
        root.downloadNotice = Translation.tr("Downloading episode %1 — follow it in Downloads.").arg(episode.number);
        downloadProc.command = [MediatorService.binary, "download", "anime-episode", root._request([episode])];
        downloadProc.running = true;
    }

    // Everything not yet watched or on disk (the helper skips what is already saved)
    function downloadSeason(remainingOnly): void {
        if (!root.chosen || downloadProc.running)
            return;
        const list = root.episodes.filter(e => !remainingOnly || !(root.episodeState(String(e.id))?.watched));
        if (list.length === 0)
            return;
        root.downloadNotice = Translation.tr("Queued %1 episodes — two download at a time, follow them in Downloads.").arg(list.length);
        downloadProc.command = [MediatorService.binary, "download", "anime-season", root._request(list)];
        downloadProc.running = true;
    }

    // Exactly these episodes (the library's missing ones), whatever is watched
    function downloadEpisodes(list): void {
        if (!root.chosen || downloadProc.running || list.length === 0)
            return;
        root.downloadNotice = Translation.tr("Queued %1 episodes — two download at a time, follow them in Downloads.").arg(list.length);
        downloadProc.command = [MediatorService.binary, "download", "anime-season", root._request(list)];
        downloadProc.running = true;
    }

    function cancelDownloads(): void {
        if (!root.chosen)
            return;
        cancelProc.command = [MediatorService.binary, "download", "anime-cancel", String(root.chosen.id)];
        cancelProc.running = true;
    }

    Timer {
        interval: 4000
        repeat: true
        running: root.view === "title" && root.chosen !== null
        onTriggered: root.refreshDownloads()
    }

    onEpisodesChanged: if (root.view === "title") root.refreshDownloads()
    onChosenChanged: {
        root.downloads = ({});
        root.batchActive = false;
    }

    Process {
        id: statusProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const r = JSON.parse(String(text ?? "").trim());
                    if (r?.ok) {
                        root.downloads = r.episodes;
                        root.batchActive = r.batch === true;
                    }
                } catch (e) {}
            }
        }
    }

    Process {
        id: downloadProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.refreshDownloads()
        }
    }

    Process {
        id: cancelProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.downloadNotice = Translation.tr("Cancelled the queued downloads.");
                root.refreshDownloads();
            }
        }
    }

    Timer {
        id: startGuard
        interval: 6000
        onTriggered: root.starting = false
    }

    Connections {
        target: MediatorService
        function onProviderSearchBusyChanged() {
            // The reply handler clears busy before it stores the results, so settle afterwards
            if (!MediatorService.providerSearchBusy)
                Qt.callLater(root._settle);
        }
        function onProviderStreamStarted() {
            root.starting = false;
        }
        function onStreamErrorChanged() {
            if (MediatorService.streamError !== "")
                root.starting = false;
        }
    }

    Process {
        id: listProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const r = JSON.parse(String(text ?? "").trim());
                    if (Array.isArray(r)) {
                        root.items = r;
                        root.error = r.length === 0 ? Translation.tr("Nothing found.") : "";
                    } else {
                        root.items = [];
                        root.error = String(r.error ?? "Could not load anime.");
                    }
                } catch (e) {
                    root.items = [];
                    root.error = Translation.tr("Could not load anime.");
                }
            }
        }
    }

    Process {
        id: mediaProc
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    const r = JSON.parse(String(text ?? "").trim());
                    if (Array.isArray(r) && r.length > 0 && root.title && Number(r[0].id) === Number(root.title.id))
                        root.title = Object.assign({}, root.title, r[0], { "search": root.title.search || r[0].search });
                } catch (e) {}
            }
        }
    }
}

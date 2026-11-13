pragma ComponentBehavior: Bound

import QtQuick

import qs.services

/**
 * What an episode that is not in the library can do: stream now or download. No interface of
 * its own, the title's episode list shows the rows. Anime go through the same provider flow as
 * the Streaming tab (the season's AniList entry is opened, its provider episodes matched by
 * number); shows go through Stremio's streams and its qBittorrent download.
 */
Item {
    id: root

    property var title: ({})
    property bool isAnime: false
    property var seasons: []
    property string imdbId: ""
    /// The season the list is showing, and the missing episodes of it
    property int season: 1
    property var shown: []

    /// Stremio: the episode whose streams are being chosen
    property bool pickerOpen: false
    signal streamStarted()

    // anime: the provider's own list for this season
    readonly property var providerEpisodes: AnimeBrowseService.episodes
    readonly property bool finding: AnimeBrowseService.matching || AnimeBrowseService.episodesBusy

    function code(e): string {
        return `S${String(e.season).padStart(2, "0")}E${String(e.number).padStart(2, "0")}`;
    }

    function providerFor(e): var {
        return root.providerEpisodes.find(p => Number(p.number) === e.number) ?? null;
    }

    function openSeason(): void {
        if (!root.isAnime || root.shown.length === 0)
            return;
        const info = root.seasons.find(s => Number(s.season) === root.season);
        if (!info?.anilist)
            return;
        AnimeBrowseService.openQueued(String(info.title ?? root.title.name), Number(info.anilist),
            root.season, Number(info.episodes ?? 0));
    }

    onSeasonChanged: root.openSeason()
    onShownChanged: if (root.shown.length > 0 && root.providerEpisodes.length === 0) root.openSeason()
    // A show cached before its IMDb id was kept: fetch it now, the id arrives as a binding
    Component.onCompleted: {
        root.openSeason();
        if (!root.isAnime && !/^tt[0-9]+$/.test(root.imdbId))
            MediatorService.startEnrich("missing", false, false);
    }

    // ── the card each episode's actions run through ──
    readonly property var card: ({ "id": root.imdbId, "type": "series", "name": String(root.title.name ?? ""),
        "year": String(root.title.year ?? "") })

    function videoId(e): string {
        return `${root.imdbId}:${e.season}:${e.number}`;
    }

    property string startingCode: ""
    property string localError: ""
    readonly property bool starting: AnimeBrowseService.starting && root.startingCode !== ""
    readonly property string streamError: String(MediatorService.streamError ?? "")

    function stream(e): void {
        console.log(`[missing] stream ${root.code(e)} anime=${root.isAnime} imdb=${root.imdbId}`);
        root.localError = "";
        if (root.isAnime) {
            const p = root.providerFor(e);
            if (!p) {
                root.localError = root.finding ? "Still finding the episodes online, try again in a moment"
                    : "That episode isn't on the online source yet";
                return;
            }
            MediatorService.streamError = "";
            root.startingCode = root.code(e);
            AnimeBrowseService.play(p);
            return;
        }
        if (!/^tt[0-9]+$/.test(root.imdbId)) {
            root.localError = "Looking up this show on Stremio, try again in a moment";
            MediatorService.startEnrich("missing", false, false);
            return;
        }
        StremioService.openTitle(root.card);
        StremioService.loadStreams(root.videoId(e), root.code(e));
        root.pickerOpen = true;
    }

    // Playback has opened: the start line or the player appearing, whichever comes first
    function _started(): void {
        if (root.startingCode !== "" || root.pickerOpen) {
            root.startingCode = "";
            root.pickerOpen = false;
            root.streamStarted();
        }
    }

    Connections {
        target: MediatorService
        function onProviderStreamStarted() { root._started(); }
        function onNativeActiveChanged() { if (MediatorService.nativeActive) root._started(); }
    }
    onStreamErrorChanged: if (root.streamError !== "") root.startingCode = ""

    function download(e): void {
        if (root.isAnime) {
            const p = root.providerFor(e);
            if (p)
                AnimeBrowseService.downloadEpisode(p);
            else
                root.localError = root.finding ? "Still finding the episodes online, try again in a moment"
                    : "That episode isn't on the online source yet";
            return;
        }
        root.enqueue([e]);
    }

    function downloadAll(): void {
        if (root.isAnime) {
            const list = root.shown.map(e => root.providerFor(e)).filter(p => p !== null);
            AnimeBrowseService.downloadEpisodes(list);
            return;
        }
        root.enqueue(root.shown);
    }

    // Stremio downloads one at a time: the next goes in a moment after the last
    property var queue: []
    function enqueue(list): void {
        if (!/^tt[0-9]+$/.test(root.imdbId)) {
            root.localError = "Looking up this show on Stremio, try again in a moment";
            MediatorService.startEnrich("missing", false, false);
            return;
        }
        if (!StremioService.title || StremioService.title.id !== root.imdbId)
            StremioService.title = root.card;
        root.queue = root.queue.concat(list.filter(e => !root.queue.includes(e)));
        feed.start();
    }

    Timer {
        id: feed
        interval: 1500
        repeat: true
        onTriggered: {
            if (root.queue.length === 0) {
                feed.stop();
                return;
            }
            const next = root.queue[0];
            root.queue = root.queue.slice(1);
            StremioService.downloadBest(root.videoId(next));
        }
    }

    /// "Downloaded", "Downloading 40%", "Queued" or ""
    function stateText(e): string {
        if (root.isAnime) {
            const p = root.providerFor(e);
            const st = p ? AnimeBrowseService.downloadState(String(p.id)) : null;
            if (!st)
                return "";
            return st.state === "done" ? "Downloaded" : st.state === "running" ? `Downloading ${Math.round(st.percent ?? 0)}%` : String(st.state);
        }
        const st = StremioService.downloadState(root.card, root.videoId(e));
        if (st)
            return `Downloading ${Math.round((st.progress ?? 0) * 100)}%`;
        return root.queue.includes(e) ? "Queued" : "";
    }

    /// One line for whatever is going on: starting, a failure, or what the source says
    readonly property string note: root.starting ? `Starting ${root.startingCode}… this can take a few seconds`
        : root.localError !== "" ? root.localError
        : root.streamError !== "" ? root.streamError
        : root.isAnime
        ? (root.finding ? "Finding the episodes online…"
            : root.providerEpisodes.length === 0 && root.shown.length > 0
                ? (AnimeBrowseService.episodesError || "No online source found for this season")
                : AnimeBrowseService.downloadNotice)
        : (StremioService.view === "streams" ? "" : StremioService.notice)
}

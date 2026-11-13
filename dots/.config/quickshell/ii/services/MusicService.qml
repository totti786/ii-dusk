pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.modules.common

/**
 * Bridge to scripts/music/music.py. Playback lives in a detached daemon that owns an mpv
 * and the queue, so music goes on when the window closes; this holds a socket to it only
 * while the Music window is open, and the daemon pushes its state down it. Searching,
 * lyrics, favourites and the rest are one-shot calls that print JSON.
 */
Singleton {
    id: root

    readonly property string script: `${Directories.scriptPath}/music/music.py`
    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/music-daemon.sock`
    readonly property bool wanted: GlobalStates.musicOpen

    // ── what the player is doing ──
    property bool linked: false
    property var track: null
    property var queue: []
    property int queueIndex: -1
    property bool playing: false
    property bool paused: true
    property bool loading: false
    property real duration: 0
    property int volume: 70
    property string repeatMode: "off"
    property bool shuffle: false
    property string playerError: ""
    property real basePosition: 0
    property real baseStamp: Date.now()
    /// Interpolated between the daemon's once-a-second updates, so lyrics move smoothly
    property real position: 0
    readonly property bool hasTrack: root.track !== null && (root.track?.id ?? "") !== ""

    // ── lyrics ──
    property var lyrics: ({ lines: [], synced: false, source: "" })
    property bool lyricsLoading: false
    property string lyricsFor: ""
    readonly property int lyricIndex: {
        const lines = root.lyrics.lines ?? [];
        if (!root.lyrics.synced || lines.length === 0)
            return -1;
        const t = root.position + 0.2;
        let lo = 0, hi = lines.length - 1, found = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (lines[mid].t <= t) {
                found = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return found;
    }

    // ── what the pages show ──
    property var searchItems: []
    property bool searching: false
    property string searchError: ""
    property string searchQuery: ""
    property string searchKind: "songs"
    property var collection: ({ head: {}, tracks: [] })
    property bool collectionLoading: false
    property string collectionError: ""
    property var homeShelves: []
    property bool homeLoading: false
    property string homeError: ""
    property var favorites: []
    property var history: []

    // ── artists: the page being shown, and who is followed (kept on this machine) ──
    property var artist: ({ head: {}, songs: [], albums: [], singles: [], related: [], following: false })
    property bool artistLoading: false
    property string artistError: ""
    property var following: []
    readonly property var followIds: {
        const ids = {};
        for (const a of root.following)
            ids[a.id] = true;
        return ids;
    }
    /// Anything that shows an artist's name asks for the page here; the window opens it
    signal artistRequested(string id, string name, string art)
    readonly property var favIds: {
        const ids = {};
        for (const t of root.favorites)
            ids[t.id] = true;
        return ids;
    }
    // Downloads kept for good: ids by state, and the tracks themselves for the Library
    property var downloads: []
    property var dlDone: ({})
    property var dlBusy: ({})
    property real dlBytes: 0
    readonly property bool anyBusy: Object.keys(root.dlBusy).length > 0
    property var taste: ({ artists: [], tracks: 0, hours: 0, skipped: 0 })
    property var settings: ({})
    property var cacheSizes: ({})
    property bool saving: false
    property string saveError: ""

    function isFav(id: string): bool {
        return root.favIds[id] === true;
    }

    function isDownloaded(id: string): bool {
        return root.dlDone[id] === true;
    }

    function isDownloading(id: string): bool {
        return root.dlBusy[id] === true;
    }

    // ── talking to the daemon ──
    property var outbox: []

    function send(msg: var): void {
        if (root.linked) {
            sock.write(JSON.stringify(msg) + "\n");
            sock.flush();
            return;
        }
        // Window closed (the IPC's playpause/next/prev): no socket is coming, so a queued
        // message would wait and replay on the next open. One `ctl` call starts the daemon if needed.
        if (!root.wanted) {
            Quickshell.execDetached(["python3", "-I", root.script, "ctl", msg.cmd]);
            return;
        }
        root.outbox.push(msg);
        root.connectPlayer();
    }

    function play(tracks: var, index: int): void {
        root.send({ cmd: "play", tracks: tracks, index: index });
    }

    function shuffleAndPlay(tracks: var): void {
        const list = tracks.slice();
        for (let i = list.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [list[i], list[j]] = [list[j], list[i]];
        }
        if (list.length > 0)
            root.play(list, 0);
    }

    function playOne(track: var): void {
        root.play([track], 0);
    }

    function enqueue(track: var, next: bool): void {
        root.send({ cmd: "enqueue", track: track, next: next });
    }

    function toggle(): void { root.send({ cmd: "toggle" }); }
    function next(): void { root.send({ cmd: "next" }); }
    function prev(): void { root.send({ cmd: "prev" }); }
    function seek(pos: real): void {
        root.basePosition = pos;
        root.baseStamp = Date.now();
        root.position = pos;
        root.send({ cmd: "seek", pos: pos });
    }
    function setVolume(v: int): void {
        root.volume = v;
        root.send({ cmd: "volume", volume: v });
    }
    function cycleRepeat(): void { root.send({ cmd: "repeat" }); }
    function toggleShuffle(): void { root.send({ cmd: "shuffle" }); }
    function jump(i: int): void { root.send({ cmd: "jump", index: i }); }
    function removeFromQueue(i: int): void { root.send({ cmd: "remove", index: i }); }
    function clearQueue(): void { root.send({ cmd: "clear" }); }

    function connectPlayer(): void {
        if (root.linked || ensureProc.running)
            return;
        ensureProc.running = true;
    }

    function applyState(s: var): void {
        root.track = s.track;
        if (s.queue !== undefined) {
            root.queue = s.queue;
            root.queueIndex = s.index;
        } else {
            root.queueIndex = s.index;
        }
        root.playing = s.playing;
        root.paused = s.paused;
        root.loading = s.loading;
        root.duration = s.dur;
        root.volume = s.volume;
        root.repeatMode = s.repeat;
        root.shuffle = s.shuffle;
        root.playerError = s.error ?? "";
        root.basePosition = s.pos;
        root.baseStamp = Date.now();
        root.position = s.pos;
        if (s.track && s.track.id !== root.lyricsFor)
            root.loadLyrics(s.track);
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: false
        parser: SplitParser {
            onRead: line => {
                try {
                    const msg = JSON.parse(line);
                    if (msg.event === "state")
                        root.applyState(msg);
                } catch (e) {}
            }
        }
        onConnectedChanged: {
            root.linked = sock.connected;
            if (sock.connected) {
                sock.write(JSON.stringify({ cmd: "subscribe" }) + "\n");
                for (const m of root.outbox)
                    sock.write(JSON.stringify(m) + "\n");
                root.outbox = [];
                sock.flush();
            } else if (root.wanted) {
                retry.restart();
            }
        }
        // A failed connect never flips `connected`, so it has to be retried from here
        onError: if (root.wanted) retry.restart()
    }

    // Starts the daemon if it is not up (a `ctl state` does that), then connects
    Process {
        id: ensureProc
        command: ["python3", "-I", root.script, "ctl", "state"]
        onExited: if (root.wanted) sock.connected = true
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: if (root.wanted && !root.linked) {
            sock.connected = false;
            root.connectPlayer();
        }
    }

    onWantedChanged: {
        if (root.wanted) {
            root.connectPlayer();
            root.loadSettings();
            root.loadDownloads();
            root.loadFollowing();
        } else {
            retry.stop();
            sock.connected = false;
            // Whatever never got through is stale by the next open
            root.outbox = [];
        }
    }

    Timer {
        interval: 150
        repeat: true
        running: root.wanted && root.playing
        onTriggered: root.position = Math.min(root.duration > 0 ? root.duration : Infinity,
            root.basePosition + (Date.now() - root.baseStamp) / 1000)
    }

    // ── one-shot calls ──
    component Runner: Process {
        id: runner
        signal finished(var data)
        stdout: StdioCollector {
            onStreamFinished: {
                let d = null;
                try {
                    d = JSON.parse(text);
                } catch (e) {}
                runner.finished(d);
            }
        }
    }

    property var wantedSearch: null
    property var searchMemo: ({})

    function search(query: string, kind: string): void {
        const q = query.trim();
        if (q.length === 0)
            return;
        root.wantedSearch = { q: q, kind: kind };
        root.searchError = "";
        // Asked before this session: show it at once, no process needed
        const hit = root.searchMemo[kind + ":" + q.toLowerCase()];
        if (hit) {
            root.searchItems = hit;
            root.searchQuery = q;
            root.searchKind = kind;
            root.searching = false;
            return;
        }
        if (!searchRun.running)
            root.runSearch();
    }

    function runSearch(): void {
        const w = root.wantedSearch;
        root.searching = true;
        searchRun.ran = w;
        searchRun.command = ["python3", "-I", root.script, "search", w.q, "--kind", w.kind];
        searchRun.running = true;
    }

    Runner {
        id: searchRun
        property var ran: null
        onFinished: data => {
            if (root.wantedSearch !== searchRun.ran) {
                root.runSearch();  // typed again meanwhile: only the latest counts
                return;
            }
            root.searching = false;
            root.searchQuery = searchRun.ran.q;
            root.searchKind = searchRun.ran.kind;
            if (data?.ok) {
                root.searchItems = data.items;
                root.searchMemo[searchRun.ran.kind + ":" + searchRun.ran.q.toLowerCase()] = data.items;
            } else {
                root.searchItems = [];
                root.searchError = data?.error ?? "Search failed";
            }
        }
    }

    function requestArtist(id: string, name: string, art: string): void {
        root.artistRequested(id, name, art);
    }

    function isFollowing(id: string): bool {
        return root.followIds[id] === true;
    }

    function openArtist(id: string, name: string, art: string): void {
        root.artist = ({ head: { name: name, id: id }, songs: [], albums: [], singles: [], related: [], following: false });
        root.artistError = "";
        root.artistLoading = true;
        const cmd = ["python3", "-I", root.script, "artist", id.length > 0 ? id : name, "--name", name];
        if (art.length > 0)
            cmd.push("--art", art);
        artistRun.command = cmd;
        artistRun.running = true;
    }

    /// Put back a page that was already loaded, so going back is instant
    function restoreArtist(data: var): void {
        root.artistError = "";
        root.artistLoading = false;
        root.artist = data;
    }

    Runner {
        id: artistRun
        onFinished: data => {
            root.artistLoading = false;
            if (data?.ok) {
                root.artist = data;
            } else {
                root.artistError = data?.error ?? "Could not open that artist";
            }
        }
    }

    function toggleFollow(id: string, name: string, art: string): void {
        followRun.environment = ({ "MUSIC_ARTIST": JSON.stringify({ id: id, name: name, art: art }) });
        followRun.command = ["python3", "-I", root.script, "follow", "toggle"];
        followRun.running = true;
    }

    function loadFollowing(): void {
        if (followRun.running)
            return;
        followRun.environment = ({});
        followRun.command = ["python3", "-I", root.script, "follow", "list"];
        followRun.running = true;
    }

    Runner {
        id: followRun
        onFinished: data => {
            if (!data?.ok)
                return;
            root.following = data.artists;
            if ((root.artist.head?.id ?? "") !== "")
                root.artist = Object.assign({}, root.artist, { following: root.followIds[root.artist.head.id] === true });
        }
    }

    function playArtistRadio(radioId: string): void {
        if (radioId.length === 0)
            return;
        radioRun.command = ["python3", "-I", root.script, "artist-radio", radioId];
        radioRun.running = true;
    }

    Runner {
        id: radioRun
        onFinished: data => { if (data?.ok && data.tracks.length > 0) root.play(data.tracks, 0); }
    }

    function openCollection(kind: string, id: string): void {
        root.collection = ({ head: {}, tracks: [] });
        root.collectionError = "";
        root.collectionLoading = true;
        collectionRun.command = ["python3", "-I", root.script, kind, id];
        collectionRun.running = true;
    }

    Runner {
        id: collectionRun
        onFinished: data => {
            root.collectionLoading = false;
            if (data?.ok)
                root.collection = data;
            else
                root.collectionError = data?.error ?? "Could not open that";
        }
    }

    function loadHome(): void {
        if (homeRun.running)
            return;
        root.homeLoading = true;
        root.homeError = "";
        homeRun.running = true;
    }

    Runner {
        id: homeRun
        command: ["python3", "-I", root.script, "home"]
        onFinished: data => {
            root.homeLoading = false;
            if (data?.ok)
                root.homeShelves = data.shelves;
            else
                root.homeError = data?.error ?? "Could not load recommendations";
        }
    }

    function loadLibrary(): void {
        favRun.command = ["python3", "-I", root.script, "fav", "list"];
        favRun.running = true;
        histRun.running = true;
    }

    Runner {
        id: favRun
        onFinished: data => { if (data?.ok) root.favorites = data.tracks; }
    }

    Runner {
        id: histRun
        command: ["python3", "-I", root.script, "history"]
        onFinished: data => { if (data?.ok) root.history = data.tracks; }
    }

    function toggleFav(track: var): void {
        const t = { id: track.id, title: track.title, artist: track.artist, album: track.album,
                    duration: track.duration, art: track.art, artistRefs: track.artistRefs ?? [] };
        favToggleRun.environment = ({ "MUSIC_TRACK": JSON.stringify(t) });
        favToggleRun.command = ["python3", "-I", root.script, "fav", "toggle"];
        favToggleRun.running = true;
    }

    Runner {
        id: favToggleRun
        onFinished: data => {
            if (data?.ok)
                root.favorites = data.tracks;
            if (root.settings.auto_download_likes)  // liking started a download
                root.loadDownloads();
        }
    }

    // ── downloads and taste ──
    function loadDownloads(): void {
        if (dlRun.running)
            return;
        dlRun.command = ["python3", "-I", root.script, "dl", "list"];
        dlRun.running = true;
    }

    function toggleDownload(track: var): void {
        const t = { id: track.id, title: track.title, artist: track.artist, album: track.album,
                    duration: track.duration, art: track.art };
        dlToggleRun.environment = ({ "MUSIC_TRACK": JSON.stringify(t) });
        dlToggleRun.command = ["python3", "-I", root.script, "dl", "toggle"];
        dlToggleRun.running = true;
    }

    function downloadLikes(): void {
        dlToggleRun.command = ["python3", "-I", root.script, "dl", "likes"];
        dlToggleRun.running = true;
    }

    function applyDownloads(data: var): void {
        if (!data?.ok)
            return;
        const done = {}, busy = {};
        for (const id of data.done)
            done[id] = true;
        for (const id of data.busy)
            busy[id] = true;
        root.dlDone = done;
        root.dlBusy = busy;
        root.downloads = data.tracks;
        root.dlBytes = data.bytes;
    }

    Runner {
        id: dlRun
        onFinished: data => root.applyDownloads(data)
    }

    Runner {
        id: dlToggleRun
        onFinished: data => root.applyDownloads(data)
    }

    // Poll while something is downloading, so the buttons turn into ticks by themselves
    Timer {
        interval: 2000
        repeat: true
        running: root.wanted && root.anyBusy
        onTriggered: root.loadDownloads()
    }

    function loadTaste(): void {
        tasteRun.command = ["python3", "-I", root.script, "taste"];
        tasteRun.running = true;
    }

    function resetTaste(): void {
        tasteRun.command = ["python3", "-I", root.script, "taste", "reset"];
        tasteRun.running = true;
    }

    Runner {
        id: tasteRun
        onFinished: data => { if (data?.ok) root.taste = data; }
    }

    function loadLyrics(track: var): void {
        root.lyricsFor = track.id;
        root.lyrics = ({ lines: [], synced: false, source: "" });
        root.lyricsLoading = true;
        lyricsRun.command = ["python3", "-I", root.script, "lyrics", track.id, "--title", track.title,
                             "--artist", track.artist ?? "", "--duration", String(track.duration ?? 0)];
        lyricsRun.running = true;
    }

    Runner {
        id: lyricsRun
        onFinished: data => {
            if (data?.id !== root.lyricsFor)
                return;
            root.lyricsLoading = false;
            if (data?.ok)
                root.lyrics = data;
        }
    }

    function loadSettings(): void {
        settingsRun.command = ["python3", "-I", root.script, "config", "show"];
        settingsRun.running = true;
        cacheRun.command = ["python3", "-I", root.script, "cache"];
        cacheRun.running = true;
    }

    Runner {
        id: settingsRun
        onFinished: data => { if (data?.ok) root.settings = data.settings; }
    }

    Runner {
        id: cacheRun
        onFinished: data => { if (data?.ok) root.cacheSizes = data.sizes; }
    }

    function saveSettings(patch: var): void {
        if (saveRun.running)
            return;
        root.saveError = "";
        root.saving = true;
        saveRun.environment = ({ "MUSIC_CONFIG_PATCH": JSON.stringify(patch) });
        saveRun.command = ["python3", "-I", root.script, "config", "set"];
        saveRun.running = true;
    }

    Runner {
        id: saveRun
        onFinished: data => {
            root.saving = false;
            if (data?.ok)
                root.settings = data.settings;
            else
                root.saveError = data?.error ?? "Could not save";
        }
    }

    function clearCache(what: string): void {
        cacheRun.command = ["python3", "-I", root.script, "cache", "clear", what];
        cacheRun.running = true;
    }
}

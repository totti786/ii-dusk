pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs.modules.common
import qs.services

/**
 * Bridge to the `mediator` CLI (~/Projects/mediator). It does the library scanning,
 * progress tracking and mpv launching; this only runs it with --json and keeps the
 * results for the browser window. Nothing here knows how episodes are parsed.
 */
Singleton {
    id: root

    signal providerStreamStarted()

    // The shipped shell carries its own backend at scripts/mediator (a zipapp under
    // vendor/). Packagers can point at a system mediator with mediator.binary.
    readonly property string binary: {
        const custom = String(Config.options?.mediator?.binary ?? "").trim();
        return custom !== "" ? custom : Quickshell.shellPath("scripts/mediator");
    }

    // The private, last successful carousel survives closing Mediator and shell restarts.
    property var continueSnapshot: []
    property bool continueSnapshotReady: false
    property bool continueSnapshotUpdated: false
    readonly property string continueSnapshotDir: (Quickshell.env("MEDIATOR_STATE_DIR") || ((Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/mediator")) + "/native-episodes"

    function preloadContinueCache(): void { continueCacheDir.running = true; }

    function saveContinueSnapshot(items: var): void {
        root.continueSnapshotUpdated = true;
        root.continueSnapshot = items;
        root.continueSnapshotReady = true;
        root.warmImages(items.map(item => item.poster));
        continueCacheWrite.restart();
    }

    Process {
        id: continueCacheDir
        command: ["mkdir", "-p", "-m", "700", root.continueSnapshotDir]
        onExited: code => {
            if (code === 0) {
                continueCacheFile.reload();
                if (root.continueSnapshotUpdated) continueCacheWrite.restart();
            }
        }
    }
    Timer {
        id: continueCacheWrite
        interval: 150
        onTriggered: continueCacheFile.setText(JSON.stringify({ version: 1, items: root.continueSnapshot }))
    }
    FileView {
        id: continueCacheFile
        path: root.continueSnapshotDir + "/.continue-carousel"
        atomicWrites: true
        printErrors: false
        onSaveFailed: error => console.warn("[Mediator] continue cache not saved:", error)
        onLoaded: {
            if (root.continueSnapshotUpdated) return;
            try {
                const cache = JSON.parse(text());
                if (cache.version === 1 && Array.isArray(cache.items)) {
                    root.continueSnapshot = cache.items.slice(0, 9);
                    root.continueSnapshotReady = true;
                    root.warmImages(root.continueSnapshot.map(item => item.poster));
                }
            } catch (e) {}
        }
    }

    property var titles: []
    property var recent: []
    property var detail: null
    property bool loading: false
    property bool loaded: false
    property string error: ""
    property string detailId: ""
    property var settings: ({})
    property bool saving: false
    property string saveError: ""
    /// "" before a test, then "testing", "ok" or "failed", with a line to show
    property string jellyfinState: ""
    property string jellyfinMessage: ""

    // Playback preferences that belong to this shell session. Watch Together is intentionally
    // separate from mediator's persistent config so a one-off Syncplay session is easy to turn
    // on and cannot silently change normal playback later.
    property bool watchTogether: false
    property bool playbackBusy: false
    property string playbackMessage: ""
    property string playbackError: ""

    // AniList account and actions. The status object is deliberately the backend's redacted
    // JSON view: it contains token_set, never the token itself.
    property var anilistStatus: ({})
    property bool anilistBusy: false
    property string anilistAction: ""
    property string anilistMessage: ""
    property string anilistError: ""
    property var anilistResult: null
    property bool openAniListAfterStatus: false
    // Streaming hub: the user's AniList queue and the native provider's own history.
    property var anilistWatching: []
    property bool anilistWatchingBusy: false
    property string anilistWatchingError: ""
    property var streamHistory: []
    property bool streamHistoryBusy: false
    property string streamHistoryError: ""
    property bool streamHistoryReloadQueued: false

    // Persistent cover cache shared with the backend (`mediator cache-images`).
    // The index is read from disk at startup so an already-cached cover is used
    // immediately instead of downloading the remote URL again.
    readonly property string imageCacheDir: {
        const override = String(Quickshell.env("MEDIATOR_CACHE_DIR") || "").trim();
        if (override !== "")
            return override.replace(/\/+$/, "") + "/images";
        const base = String(Quickshell.env("XDG_CACHE_HOME") || "").trim();
        const home = String(Quickshell.env("HOME") || "").trim();
        return (base !== "" ? base : `${home}/.cache`) + "/mediator/images";
    }
    readonly property string imageIndexPath: root.imageCacheDir + "/index.json"
    property var imageCache: ({})
    property var imageCachePending: []

    // Native provider browsing is intentionally separate from the legacy ani-cli command. The
    // GUI resolves provider ids and episodes itself, so no terminal picker is involved.
    property bool providerSearchBusy: false
    property var providerSearchResults: []
    property string providerSearchQuery: ""
    property string providerSearchError: ""
    property int providerSearchRequest: 0
    property bool providerEpisodesBusy: false
    property var providerEpisodes: []
    property var providerEpisodesTitle: ({})
    property string providerEpisodesError: ""
    property int providerEpisodesRequest: 0

    // The playback process stays alive while mpv plays. The service emits providerStreamStarted
    // only after the backend has resolved an exact episode and is about to launch mpv.
    property bool streamBusy: false
    property bool streamResolving: false
    property string streamMessage: ""
    property string streamError: ""
    property string streamQuery: ""
    property string providerPendingShowId: ""
    property string providerPendingEpisodeId: ""

    // Native provider playback is a long-lived worker process. Its socket name is derived
    // from the worker PID, so controls must always carry this PID instead of targeting the
    // newest unrelated local session.
    property var nativeState: ({})
    property bool nativeStateBusy: false
    property string nativeStateError: ""
    // The worker PID identifies the owned IPC socket. It is not the mpv PID and may
    // disappear during a shell reload while the exact mpv MPRIS player survives.
    property int nativePlayerPid: 0
    property bool nativeWorkerActive: false
    property string nativeMatchedMprisBusName: ""
    property bool nativeDaemonHold: false
    property var nativePendingLaunch: null
    property int nativeLaunchGeneration: 0
    property bool nativeStateReloadQueued: false
    /// The stream the worker's mpv was last seen playing. A series is one mpv playlist, so Enter
    /// or `>` changes the episode inside a single worker: the remembered state must be re-read.
    property string nativeSeenPath: ""
    Timer {
        id: nativeEpisodeReload
        interval: 150  // the daemon only reports a new episode once the worker has saved it
        onTriggered: {
            root.loadNativeState();
            root.loadStreamHistory();
        }
    }
    readonly property bool nativeHasState: String(nativeState?.show_id ?? "").trim() !== ""
        && String(nativeState?.episode_id ?? "").trim() !== ""
    readonly property string nativeExpectedTrackTitle: {
        const title = String(root.nativeState?.title ?? "").trim();
        const episode = String(root.nativeState?.episode_number ?? "").trim();
        if (title === "")
            return "";
        // Mirrors the label mediator gives mpv: movies are the bare title, Stremio
        // episodes read "Title S01E02", provider episodes "Title Episode 2".
        if (episode === "")
            return String(root.nativeState?.show_id ?? "").startsWith("stremio:") ? title : "";
        return /^S\d+E\d+$/.test(episode) ? `${title} ${episode}` : `${title} Episode ${episode}`;
    }
    readonly property var nativeMprisPlayer: root._nativeMprisPlayer()
    readonly property bool nativeMprisPlaying: root.nativeMprisPlayer
        ? (root.nativeMprisPlayer.isPlaying === true
            || root.nativeMprisPlayer.playbackState === MprisPlaybackState.Playing)
        : false
    /// A stream the shell did not start itself (the shell was reloaded mid-episode, so its worker
    /// handle is gone): the daemon still lists the session and tags it with the stream identity
    readonly property var nativeAdopted: root.nativeWorkerActive ? null
        : (root.nowPlaying.find(session => session?.native && String(session?.native?.show_id ?? "") !== ""
            && String(session?.path ?? "").trim() !== "") ?? null)
    readonly property int nativeControlPid: root.nativeWorkerActive ? root.nativePlayerPid
        : Number(root.nativeAdopted?.pid ?? root.localSession?.pid ?? 0)
    readonly property bool nativeActive: root.nativeWorkerActive || root.nativeAdopted !== null || root.localSession !== null
        || (root.nativeMprisPlayer !== null && root.nativeMprisPlayer.playbackState !== MprisPlaybackState.Stopped)
    // The bar pill is an activity, not a permanent bookmark: show while the player is
    // open, while an episode is resolving, and for a short grace period after close.
    property bool nativeLinger: false
    property bool nativeWasActive: false
    readonly property int nativeLingerMs: 120000
    readonly property bool nativePillVisible: root.nativeActive || root.streamBusy || root.nativeLinger
    readonly property var nativeNow: root.nativeWorkerActive && root.nativePlayerPid > 0
        ? (root.nowPlaying.find(session => Number(session?.pid ?? 0) === root.nativePlayerPid
            && String(session?.path ?? "").trim() !== "") ?? null)
        : (root.nativeAdopted ?? root.localSession)
    /// mpv's own session (its real time-pos, held while it buffers) - the MPRIS clock keeps
    /// extrapolating through a stall, and a stream's launcher pid is not mpv's
    readonly property var nativeSession: root.nativeExpectedTrackTitle !== ""
        ? (root.nowPlaying.find(session => String(session?.media_title ?? "") === root.nativeExpectedTrackTitle
            && Number(session?.duration ?? 0) > 0) ?? root.nativeNow)
        : root.nativeNow
    /// A local-library show or movie mediator itself is playing: a daemon session with a catalog title.
    /// It has no worker or saved stream state, but gets the same pill and card, fed from the session.
    readonly property var localSession: root.nativeWorkerActive ? null
        : (root.nowPlaying.find(session => String(session?.title_id ?? "") !== ""
            && !String(session.title_id).startsWith("online/")
            && String(session?.path ?? "").trim() !== "") ?? null)
    readonly property bool localPlaying: root.localSession !== null
    /// What the pill and card show: the stream worker's saved state, or the local session in the same shape
    readonly property var _localState: root.localSession ? ({
        show_id: String(root.localSession.title_id),
        episode_id: String((root.localSession.episodes?.length ?? 0) > 0 ? root.localSession.path
            : (root.localSession.code || root.localSession.label || root.localSession.path)),
        title: String(root.localSession.title ?? ""),
        poster: String(root.localSession.poster ?? ""),
        episode_number: String(root.localSession.label ?? ""),
        episode_title: String(root.localSession.episode_title ?? ""),
        episodes: root.localSession.episodes ?? [],
        local: true,
        movie: String(root.localSession.lib ?? "") === "movies"
    }) : null
    /// The last library/Jellyfin episode, kept after its player closes so the pill (which lingers)
    /// shows what was watched last rather than the last streamed title
    property var lastLocal: null
    property bool lastWasLocal: false
    on_LocalStateChanged: {
        if (root._localState !== null) {
            root.lastLocal = root._localState;
            root.lastWasLocal = true;
        }
    }
    onNativeWorkerActiveChanged: if (root.nativeWorkerActive) root.lastWasLocal = false
    readonly property bool _showLastLocal: root._localState === null && root.lastWasLocal && root.lastLocal !== null
    readonly property var displayState: root._localState ?? (root._showLastLocal ? root.lastLocal : root.nativeState)
    readonly property bool displayHasState: root.localPlaying || root._showLastLocal || root.nativeHasState
    readonly property bool nativeBuffering: root.nativeSession?.buffering === true
    /// mpv has the stream open but nothing to show yet (a torrent still finding peers): its
    /// player reports "playing" and a clock that keeps running, so go by the missing length
    readonly property bool nativeLoading: root.nativeActive && (root.nativeMprisPlayer
        ? !(Number(MprisController.trackLengthOf(root.nativeMprisPlayer) ?? 0) > 0)
        : root.nativeNow ? !(Number(root.nativeNow.duration ?? 0) > 0) : false)
    readonly property real nativePosition: root.nativeLoading ? Number(root.nativeState?.position ?? 0)
        : root.nativeSession && Number(root.nativeSession.duration ?? 0) > 0 ? Number(root.nativeSession.position ?? 0)
        : root.nativeMprisPlayer
        ? Number(MprisController.trackPositionOf(root.nativeMprisPlayer) ?? 0)
        : root.nativeNow
            ? Number(root.nativeNow.position ?? 0)
            : Number(root.nativeState?.position ?? 0)
    readonly property real nativeDuration: root.nativeMprisPlayer
        ? Number(MprisController.trackLengthOf(root.nativeMprisPlayer) ?? 0)
        : root.nativeNow
            ? Number(root.nativeNow.duration ?? 0)
            : Number(root.nativeState?.duration ?? 0)
    readonly property bool nativePaused: root.nativeMprisPlayer
        ? !root.nativeMprisPlaying
        : root.nativeNow ? Boolean(root.nativeNow.paused) : false

    function _isMpvMprisPlayer(player: var): bool {
        if (!player)
            return false;
        const identity = String(player.identity ?? "").trim().toLowerCase();
        const desktop = String(player.desktopEntry ?? "").trim().toLowerCase();
        const bus = String(player.dbusName ?? "").trim();
        return identity === "mpv" || desktop === "mpv"
            || /^org\.mpris\.MediaPlayer2\.mpv(?:\.|$)/.test(bus);
    }

    /// The daemon's own player: mpv's MPRIS plugin is off in Mediator's mpv, so this is the one entry
    function _isMediatorMprisPlayer(player: var): bool {
        return String(player?.dbusName ?? "") === "org.mpris.MediaPlayer2.mediator";
    }

    /// The daemon's player is the remembered episode when its metadata says so: artist the show, title
    /// the episode's own name. This needs no daemon session, which only exists while something holds
    /// the socket - after a shell reload nothing does, and without this the pill vanished until the
    /// app was opened, leaving the generic media bubble in its place.
    function _mediatorPlayerIsRemembered(player: var): bool {
        if (!root.nativeHasState)
            return false;
        const show = String(root.nativeState?.title ?? "").trim();
        const title = String(player?.trackTitle ?? "").trim();
        const artist = String(player?.trackArtist ?? "").trim();
        if (show === "")
            return false;
        const episodeId = String(root.nativeState?.episode_id ?? "");
        const episode = (root.nativeState?.episodes ?? []).find(e => String(e?.id ?? "") === episodeId);
        const episodeTitle = String(episode?.title ?? "").trim();
        if (artist === show)
            return episodeTitle === "" || title === episodeTitle || title === root.nativeExpectedTrackTitle;
        // A movie has no artist: the title is the show's
        return artist === "" && (title === show || title === root.nativeExpectedTrackTitle);
    }

    function _nativeMprisCandidates(): var {
        const expected = root.nativeExpectedTrackTitle;
        const mediatorSession = (root.nativeSession !== null && root.nativeSession !== undefined) || root.localPlaying;
        return (MprisController.allPlayers ?? []).filter(player => {
            // Its title is the episode's own, not mpv's forced "Show S01E02" label: the daemon session
            // already matched on that label
            if (root._isMediatorMprisPlayer(player))
                // A running stream worker owns the daemon's player outright. Matching its titles
                // against the remembered episode failed for a moment on every playlist advance
                // (the player already shows the new episode, the saved state is a beat behind), which
                // handed it to the generic media bubble.
                return player.playbackState !== MprisPlaybackState.Stopped
                    && (root.nativeWorkerActive || mediatorSession || root._mediatorPlayerIsRemembered(player));
            if (expected === "")
                return false;
            if (!root._isMpvMprisPlayer(player))
                return false;
            if (String(player.trackTitle ?? "").trim() !== expected)
                return false;
            return player.playbackState !== MprisPlaybackState.Stopped;
        });
    }

    /// One player with this title, or when a leftover mpv shares it, the one actually playing.
    /// Never whichever happens to come first in the global MPRIS list.
    function _onlyCandidate(candidates: var): var {
        if (candidates.length === 1)
            return candidates[0];
        const playing = candidates.filter(p => p.isPlaying === true || p.playbackState === MprisPlaybackState.Playing);
        return playing.length === 1 ? playing[0] : null;
    }

    function _nativeMprisPlayer(): var {
        const candidates = root._nativeMprisCandidates();
        if (root.nativeMatchedMprisBusName !== "")
            return candidates.find(player => String(player.dbusName ?? "") === root.nativeMatchedMprisBusName) ?? null;
        return root._onlyCandidate(candidates);
    }

    function refreshNativeMprisMatch(): void {
        const candidates = root._nativeMprisCandidates();
        if (root.nativeMatchedMprisBusName !== "") {
            const cached = candidates.find(player => String(player.dbusName ?? "")
                === root.nativeMatchedMprisBusName);
            if (cached)
                return;
            root.nativeMatchedMprisBusName = "";
        }
        const only = root._onlyCandidate(candidates);
        if (only)
            root.nativeMatchedMprisBusName = String(only.dbusName ?? "");
    }

    function _nativeMprisGone(): void {
        root.refreshNativeMprisMatch();
        if (!root.nativeMprisPlayer && !root.nativeWorkerActive
                && root.nativePendingLaunch && !providerPlayProc.running) {
            const pending = root.nativePendingLaunch;
            root.nativePendingLaunch = null;
            nativeStopWatchdog.stop();
            root.streamBusy = true;
            root.streamResolving = true;
            Qt.callLater(() => root._launchProviderEpisode(pending));
        }
    }

    Connections {
        target: MprisController
        function onAllPlayersChanged() { root.refreshNativeMprisMatch(); }
    }

    Instantiator {
        model: Mpris.players
        delegate: Connections {
            required property var modelData
            target: modelData
            function onTrackTitleChanged() { root.refreshNativeMprisMatch(); }
            function onPlaybackStateChanged() { root.refreshNativeMprisMatch(); }
        }
    }

    Timer {
        id: nativeMprisPositionTimer
        interval: 1000
        repeat: true
        running: root.nativeMprisPlayer !== null
        onTriggered: root.nativeMprisPlayer?.positionChanged()
    }

    Timer {
        id: nativePillLingerTimer
        interval: root.nativeLingerMs
        repeat: false
        onTriggered: root.nativeLinger = false
    }

    onNativeActiveChanged: {
        if (root.nativeActive) {
            root.nativeWasActive = true;
            root.nativeLinger = false;
            nativePillLingerTimer.stop();
        } else if (root.nativeWasActive) {
            root.nativeWasActive = false;
            root.nativeLinger = true;
            nativePillLingerTimer.restart();
        }
    }

    onNativeStateChanged: {
        root.refreshNativeMprisMatch();
        root.warmImages([root.nativeState?.poster]);
    }
    onStreamHistoryChanged: root.warmImages((root.streamHistory || []).map(item => item?.poster))
    onAnilistWatchingChanged: root.warmImages((root.anilistWatching || []).map(item => item?.poster))
    onProviderSearchResultsChanged: root.warmImages((root.providerSearchResults || []).map(item => item?.poster))
    onNativeMprisPlayerChanged: {
        const player = root.nativeMprisPlayer;
        // Fallback for a start line that arrived late (or was lost): the exact
        // MPRIS player appearing is proof enough that mpv is playing.
        if (player && root.streamResolving && !root.nativePendingLaunch
                && !providerPlayProc.hasStarted) {
            providerPlayProc.hasStarted = true;
            root.streamResolving = false;
            root.streamMessage = "Playing anime stream…";
            root.streamError = "";
            root.loadNativeState();
            root.loadStreamHistory();
            root.providerStreamStarted();
        }
        // Not inline: it rewrites nativeMatchedMprisBusName, which this very property depends on
        Qt.callLater(root._nativeMprisGone);
    }

    Component.onCompleted: {
        root.preloadContinueCache();
        root.nativeWasActive = root.nativeActive;
        Qt.callLater(root.loadNativeState);
        Qt.callLater(() => root.mediatorPlayerPresentChanged());
    }

    FileView {
        id: imageIndexView
        path: root.imageIndexPath
        watchChanges: true
        printErrors: false
        onLoaded: {
            let next = Object.assign({}, root.imageCache);
            try {
                const raw = JSON.parse(text());
                for (const url in raw) {
                    const path = String(raw[url] ?? "").trim();
                    if (path !== "")
                        next[url] = path.startsWith("file:") ? path : `file://${path}`;
                }
            } catch (e) {}
            root.imageCache = next;
        }
    }

    function loadSettings(): void {
        settingsProc.running = true;
    }

    /// Write {"section.key": value} through `mediator config set`. The patch travels in the
    /// environment, so an API key never shows up in a process listing.
    function saveSettings(patch: var): void {
        if (saveProc.running)
            return;
        root.saving = true;
        root.saveError = "";
        saveProc.pendingPatch = patch;
        saveProc.environment = ({ MEDIATOR_CONFIG_PATCH: JSON.stringify(patch) });
        saveProc.running = true;
    }

    function testJellyfin(): void {
        root.jellyfinState = "testing";
        root.jellyfinMessage = "Connecting…";
        jellyfinProc.running = true;
    }

    /// Watch Together plays through the shell's Syncplay session, not a separate Syncplay window.
    function _togetherPrefix(): var {
        return root.watchTogether ? SyncplayService.mediatorCommandPrefix : [];
    }

    function _localCommand(subcommand: string, args: var): var {
        return root._togetherPrefix().concat([root.binary]).concat(root.watchTogether ? ["-s"] : []).concat([subcommand]).concat(args || []);
    }

    function openAniListConsent(): void {
        const url = String(root.anilistStatus.auth_url ?? "").trim();
        if (url !== "") {
            Quickshell.execDetached(["xdg-open", url]);
            root.anilistMessage = "AniList consent opened in your browser.";
            root.anilistError = "";
            return;
        }
        // status --json supplies the built-in public client id from the backend. This avoids
        // keeping a second copy of that id in the shell configuration.
        root.openAniListAfterStatus = true;
        root.loadAniListStatus();
    }

    function loadAniListStatus(): void {
        if (anilistProc.running)
            return;
        root.anilistAction = "status";
        root.anilistBusy = true;
        root.anilistMessage = "Checking AniList…";
        root.anilistError = "";
        anilistProc.command = [root.binary, "anilist", "status", "--json"];
        anilistProc.stdinPayload = "";
        anilistProc.stdinEnabled = true;
        anilistProc.running = true;
    }

    function connectAniList(tokenOrUrl: string): void {
        const token = String(tokenOrUrl ?? "").trim();
        if (token === "") {
            root.anilistError = "Paste the token or the redirected AniList URL first.";
            return;
        }
        if (anilistProc.running)
            return;
        root.anilistAction = "login";
        root.anilistBusy = true;
        root.anilistMessage = "Checking AniList token…";
        root.anilistError = "";
        // The token is sent through stdin and is never included in Process.command or an
        // environment variable. Clear the payload immediately after Process writes it.
        anilistProc.command = [root.binary, "anilist", "login", "--token-stdin", "--json"];
        anilistProc.stdinPayload = token;
        anilistProc.stdinEnabled = true;
        anilistProc.running = true;
    }

    function logoutAniList(): void {
        if (anilistProc.running)
            return;
        root.anilistAction = "logout";
        root.anilistBusy = true;
        root.anilistMessage = "Signing out of AniList…";
        root.anilistError = "";
        anilistProc.command = [root.binary, "anilist", "logout", "--json"];
        anilistProc.stdinPayload = "";
        anilistProc.stdinEnabled = true;
        anilistProc.running = true;
    }

    function syncAniListAll(): void {
        _syncAniList(["--all", "--fetch"], "sync-all");
    }

    function retryAniList(): void {
        _syncAniList(["--pending", "--fetch"], "sync-pending");
    }

    function syncAniListTitle(id: string): void {
        if (String(id ?? "").trim() === "")
            return;
        _syncAniList([id, "--fetch"], "sync-title");
    }

    function _syncAniList(args: var, action: string): void {
        if (anilistProc.running)
            return;
        root.anilistAction = action;
        root.anilistBusy = true;
        root.anilistMessage = action === "sync-pending" ? "Retrying pending AniList updates…"
            : action === "sync-title" ? "Syncing this anime with AniList…" : "Syncing local anime with AniList…";
        root.anilistError = "";
        anilistProc.command = [root.binary, "anilist", "sync"].concat(args || []).concat(["--json"]);
        anilistProc.stdinPayload = "";
        anilistProc.stdinEnabled = true;
        anilistProc.running = true;
    }

    function scoreAniListTitle(id: string, value: string, season: string): void {
        const titleId = String(id ?? "").trim();
        const score = String(value ?? "").trim();
        if (titleId === "" || score === "") {
            root.anilistError = "Enter a score before sending it to AniList.";
            return;
        }
        if (anilistProc.running)
            return;
        root.anilistAction = "score";
        root.anilistBusy = true;
        root.anilistMessage = "Saving AniList score…";
        root.anilistError = "";
        const args = [root.binary, "anilist", "score", titleId, score];
        const seasonText = String(season ?? "").trim();
        const n = Number(seasonText);
        if (seasonText !== "" && Number.isFinite(n) && n >= 0)
            args.push("--season", String(Math.trunc(n)));
        args.push("--json");
        anilistProc.command = args;
        anilistProc.stdinPayload = "";
        anilistProc.stdinEnabled = true;
        anilistProc.running = true;
    }

    function _finishAniList(resultText: string, errText: string, code: int): void {
        const action = root.anilistAction;
        let parsed = null;
        try {
            parsed = JSON.parse(String(resultText ?? "").trim());
        } catch (e) {}
        root.anilistResult = parsed;
        if (action === "status") {
            if (parsed && typeof parsed === "object") {
                root.anilistStatus = parsed;
                if (parsed.ok) {
                    root.anilistError = "";
                    root.anilistMessage = parsed.pending > 0
                        ? `${parsed.username || "AniList"} connected · ${parsed.pending} pending update${parsed.pending === 1 ? "" : "s"}`
                        : `${parsed.username || "AniList"} connected`;
                } else {
                    root.anilistError = String(parsed.error || "AniList is not connected");
                    root.anilistMessage = "AniList is not connected";
                }
            } else if (code !== 0) {
                root.anilistError = String(errText ?? "").trim().replace(/^mediator:\s*/, "")
                    || "Could not read AniList status.";
            }
            if (root.openAniListAfterStatus) {
                root.openAniListAfterStatus = false;
                const url = String(root.anilistStatus.auth_url ?? "").trim();
                if (url !== "")
                    Quickshell.execDetached(["xdg-open", url]);
            }
            return;
        }

        if (code !== 0) {
            const detail = String(errText ?? "").trim().replace(/^mediator:\s*/, "");
            root.anilistError = detail || (action === "login" ? "AniList rejected that token."
                : action === "logout" ? "Could not sign out of AniList."
                : "AniList could not complete that request.");
            root.anilistMessage = "";
            return;
        }
        root.anilistError = "";
        if (action === "login") {
            root.anilistMessage = parsed?.username ? `Connected as ${parsed.username}.` : "AniList connected.";
            root.loadSettings();
            Qt.callLater(root.loadAniListStatus);
        } else if (action === "logout") {
            root.anilistMessage = "AniList disconnected.";
            root.loadSettings();
            root.anilistStatus = ({ configured: false, ok: false, pending: 0 });
        } else if (action === "score") {
            root.anilistMessage = "AniList score saved.";
            Qt.callLater(root.loadAniListStatus);
        } else {
            let rows = Array.isArray(parsed) ? parsed : [];
            let saves = 0, errors = 0;
            for (const row of rows) {
                saves += (row.saves ?? []).length;
                errors += (row.errors ?? []).length;
            }
            root.anilistMessage = saves > 0 ? `AniList sync saved ${saves} update${saves === 1 ? "" : "s"}.`
                : "AniList sync is up to date.";
            if (errors > 0)
                root.anilistError = `${errors} AniList update${errors === 1 ? "" : "s"} failed; retry pending.`;
            Qt.callLater(root.loadAniListStatus);
        }
    }

    /// Bumped when a poster is replaced; the fragment gives the same file a new image-cache key
    property int posterVersion: 0
    property string posterMessage: ""
    property bool posterBusy: false

    function posterUrl(path): string {
        // Streamed titles carry the poster's web address, not a cached file
        if (/^(https?|file):/.test(String(path ?? "")))
            return root.cachedImage(path);
        return path ? `file://${path}#${root.posterVersion}` : "";
    }

    /// Replace a title's poster with an image file or an http(s) URL.
    function setPoster(id: string, source: string): void {
        if (posterProc.running || source.trim() === "")
            return;
        root.posterBusy = true;
        root.posterMessage = "";
        posterProc.command = [root.binary, "posters", "set", id, source.trim(), "--json"];
        posterProc.running = true;
    }

    function refresh(): void {
        // The Continue row must not wait on the library listing: `list` stays alive after it has
        // printed, refreshing the Jellyfin cache behind itself, and `history` is cheap and independent
        if (!historyProc.running)
            historyProc.running = true;
        if (listProc.running) {
            root.refreshStale = true;
            return;
        }
        root.refreshStale = false;
        root.loading = true;
        listProc.running = true;
    }

    /// Open a title's page: the old page goes blank until the new one arrives.
    function loadDetail(id: string): void {
        root.detailId = id;
        root.detail = null;
        root.fetchDetail();
    }

    /// Re-read the open page in place (an episode got marked, info arrived): what is shown
    /// stays until the answer lands, so the list does not flash or lose its place.
    function reloadDetail(): void {
        if (root.detailId !== "")
            root.fetchDetail();
    }

    /// One `show` at a time; a request that arrives meanwhile runs right after, for whatever id is open then.
    function fetchDetail(): void {
        if (detailProc.running) {
            root.detailStale = true;
            return;
        }
        root.detailStale = false;
        detailProc.requestedId = root.detailId;
        detailProc.command = [root.binary, "show", root.detailId, "--all", "--json"];
        detailProc.running = true;
    }
    property bool detailStale: false

    /// 3:07 or 1:02:09
    function clock(sec): string {
        const t = Math.max(0, Math.round(sec ?? 0));
        const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), r = t % 60;
        const pad = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? `${h}:${pad(m)}:${pad(r)}` : `${m}:${pad(r)}`;
    }

    function clearDetail(): void {
        root.detailId = "";
        root.detail = null;
    }

    /// Read tracks and resolution from a title's files (ffprobe, cached); reloads the page when done.
    property string probingId: ""
    function probeTitle(id: string): void {
        if (probeProc.running)
            return;
        root.probingId = id;
        probeProc.command = [root.binary, "probe", id];
        probeProc.running = true;
    }

    function openTrailer(url: string): void {
        Quickshell.execDetached(["mpv", "--force-window=immediate", url]);
    }

    function clearProviderSearch(): void {
        root.providerSearchRequest += 1;
        root.providerEpisodesRequest += 1;
        root.providerSearchQuery = "";
        root.providerSearchResults = [];
        root.providerSearchError = "";
        root.providerEpisodes = [];
        root.providerEpisodesTitle = ({});
        root.providerEpisodesError = "";
    }

    function loadStreamHistory(): void {
        if (streamHistoryProc.running) {
            root.streamHistoryReloadQueued = true;
            return;
        }
        root.streamHistoryBusy = true;
        root.streamHistoryError = "";
        streamHistoryProc.replyText = "";
        streamHistoryProc.errorText = "";
        streamHistoryProc.command = [root.binary, "stream-state", "--all", "--json"];
        streamHistoryProc.running = true;
    }

    function loadAniListWatching(): void {
        if (anilistWatchingProc.running)
            return;
        root.anilistWatchingBusy = true;
        root.anilistWatchingError = "";
        anilistWatchingProc.replyText = "";
        anilistWatchingProc.errorText = "";
        anilistWatchingProc.command = [root.binary, "anilist", "watching", "--json", "--limit", "30"];
        anilistWatchingProc.running = true;
    }

    function cachedImage(url): string {
        const key = String(url ?? "").trim();
        if (key === "")
            return "";
        const hit = root.imageCache[key];
        return hit ? String(hit) : key;
    }

    function warmImages(urls): void {
        if (!Array.isArray(urls))
            return;
        const pending = root.imageCachePending.slice();
        const known = root.imageCache || ({});
        for (const raw of urls) {
            const url = String(raw ?? "").trim();
            if (!/^https?:\/\//i.test(url))
                continue;
            if (known[url] || pending.indexOf(url) !== -1
                    || imageCacheProc.batch.indexOf(url) !== -1)
                continue;
            pending.push(url);
        }
        if (pending.length === root.imageCachePending.length)
            return;
        root.imageCachePending = pending;
        if (!imageCacheProc.running)
            Qt.callLater(root._drainImageCache);
    }

    function _drainImageCache(): void {
        if (imageCacheProc.running || root.imageCachePending.length === 0)
            return;
        const batch = root.imageCachePending.slice(0, 12);
        root.imageCachePending = root.imageCachePending.slice(batch.length);
        imageCacheProc.batch = batch;
        imageCacheProc.replyText = "";
        imageCacheProc.command = [root.binary, "cache-images", "--json"].concat(batch);
        imageCacheProc.running = true;
    }

    function loadStreaming(): void {
        root.loadStreamHistory();
        root.loadAniListStatus();
        root.loadAniListWatching();
    }

    function loadNativeState(): void {
        if (nativeStateProc.running) {
            root.nativeStateReloadQueued = true;
            return;
        }
        nativeStateProc.requestGeneration = root.nativeLaunchGeneration;
        root.nativeStateBusy = true;
        root.nativeStateError = "";
        nativeStateProc.replyText = "";
        nativeStateProc.errorText = "";
        nativeStateProc.command = [root.binary, "stream-state", "--json"];
        nativeStateProc.running = true;
    }

    function _nativeLaunchPayload(showId: string, episodeId: string, title: string,
                                  dub: bool, quality: string, poster: string,
                                  anilistId, anilistSeason, anilistTotal): var {
        return {
            showId: String(showId ?? "").trim(),
            episodeId: String(episodeId ?? "").trim(),
            title: String(title ?? "").trim(),
            dub: Boolean(dub),
            quality: String(quality ?? "best").trim() || "best",
            poster: String(poster ?? "").trim(),
            anilistId: Number(anilistId ?? 0) || 0,
            anilistSeason: Number(anilistSeason ?? 0) || 0,
            anilistTotal: Number(anilistTotal ?? 0) || 0
        };
    }

    function _launchProviderEpisode(payload: var): void {
        if (!payload || String(payload.showId ?? "").trim() === ""
                || String(payload.episodeId ?? "").trim() === "") {
            root.streamError = "Select an exact anime episode first.";
            root.streamBusy = false;
            root.streamResolving = false;
            return;
        }
        root.streamBusy = true;
        root.streamResolving = true;
        root.streamQuery = String(payload.title ?? "");
        // The bubble and bar pill read the remembered state: until the new episode reports in, it
        // would still describe the previous show, and its player would match nothing and get its own bubble.
        root.nativeState = ({
            "show_id": String(payload.showId), "episode_id": String(payload.episodeId),
            "title": String(payload.title ?? ""), "poster": String(payload.poster ?? ""),
            "episode_number": "", "episode_title": "", "episodes": [],
            "position": 0, "duration": 0, "watched": false, "dub": Boolean(payload.dub),
            "quality": String(payload.quality ?? "best")
        });
        root.streamMessage = "Resolving episode source…";
        root.streamError = "";
        root.providerPendingShowId = String(payload.showId);
        root.providerPendingEpisodeId = String(payload.episodeId);
        const command = root._togetherPrefix().concat([root.binary]).concat(root.watchTogether ? ["-s"] : []).concat(["stream-play", String(payload.showId),
            String(payload.episodeId), "--title", String(payload.title ?? ""), "--json"]);
        if (String(payload.poster ?? "").trim() !== "")
            command.push("--poster", String(payload.poster));
        if (payload.dub)
            command.push("--dub");
        if (String(payload.quality ?? "").trim() !== "")
            command.push("--quality", String(payload.quality).trim());
        // Prefer an explicit AniList id from the streaming section. Otherwise, once
        // this show has matched, reuse that identity for later episodes instead of
        // re-searching a season name.
        let anilistId = Number(payload.anilistId ?? 0) || 0;
        let anilistSeason = Number(payload.anilistSeason ?? 0) || 0;
        let anilistTotal = Number(payload.anilistTotal ?? 0) || 0;
        const mapped = root.nativeState;
        if (anilistId <= 0 && String(mapped?.show_id ?? "") === String(payload.showId)
                && Number(mapped?.anilist_id ?? 0) > 0) {
            anilistId = Number(mapped.anilist_id);
            anilistSeason = Number(mapped.season ?? 0);
            anilistTotal = Number(mapped.total ?? 0);
        }
        if (anilistId > 0) {
            command.push("--anilist-id", String(anilistId),
                "--season", String(anilistSeason),
                "--total", String(anilistTotal));
        }
        providerPlayProc.hasStarted = false;
        providerPlayProc.errorText = "";
        providerPlayProc.replyError = "";
        providerPlayProc.generation = ++root.nativeLaunchGeneration;
        providerPlayProc.command = command;
        // Hold the daemon independently of Browser windows. The hold is balanced when this
        // worker exits, so an idle shell does not keep a companion process or library scan.
        if (!root.nativeDaemonHold) {
            root.nativeDaemonHold = true;
            root.retain();
        }
        providerPlayProc.running = true;
    }

    function searchProvider(query: string): void {
        const text = String(query ?? "").trim();
        if (text === "") {
            root.providerSearchError = "Enter an anime title to search.";
            root.providerSearchResults = [];
            return;
        }
        if (providerSearchProc.running)
            return;
        root.providerSearchRequest += 1;
        providerSearchProc.requestId = root.providerSearchRequest;
        root.providerSearchQuery = text;
        root.providerSearchBusy = true;
        root.providerSearchError = "";
        root.providerSearchResults = [];
        providerSearchProc.replyText = "";
        providerSearchProc.errorText = "";
        providerSearchProc.command = [root.binary, "stream-search", text, "--json"];
        providerSearchProc.running = true;
    }

    function loadProviderEpisodes(show: var): void {
        const id = String(show?.id ?? "").trim();
        if (id === "") {
            root.providerEpisodesError = "The provider result has no stable id.";
            return;
        }
        if (providerEpisodesProc.running)
            return;
        root.providerEpisodesRequest += 1;
        providerEpisodesProc.requestId = root.providerEpisodesRequest;
        root.providerEpisodesBusy = true;
        root.providerEpisodesError = "";
        root.providerEpisodes = [];
        root.providerEpisodesTitle = show;
        providerEpisodesProc.replyText = "";
        providerEpisodesProc.errorText = "";
        providerEpisodesProc.command = [root.binary, "stream-episodes", id, "--json"];
        providerEpisodesProc.running = true;
    }

    function playProviderEpisode(showId: string, episodeId: string, title: string,
                                  dub: bool, quality: string, poster, switchCurrent,
                                  anilistId, anilistSeason, anilistTotal): void {
        const id = String(showId ?? "").trim();
        const ep = String(episodeId ?? "").trim();
        if (id === "" || ep === "") {
            root.streamError = "Select an exact anime episode first.";
            return;
        }
        // Clicking the episode that is already loaded is a resume, not a switch.
        if (root.nativeActive
                && String(root.nativeState?.show_id ?? "") === id
                && String(root.nativeState?.episode_id ?? "") === ep) {
            if (root.nativePaused)
                root.nativeControl("play");
            return;
        }
        if (root.streamBusy || providerPlayProc.running || root.nativeActive) {
            if (!Boolean(switchCurrent)) {
                root.streamError = "An anime stream is already playing; close it before starting another.";
                return;
            }
            if ((root.nativePendingLaunch?.showId ?? "") === id
                    && (root.nativePendingLaunch?.episodeId ?? "") === ep) {
                root.streamError = "That episode is already queued.";
                return;
            }
            if (root.streamResolving && !root.nativeMprisPlayer) {
                root.streamError = "Wait for the current episode to finish opening.";
                return;
            }
            if (!root.nativeWorkerActive && !root.nativeMprisPlayer) {
                root.streamError = "Wait for the current episode to finish opening.";
                return;
            }
            root.nativePendingLaunch = root._nativeLaunchPayload(id, ep, title, dub, quality, poster,
                anilistId, anilistSeason, anilistTotal);
            root.streamError = "";
            root.streamMessage = "Switching episode…";
            root.streamResolving = true;
            const player = root.nativeMprisPlayer;
            if (player) {
                // MPRIS survives a shell reload even when the provider worker does not.
                // Quit the exact matched mpv and wait for that bus to disappear before
                // resolving the queued episode.
                if (player.canQuit !== false && typeof player.quit === "function")
                    player.quit();
                else if (typeof player.stop === "function")
                    player.stop();
            } else {
                // Use the exact owned socket: daemon discovery may lag player readiness.
                nativeStopProc.command = [root.binary, "stream-control", String(root.nativeControlPid), "stop", "--json"];
                nativeStopProc.running = true;
            }
            nativeStopWatchdog.restart();
            return;
        }
        root.nativePendingLaunch = null;
        root._launchProviderEpisode(root._nativeLaunchPayload(id, ep, title, dub, quality, poster,
            anilistId, anilistSeason, anilistTotal));
    }

    /// Plays or switches to the episode at `index` of the list the pill and card show (a stream
    /// or a library show). The card's episode list and the Syncplay window both call this.
    function launchEpisode(index: int): void {
        const saved = root.displayState;
        const episodes = Array.isArray(saved?.episodes) ? saved.episodes : [];
        if (index < 0 || index >= episodes.length || root.streamResolving
                || (root.streamBusy && !root.nativeActive))
            return;
        const episode = episodes[index];
        const episodeId = String(episode?.id ?? "");
        // In a Syncplay room fed by this worker, an episode the room already holds is a move
        // inside the room: the player stays open and everyone follows. Restarting the player
        // would drop out of the room and rejoin it.
        if (SyncplayService.mediatorOwned && SyncplayService.connected && saved?.local !== true) {
            const current = episodes.findIndex(e => String(e?.id ?? "") === String(saved?.episode_id ?? ""));
            const inRoom = Math.max(0, SyncplayService.playlistIndex) + (index - current);
            if (current >= 0 && index !== current && inRoom >= 0 && inRoom < SyncplayService.playlistItems.length) {
                SyncplayService.playlistPlay(inRoom);
                return;
            }
            // Not in the room yet (an earlier episode, or one past what the worker has fed in):
            // the worker adds it and moves the room, so the player stays open
            if (current >= 0 && index !== current && root.nativeActive && root.nativeControlPid > 0) {
                // straight to the player's own socket: the worker listens there for this message
                const sock = (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mediator-" + root.nativeControlPid + ".sock";
                roomGotoProc.command = ["python3", "-c",
                    "import json,socket,sys\nc=socket.socket(socket.AF_UNIX);c.settimeout(2);c.connect(sys.argv[1])\n"
                    + "c.sendall(json.dumps({'command':['script-message','mediator-room-goto',sys.argv[2]]}).encode()+b'\\n')",
                    sock, episodeId];
                roomGotoProc.running = true;
                return;
            }
        }
        if (saved?.local === true) {
            if (episodeId !== String(saved?.episode_id ?? "") && root.localPlaying)
                root.playLocalEpisode(episodeId);
            return;
        }
        const showId = String(saved?.show_id ?? "");
        const title = String(saved?.title ?? showId);
        const dub = Boolean(saved?.dub);
        const quality = String(saved?.quality ?? "best");
        const poster = String(saved?.poster ?? "");
        if (showId === "" || episodeId === "")
            return;
        if (episodeId === String(saved?.episode_id ?? "")) {
            if (!root.nativeActive)
                root.playProviderEpisode(showId, episodeId, title, dub, quality, poster);
            return;
        }
        if (root.streamBusy || root.nativeActive)
            root.switchNativeEpisode(showId, episodeId, title, dub, quality, poster);
        else
            root.playProviderEpisode(showId, episodeId, title, dub, quality, poster);
    }

    function switchNativeEpisode(showId: string, episodeId: string, title: string,
                                 dub: bool, quality: string, poster): void {
        root.playProviderEpisode(showId, episodeId, title, dub, quality, poster, true);
    }

    /// playerctl next/previous on a stream: move to the neighbouring episode of the saved list
    function stepNativeEpisode(dir: int): void {
        // In a Syncplay room mpv's own playlist holds one entry; the room's list is the one to move in
        if (SyncplayService.mediatorOwned && SyncplayService.connected) {
            const target = Math.max(0, SyncplayService.playlistIndex) + dir;
            if (target >= 0 && target < SyncplayService.playlistItems.length) {
                SyncplayService.playlistPlay(target);
                return;
            }
        }
        if (!root.nativeActive || !root.nativeHasState)
            return;
        const episodes = Array.isArray(root.nativeState.episodes) ? root.nativeState.episodes : [];
        const current = String(root.nativeState.episode_id ?? "");
        const index = episodes.findIndex(item => String(item?.id ?? "") === current);
        const target = episodes[index + dir];
        if (index < 0 || !target)
            return;
        root.switchNativeEpisode(String(root.nativeState.show_id), String(target.id),
            String(root.nativeState.title ?? ""), Boolean(root.nativeState.dub),
            String(root.nativeState.quality ?? "best"), String(root.nativeState.poster ?? ""));
    }

    function playRememberedNative(): void {
        if (!root.nativeHasState) {
            root.streamError = "No native anime episode has been saved yet.";
            return;
        }
        const state = root.nativeState;
        let episodeId = String(state.episode_id ?? "");
        // A finished episode should continue with the next one. The terminal
        // `stream-resume` already does this; keep the bar pill's play button in step
        // with it instead of replaying the episode that just ended.
        if (Boolean(state.watched)) {
            const episodes = Array.isArray(state.episodes) ? state.episodes : [];
            const index = episodes.findIndex(item => String(item?.id ?? "") === episodeId);
            if (index >= 0 && index + 1 < episodes.length)
                episodeId = String(episodes[index + 1]?.id ?? episodeId);
        }
        if (episodeId === "") {
            root.streamError = "No native anime episode has been saved yet.";
            return;
        }
        root.playProviderEpisode(String(state.show_id), episodeId,
            String(state.title ?? ""), Boolean(state.dub),
            String(state.quality ?? "best"), String(state.poster ?? ""));
    }

    function nativeControl(action: string, value): void {
        const player = root.nativeMprisPlayer;
        if (player) {
            if (action === "toggle" && player.canTogglePlaying !== false
                    && typeof player.togglePlaying === "function") {
                player.togglePlaying();
                return;
            }
            if (action === "pause" && typeof player.pause === "function") {
                player.pause();
                return;
            }
            if (action === "play" && typeof player.play === "function") {
                player.play();
                return;
            }
            if (action === "seek_to" && value !== null && value !== undefined) {
                player.position = Math.max(0, Number(value) || 0);
                return;
            }
            if (action === "stop") {
                if (player.canQuit !== false && typeof player.quit === "function")
                    player.quit();
                else if (typeof player.stop === "function")
                    player.stop();
                return;
            }
        }
        if (root.nativeControlPid <= 0) {
            root.streamError = "The native anime player is not running.";
            return;
        }
        if (nativeControlProc.running)
            return;
        const command = [root.binary, "stream-control", String(root.nativeControlPid), action, "--json"];
        if (value !== null && value !== undefined)
            command.push("--value", String(value));
        nativeControlProc.command = command;
        nativeControlProc.running = true;
    }

    function titleById(id: string): var {
        return root.titles.find(t => t.id === id) ?? null;
    }

    // ── What the library already holds, so the online pages can say so ──

    /// Lower-case words only, without a trailing "(2011)", so "Hunter x Hunter (2011)" meets "Hunter x Hunter"
    function normTitle(text: string): string {
        return String(text ?? "").toLowerCase().replace(/\(\s*(19|20)\d\d\s*\)/g, " ")
            .replace(/&/g, " and ").replace(/[^a-z0-9]+/g, " ").trim();
    }

    readonly property var ownedIndex: {
        const out = ({});
        for (const t of root.titles) {
            for (const name of [t.name, t.display]) {
                const key = root.normTitle(name);
                if (key !== "" && out[key] === undefined)
                    out[key] = t;
            }
        }
        return out;
    }

    /// The library title that goes by one of these names (and a year no more than one apart), or null
    function ownedFor(names: var, year: var): var {
        const y = Number(year ?? 0);
        for (const name of (Array.isArray(names) ? names : [names])) {
            const hit = root.ownedIndex[root.normTitle(name)];
            if (!hit)
                continue;
            const hy = Number(hit.year ?? 0);
            if (y > 0 && hy > 0 && Math.abs(y - hy) > 1)
                continue;
            return hit;
        }
        return null;
    }

    // ── Streamed titles, shaped like library titles so the carousel can show them ──

    function nextEpisodeOf(state: var): var {
        const episodes = Array.isArray(state?.episodes) ? state.episodes : [];
        const i = episodes.findIndex(e => String(e?.id ?? "") === String(state?.episode_id ?? ""));
        return i >= 0 && i + 1 < episodes.length ? episodes[i + 1] : null;
    }

    function _episodeTag(number: var): string {
        const n = String(number ?? "");
        return n === "" ? "" : (/^S\d+E\d+$/.test(n) ? n : "Ep " + n);
    }

    /// Start or resume a streamed title: the next episode once the last one was finished
    /// Take streamed shows off Continue watching (all their remembered episodes)
    function forgetStreams(showIds: var): void {
        const ids = (showIds || []).map(String).filter(x => x !== "");
        if (ids.length === 0)
            return;
        // Gone from the row right away; the helper confirms by the reload that follows
        root.streamHistory = (root.streamHistory || []).filter(h => !ids.includes(String(h?.show_id ?? "")));
        if (ids.includes(String(root.nativeState?.show_id ?? "")) && !root.nativeActive)
            root.nativeState = ({});
        forgetProc.command = [root.binary, "stream-forget", "--json"].concat(ids);
        forgetProc.running = true;
    }

    Process {
        id: forgetProc
        onExited: root.loadStreamHistory()
    }

    /**
     * One record per show, for "continue watching".
     *
     * An episode opened for a few seconds (a misclick, skipping ahead to find the right
     * one) is the newest record but not where the viewer is: it used to replace an episode
     * half-watched the day before. Such a brief, unfinished record only wins when the show
     * has nothing else. The row still sorts by the latest touch of the show.
     */
    readonly property real briefSeconds: 60

    function isBrief(s: var): bool {
        return !s?.watched && Number(s?.position ?? 0) < root.briefSeconds;
    }

    function streamShows(list: var, keep: var): var {
        const best = ({});
        const touched = ({});
        for (const s of (Array.isArray(list) ? list : [])) {
            const show = String(s?.show_id ?? "");
            if (show === "" || (keep && !keep(s)))
                continue;
            const at = Number(s.updated_at ?? 0);
            touched[show] = Math.max(touched[show] ?? 0, at);
            const cur = best[show];
            const better = !cur
                || (root.isBrief(cur) && !root.isBrief(s))
                || (root.isBrief(cur) === root.isBrief(s) && at > Number(cur.updated_at ?? 0));
            if (better)
                best[show] = s;
        }
        return Object.keys(best).sort((a, b) => touched[b] - touched[a]).map(k => best[k]);
    }

    function resumeStream(state: var): void {
        if (!state)
            return;
        if (String(state.show_id).startsWith("stremio:")) {
            StremioService.resume(state);
            return;
        }
        let episodeId = String(state.episode_id ?? "");
        if (state.watched) {
            const next = root.nextEpisodeOf(state);
            if (next)
                episodeId = String(next.id);
        }
        root.playProviderEpisode(String(state.show_id), episodeId,
            String(state.title ?? ""), Boolean(state.dub), String(state.quality ?? "best"),
            String(state.poster ?? ""), true, Number(state.anilist_id ?? 0),
            Number(state.season ?? 0), Number(state.total ?? 0));
    }

    readonly property var streamResumeRow: root.streamResumeItems(root.streamHistory)

    function streamResumeItems(history: var): var {
        const out = [];
        for (const s of root.streamShows(history)) {
            const show = String(s.show_id);
            const next = s.watched ? root.nextEpisodeOf(s) : null;
            if (s.watched && !next)
                continue;  // finished, and nothing after it
            const code = root._episodeTag(s.watched ? next.number : s.episode_number);
            out.push({
                "id": "stream:" + show, "name": String(s.title ?? ""), "display": String(s.title ?? ""),
                "poster": String(s.poster ?? ""), "lib": "stream", "source": "stream",
                "watched": 0, "total": 0, "last_played": Number(s.updated_at ?? 0),
                "next": { "reason": s.watched ? "next" : "resume", "code": code, "label": code,
                          "position": s.watched ? 0 : Number(s.position ?? 0), "duration": Number(s.duration ?? 0) },
                "stream": s
            });
        }
        return out;
    }

    /// Resume where you left off, or play the next episode. Leaves mpv running on its own.
    function continueTitle(id: string): void {
        if (playbackProc.running)
            return;
        root.playbackBusy = true;
        root.playbackMessage = "Starting playback…";
        root.playbackError = "";
        playbackProc.command = root._localCommand("continue", [id, "--rewatch"]);
        playbackProc.running = true;
    }

    function playPath(id: string, path: string): void {
        if (playbackProc.running)
            return;
        root.playbackBusy = true;
        root.playbackMessage = "Starting playback…";
        root.playbackError = "";
        playbackProc.command = root._localCommand("play", [id, "--path", path, "--resume"]);
        playbackProc.running = true;
    }

    /// Mark one episode watched or unwatched, then reload what the detail view shows.
    function setWatched(id: string, code: string, watched: bool): void {
        root.mark([root.binary, watched ? "watched" : "unwatched", id, "--from", code, "--to", code]);
    }

    /// A movie has one file: mark the whole title.
    function setWatchedAll(id: string, watched: bool): void {
        root.mark([root.binary, watched ? "watched" : "unwatched", id]);
    }

    // Marks run one after another: a busy Process keeps only the newest command it is given,
    // so ticking three episodes quickly would lose the middle one.
    property var markQueue: []

    function mark(command: var): void {
        root.markQueue = root.markQueue.concat([command]);
        if (!markProc.running)
            root.nextMark();
    }

    function nextMark(): void {
        if (root.markQueue.length === 0)
            return;
        markProc.command = root.markQueue[0];
        root.markQueue = root.markQueue.slice(1);
        markProc.running = true;
    }

    // ── the live companion (mediator daemon) ──
    /// Windows that want live updates hold a reference; the socket closes when none does.
    property int holders: 0
    readonly property bool wanted: root.holders > 0
    property bool linked: false
    /// Every mpv mediator started: [{title, label, position, duration, paused, ...}]
    property var nowPlaying: []
    readonly property var now: root.nowPlaying.length > 0 ? root.nowPlaying[0] : null
    /// Background fetch of posters, summaries, banners and episode names
    property var enrich: ({ running: false, done: 0, total: 0, current: "", errors: 0 })
    readonly property string sockPath: `${Quickshell.env("XDG_RUNTIME_DIR")}/mediator-daemon.sock`
    property bool enrichRequested: false
    property bool refreshStale: false

    function retain(): void {
        root.holders++;
    }

    function release(): void {
        root.holders = Math.max(0, root.holders - 1);
    }

    /// Playback mediator started outside the shell (the CLI, another launcher) has no worker to hold
    /// the daemon connection: while the daemon's own MPRIS player exists, hold it so the pill and
    /// island learn about the session
    property bool mprisHold: false
    readonly property bool mediatorPlayerPresent: (MprisController.allPlayers ?? []).some(p => root._isMediatorMprisPlayer(p))
    onMediatorPlayerPresentChanged: {
        if (root.mediatorPlayerPresent && !root.mprisHold) {
            root.mprisHold = true;
            root.retain();
        } else if (!root.mediatorPlayerPresent && root.mprisHold) {
            root.mprisHold = false;
            root.release();
        }
    }

    function send(msg: var): void {
        if (!root.linked)
            return;
        sock.write(JSON.stringify(msg) + "\n");
        sock.flush();
    }

    /// pause/play/toggle, seek (+value seconds), seek_to, next, prev, stop, speed, volume
    function control(action: string, value: var): void {
        root.send({ cmd: "control", action: action, value: value });
    }

    /// Switch the running local/Jellyfin session to another episode of the same title
    function playLocalEpisode(path: string): void {
        root.send({ cmd: "control", action: "play_path", path: path, pid: Number(root.localSession?.pid ?? 0) });
    }

    /// scope: "missing" (what has no info yet), "all", or one title id
    /// `auto`: the app asked on its own (not a page that needs the lookup), so the "fetch
    /// missing posters automatically" setting can turn it off
    function startEnrich(scope: string, refresh: bool, auto: bool): void {
        root.send({ cmd: "enrich", scope: scope, refresh: refresh, auto: Boolean(auto) });
    }

    function stopEnrich(): void {
        root.send({ cmd: "enrich_stop" });
    }

    function _applyEvent(msg: var): void {
        if (msg.event === "now") {
            root.nowPlaying = msg.sessions;
            const live = root.nativeNow ?? root.nowPlaying.find(session => String(session?.title_id ?? "").startsWith("online/"));
            const ref = live?.native;
            if (ref && String(ref.episode_id ?? "") !== "") {
                // The daemon read this episode from the worker's own state file, so a reload now
                // sees it: compare ids, not paths.
                const key = `${ref.show_id}|${ref.episode_id}`;
                if (key !== root.nativeSeenPath) {
                    if (root.nativeSeenPath !== "")
                        nativeEpisodeReload.restart();
                    root.nativeSeenPath = key;
                }
            } else {
                // An older daemon without `native`: fall back to noticing the path change
                const path = String(live?.path ?? "");
                if (path !== "" && path !== root.nativeSeenPath) {
                    if (root.nativeSeenPath !== "")
                        nativeEpisodeReload.restart();
                    root.nativeSeenPath = path;
                }
            }
        } else if (msg.event === "step") {
            root.stepNativeEpisode(Number(msg.dir) < 0 ? -1 : 1);
        } else if (msg.event === "enrich") {
            root.enrich = msg;
        } else if (msg.event === "changed") {
            root.refresh();
            root.reloadDetail();
        } else if (msg.event === "info") {
            if (msg.id === root.detailId)
                root.reloadDetail();
        }
    }

    onWantedChanged: {
        if (root.wanted) {
            ensureProc.running = true;
            // Titles added since the shell started (a finished download) get their poster and info
            if (sock.connected && !root.enrich.running)
                root.startEnrich("missing", false, true);
        } else {
            retry.stop();
            sock.connected = false;
        }
    }

    Process {
        id: ensureProc
        command: [root.binary, "daemon", "start"]
        onExited: if (root.wanted) sock.connected = true
    }

    Socket {
        id: sock
        path: root.sockPath
        connected: false
        parser: SplitParser {
            onRead: line => {
                try {
                    root._applyEvent(JSON.parse(line));
                } catch (e) {}
            }
        }
        onConnectedChanged: {
            root.linked = sock.connected;
            if (sock.connected) {
                sock.write(JSON.stringify({ cmd: "subscribe" }) + "\n");
                sock.flush();
                // Once per shell session: fill in whatever has no info yet. Cheap when there is nothing to do.
                if (!root.enrichRequested) {
                    root.enrichRequested = true;
                    root.startEnrich("missing", false, true);
                }
            } else {
                root.nowPlaying = [];
                if (root.wanted)
                    retry.restart();
            }
        }
        // A failed connect never flips `connected`, so it has to be retried from here
        onError: if (root.wanted) retry.restart()
    }

    Timer {
        id: retry
        interval: 2000
        onTriggered: if (root.wanted && !root.linked) {
            sock.connected = false;
            ensureProc.running = true;
        }
    }

    Process {
        id: metaProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    if (r.id === root.detailId && r.meta && !r.meta.error && root.detail)
                        root.detail = Object.assign({}, root.detail, { meta: r.meta });
                } catch (e) {}
            }
        }
    }

    Process {
        id: listProc
        command: [root.binary, "list", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.titles = JSON.parse(text);
                    root.error = "";
                    root.loaded = true;
                } catch (e) {
                    root.error = text.trim() || "mediator list returned nothing";
                }
                root.loading = false;
            }
        }
        onExited: (code, status) => {
            if (code !== 0) {
                root.error = `mediator exited with ${code}`;
                root.loading = false;
            }
            if (root.refreshStale)
                root.refresh();
        }
    }

    Process {
        id: historyProc
        command: [root.binary, "history", "-n", "14", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.recent = JSON.parse(text);
                } catch (e) {
                    root.recent = [];
                }
            }
        }
    }

    Process {
        id: detailProc
        property string requestedId: ""
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text);
                    if (d.id === root.detailId) {
                        root.detail = d;
                        // Nothing cached yet: ask the sources, the page fills in when they answer
                        if (!d.meta) {
                            metaProc.command = [root.binary, "meta", d.id];
                            metaProc.running = true;
                        }
                    }
                } catch (e) {
                    root.error = "could not read the episode list";
                }
            }
        }
        onExited: {
            // The page moved on, or something changed, while this one was reading
            if (root.detailStale || (root.detailId !== "" && root.detailId !== detailProc.requestedId))
                root.fetchDetail();
        }
    }

    Process {
        id: probeProc
        onExited: {
            const id = root.probingId;
            root.probingId = "";
            if (id !== "" && id === root.detailId)
                root.reloadDetail();
        }
    }

    Process {
        id: markProc
        onExited: {
            if (root.markQueue.length > 0) {
                root.nextMark();
                return;
            }
            root.reloadDetail();
            root.refresh();
        }
    }

    Process {
        id: settingsProc
        command: [root.binary, "config", "show", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.settings = JSON.parse(text);
                } catch (e) {
                    root.error = "could not read the settings";
                }
            }
        }
    }

    Process {
        id: saveProc
        property var pendingPatch: ({})
        command: [root.binary, "config", "set", "--json"]
        stderr: StdioCollector {
            id: saveErr
        }
        onExited: (code, status) => {
            root.saving = false;
            if (code !== 0) {
                root.saveError = saveErr.text.trim().replace(/^mediator: /, "") || "could not save";
                return;
            }
            root.loadSettings();
            const keys = Object.keys(saveProc.pendingPatch);
            if (keys.some(k => k.startsWith("jellyfin.")))
                root.testJellyfin();
            if (keys.some(k => k.startsWith("anilist.")))
                Qt.callLater(root.loadAniListStatus);
            root.refresh();
        }
    }

    Process {
        id: jellyfinProc
        command: [root.binary, "jellyfin", "status", "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const r = JSON.parse(text);
                    root.jellyfinState = r.ok ? "ok" : "failed";
                    root.jellyfinMessage = r.ok ? `${r.server} ${r.version} · ${r.libraries.map(l => l.name).join(", ")}` : r.error;
                } catch (e) {
                    root.jellyfinState = "failed";
                    root.jellyfinMessage = "no answer from mediator";
                }
            }
        }
    }

    Process {
        id: anilistProc
        property string stdinPayload: ""
        property string replyText: ""
        property string errorText: ""
        stdinEnabled: false

        onRunningChanged: {
            if (!running)
                return;
            replyText = "";
            errorText = "";
            if (stdinPayload !== "") {
                write(stdinPayload + "\n");
                // Closing stdin makes `--token-stdin` finish reading. The payload is cleared
                // before the process can be inspected so it cannot appear in later commands.
                stdinPayload = "";
            }
            stdinEnabled = false;
        }

        stdout: StdioCollector {
            onStreamFinished: anilistProc.replyText = text
        }
        stderr: StdioCollector {
            onStreamFinished: anilistProc.errorText = text
        }
        onExited: (code, status) => {
            const finishedAction = root.anilistAction;
            root.anilistBusy = false;
            root._finishAniList(anilistProc.replyText, anilistProc.errorText, code);
            if (root.anilistAction === finishedAction)
                root.anilistAction = "";
        }
    }

    Process {
        id: playbackProc
        property string errorText: ""
        stderr: StdioCollector {
            onStreamFinished: playbackProc.errorText = text
        }
        onExited: (code, status) => {
            root.playbackBusy = false;
            if (code === 0) {
                root.playbackError = "";
                root.playbackMessage = "Playback finished.";
            } else {
                root.playbackMessage = "";
                root.playbackError = playbackProc.errorText.trim().replace(/^mediator:\s*/, "")
                    || `Playback could not start (exit ${code}).`;
            }
        }
    }

    Process {
        id: providerSearchProc
        property int requestId: 0
        property string replyText: ""
        property string errorText: ""
        stdout: StdioCollector {
            onStreamFinished: providerSearchProc.replyText = text
        }
        stderr: StdioCollector {
            onStreamFinished: providerSearchProc.errorText = text
        }
        onExited: (code, status) => {
            root.providerSearchBusy = false;
            if (requestId !== root.providerSearchRequest)
                return;
            let parsed = null;
            try {
                parsed = JSON.parse(String(replyText ?? "").trim());
            } catch (e) {}
            if (code !== 0 || !parsed?.ok) {
                root.providerSearchResults = [];
                root.providerSearchError = String(parsed?.error || errorText || "Provider search failed.")
                    .trim().replace(/^mediator:\s*/, "");
                return;
            }
            root.providerSearchResults = Array.isArray(parsed.results) ? parsed.results : [];
            if (root.providerSearchResults.length === 0)
                root.providerSearchError = "No anime matched that search.";
        }
    }

    Process {
        id: providerEpisodesProc
        property int requestId: 0
        property string replyText: ""
        property string errorText: ""
        stdout: StdioCollector {
            onStreamFinished: providerEpisodesProc.replyText = text
        }
        stderr: StdioCollector {
            onStreamFinished: providerEpisodesProc.errorText = text
        }
        onExited: (code, status) => {
            root.providerEpisodesBusy = false;
            if (requestId !== root.providerEpisodesRequest)
                return;
            let parsed = null;
            try {
                parsed = JSON.parse(String(replyText ?? "").trim());
            } catch (e) {}
            if (code !== 0 || !parsed?.ok) {
                root.providerEpisodes = [];
                root.providerEpisodesError = String(parsed?.error || errorText || "Could not load episodes.")
                    .trim().replace(/^mediator:\s*/, "");
                return;
            }
            root.providerEpisodes = Array.isArray(parsed.episodes) ? parsed.episodes : [];
            if (root.providerEpisodes.length === 0)
                root.providerEpisodesError = "No episodes are available for this anime.";
        }
    }

    Timer {
        id: nativeStopWatchdog
        interval: 8000
        onTriggered: {
            if (!root.nativePendingLaunch)
                return;
            root.nativePendingLaunch = null;
            root.streamResolving = false;
            root.streamError = "The player did not close. Close mpv, then try again.";
        }
    }

    Process {
        id: roomGotoProc
    }

    Process {
        id: nativeStopProc
        stderr: StdioCollector { id: nativeStopError }
        onExited: (code, status) => {
            if (code !== 0 && root.nativePendingLaunch) {
                nativeStopWatchdog.stop();
                root.nativePendingLaunch = null;
                root.streamResolving = false;
                root.streamError = nativeStopError.text.trim() || "Could not close the current player. Try again.";
            }
        }
    }

    Process {
        id: nativeControlProc
        stdout: StdioCollector { id: nativeControlReply }
        onExited: (code, status) => {
            if (code !== 0) {
                let reply = null;
                try { reply = JSON.parse(nativeControlReply.text); } catch (e) {}
                root.streamError = reply?.error || "The native player is no longer available.";
            }
        }
    }

    Process {
        id: nativeStateProc
        property int requestGeneration: 0
        property string replyText: ""
        property string errorText: ""
        stdout: StdioCollector {
            onStreamFinished: nativeStateProc.replyText = text
        }
        stderr: StdioCollector {
            onStreamFinished: nativeStateProc.errorText = text
        }
        onExited: (code, status) => {
            root.nativeStateBusy = false;
            if (root.nativeStateReloadQueued) {
                root.nativeStateReloadQueued = false;
                Qt.callLater(root.loadNativeState);
            }
            if (requestGeneration !== root.nativeLaunchGeneration)
                return;
            let parsed = null;
            try {
                parsed = JSON.parse(String(replyText ?? "").trim());
            } catch (e) {}
            if (code !== 0 || !parsed?.ok) {
                root.nativeStateError = String(parsed?.error || errorText
                    || "Could not read saved anime playback.").trim().replace(/^mediator:\s*/, "");
                return;
            }
            root.nativeStateError = "";
            root.nativeState = parsed.state && typeof parsed.state === "object"
                ? parsed.state : ({});
        }
    }

    Process {
        id: imageCacheProc
        property var batch: []
        property string replyText: ""
        stdout: StdioCollector {
            onStreamFinished: imageCacheProc.replyText = text
        }
        stderr: StdioCollector { }
        onExited: (code, status) => {
            let parsed = null;
            try {
                parsed = JSON.parse(String(replyText ?? "").trim());
            } catch (e) {}
            const images = parsed && parsed.images && typeof parsed.images === "object"
                ? parsed.images : ({});
            const next = Object.assign({}, root.imageCache);
            for (const url in images) {
                const path = String(images[url] ?? "").trim();
                if (path !== "")
                    next[url] = path.startsWith("file:") ? path : `file://${path}`;
            }
            root.imageCache = next;
            imageCacheProc.batch = [];
            if (root.imageCachePending.length > 0)
                Qt.callLater(root._drainImageCache);
        }
    }

    Process {
        id: streamHistoryProc
        property string replyText: ""
        property string errorText: ""
        stdout: StdioCollector {
            onStreamFinished: streamHistoryProc.replyText = text
        }
        stderr: StdioCollector {
            onStreamFinished: streamHistoryProc.errorText = text
        }
        onExited: (code, status) => {
            root.streamHistoryBusy = false;
            let parsed = null;
            try {
                parsed = JSON.parse(String(replyText ?? "").trim());
            } catch (e) {}
            if (code === 0 && parsed?.ok) {
                root.streamHistory = Array.isArray(parsed.recent) ? parsed.recent : [];
                root.streamHistoryError = "";
            } else {
                root.streamHistory = [];
                root.streamHistoryError = String(parsed?.error || errorText
                    || "Could not read streaming history.").trim().replace(/^mediator:\s*/, "");
            }
            if (root.streamHistoryReloadQueued) {
                root.streamHistoryReloadQueued = false;
                Qt.callLater(root.loadStreamHistory);
            }
        }
    }

    Process {
        id: anilistWatchingProc
        property string replyText: ""
        property string errorText: ""
        stdout: StdioCollector {
            onStreamFinished: anilistWatchingProc.replyText = text
        }
        stderr: StdioCollector {
            onStreamFinished: anilistWatchingProc.errorText = text
        }
        onExited: (code, status) => {
            root.anilistWatchingBusy = false;
            let parsed = null;
            try {
                parsed = JSON.parse(String(replyText ?? "").trim());
            } catch (e) {}
            if (code === 0 && parsed?.ok) {
                root.anilistWatching = Array.isArray(parsed.entries) ? parsed.entries : [];
                root.anilistWatchingError = "";
            } else {
                root.anilistWatching = [];
                root.anilistWatchingError = String(parsed?.error || errorText
                    || "Could not read the AniList queue.").trim().replace(/^mediator:\s*/, "");
            }
        }
    }

    Process {
        id: providerPlayProc
        property bool hasStarted: false
        property int generation: 0
        property string errorText: ""
        property string replyError: ""
        stdout: SplitParser {
            onRead: line => {
                let parsed = null;
                try {
                    parsed = JSON.parse(String(line).trim());
                } catch (e) {}
                if (parsed?.error)
                    providerPlayProc.replyError = String(parsed.error);
                if (parsed?.started && !providerPlayProc.hasStarted) {
                    providerPlayProc.hasStarted = true;
                    root.nativePlayerPid = Number(parsed.pid ?? 0);
                    root.nativeWorkerActive = true;
                    root.streamResolving = false;
                    root.streamMessage = "Playing anime stream…";
                    root.streamError = "";
                    root.loadNativeState();
                    root.loadStreamHistory();
                    root.providerStreamStarted();
                }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: providerPlayProc.errorText = text
        }
        onExited: (code, status) => {
            const detail = (providerPlayProc.errorText.trim()
                || providerPlayProc.replyError).replace(/^mediator:\s*/, "");
            const pending = root.nativePendingLaunch;
            const started = providerPlayProc.hasStarted;
            const waitingForMpris = pending && root.nativeMprisPlayer !== null;
            if (!waitingForMpris)
                nativeStopWatchdog.stop();
            root.nativePlayerPid = 0;
            root.nativeWorkerActive = false;
            root.nativeSeenPath = "";
            if (root.nativeDaemonHold) {
                root.nativeDaemonHold = false;
                root.release();
            }
            root.providerPendingShowId = "";
            root.providerPendingEpisodeId = "";
            if (pending) {
                root.streamBusy = true;
                root.streamResolving = true;
                if (!waitingForMpris) {
                    // The exact MPRIS player is gone, so the queued identity can be
                    // resolved now. If it is still present, _nativeMprisGone owns
                    // this handoff and the watchdog remains active.
                    root.nativePendingLaunch = null;
                    Qt.callLater(() => root._launchProviderEpisode(pending));
                }
                return;
            }
            root.streamBusy = false;
            root.streamResolving = false;
            root.loadNativeState();
            root.loadStreamHistory();
            if (root.anilistStatus?.configured)
                root.loadAniListWatching();
            if (code === 0 && started) {
                root.streamError = "";
                root.streamMessage = "Continue watching is ready.";
            } else {
                root.streamMessage = "";
                root.streamError = detail || `Could not start anime stream (exit ${code}).`;
            }
        }
    }

    /**
     * If the shell reloads, the provider worker (and its IPC loop) can die while mpv
     * survives. MPRIS still knows the position, so persist it here instead of adding
     * another tracker. Normal playback keeps writing through the worker; this only
     * covers the adopted-player case.
     */
    Process {
        id: nativeCheckpointProc
        stdout: StdioCollector { }
        stderr: StdioCollector { }
    }

    Timer {
        id: nativeCheckpointTimer
        interval: 10000
        repeat: true
        running: root.nativeActive && !root.nativeWorkerActive && root.nativeHasState
            && !root.streamResolving && root.nativeDuration > 0
        onTriggered: {
            if (nativeCheckpointProc.running)
                return;
            const state = root.nativeState;
            const showId = String(state?.show_id ?? "").trim();
            const episodeId = String(state?.episode_id ?? "").trim();
            if (showId === "" || episodeId === "")
                return;
            nativeCheckpointProc.command = [root.binary, "stream-checkpoint",
                showId, episodeId,
                "--position", String(root.nativePosition),
                "--duration", String(root.nativeDuration),
                "--json"];
            nativeCheckpointProc.running = true;
        }
    }

    Process {
        id: posterProc
        stderr: StdioCollector {
            id: posterErr
        }
        onExited: (code, status) => {
            root.posterBusy = false;
            if (code === 0) {
                root.posterVersion++;
                root.posterMessage = "Poster updated";
                root.refresh();
            } else {
                root.posterMessage = posterErr.text.trim().replace(/^mediator: /, "") || "Could not set the poster";
            }
        }
    }
}

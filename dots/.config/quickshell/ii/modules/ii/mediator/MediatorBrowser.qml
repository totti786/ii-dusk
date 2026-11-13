pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The mediator browser body shared by the overlay and the window: search, a "continue
 * watching" row, then a poster grid. Opening a title swaps the grid for
 * TitleDetail. The search field keeps focus the whole time and every key is routed from it,
 * so typing always filters and the arrows always move.
 */
FocusScope {
    id: root

    signal closeRequested()
    signal windowRequested()

    /// The room lives in an ordinary window, which would open behind the full-screen overlay,
    /// so the overlay steps aside first. Watch Together stays on; reopen Mediator any time.
    function openRoom(): void {
        if (root.overlay)
            GlobalStates.mediatorAppOpen = false;
        GlobalStates.openSyncplayApp();
    }

    /// Overlay: tab pills, gear and a hero billboard live in the header. Window: the rail owns
    /// tabs and settings, so the header is just search and count.
    property bool overlay: true

    readonly property var tabs: [
        { key: "", label: "All", icon: "grid_view" },
        { key: "anime", label: "Anime", icon: "animation" },
        { key: "shows", label: "Shows", icon: "tv" },
        { key: "movies", label: "Movies", icon: "movie" },
        { key: "stream", label: "Streaming", icon: "live_tv" }
    ]
    property string tab: ""
    /// Online mode covers both the anime provider search and the Stremio catalog.
    property bool streaming: false
    /// Movies & shows are the default; anime is one click (or Ctrl+Up) away
    property string onlineKind: "stremio"
    readonly property bool stremio: root.streaming && root.onlineKind === "stremio"
    readonly property string tabKey: root.streaming ? "stream" : root.tab
    property string query: ""
    property int cur: 0
    /// Which part the arrow keys drive: the hero's Resume button, the "up next" row, or the grid.
    property string zone: "grid"
    onZoneChanged: if (root.zone === "row") root.scrollToTop()
    property int resumeCur: 0
    /// Until the cursor is moved by hand it rests on the carousel, the first thing on the page
    property bool zoneChosen: false
    onRowItemsChanged: if (!root.zoneChosen && root.rowItems.length > 0) root.zone = "row"
    property bool settingsOpen: false
    property bool streamOpen: false
    property string streamInitialQuery: ""
    property bool streamAutoSearch: false
    property int streamAniListId: 0
    property int streamAniListSeason: 0
    property int streamAniListTotal: 0

    readonly property var localItems: {
        if (root.streaming)
            return [];
        // Words, not a literal run: punctuation and apostrophes do not matter, and order does not either
        const words = root.fold(root.query).split(" ").filter(w => w !== "");
        return MediatorService.titles.filter(t => {
            if (root.tab !== "" && t.lib !== root.tab)
                return false;
            if (words.length === 0)
                return true;
            const hay = root.fold(t.display ?? "") + " " + root.fold(t.name ?? "");
            return words.every(w => hay.includes(w));
        });
    }
    function fold(text): string {
        return MediatorService.normTitle(String(text ?? "").normalize("NFD").replace(/[\u0300-\u036f]/g, "").replace(/['’`]/g, ""));
    }
    /// On the All tab a search also asks the online sources; what the library already holds is left out
    readonly property var onlineItems: {
        const have = new Set(root.localItems.map(t => root.fold(t.name ?? t.display)));
        return onlineSearch.results.filter(r => !have.has(root.fold(r.name)));
    }
    readonly property var items: root.localItems.concat(root.onlineItems)
    readonly property var resumeRow: root.query === "" && root.tab === "" && !root.settingsOpen
        && !root.streaming
        ? root.continueItems : []
    readonly property var heroTitle: null  // the carousel replaced the big banner
    readonly property var rowItems: root.heroTitle ? root.resumeRow.slice(1) : root.resumeRow
    readonly property bool inDetail: MediatorService.detailId !== ""
    readonly property var detailTitle: MediatorService.titleById(MediatorService.detailId)

    // Publish both histories together, so a late source cannot rearrange a visible row.
    readonly property var continueItems: MediatorService.continueSnapshot
    property bool continueLoaded: MediatorService.continueSnapshotReady
    property bool continueBusy: false
    property bool continueQueued: false
    property string continueError: ""
    property var continueLocalResult: []
    property var continueStreamResult: []
    property bool continueLocalDone: false
    property bool continueStreamDone: false
    property bool continueLocalOk: false
    property bool continueStreamOk: false

    function refreshContinue(): void {
        if (root.continueBusy) { root.continueQueued = true; return; }
        root.continueBusy = true;
        root.continueLocalDone = false;
        root.continueStreamDone = false;
        root.continueLocalOk = false;
        root.continueStreamOk = false;
        continueLocal.output = "";
        continueStream.output = "";
        continueLocal.running = true;
        continueStream.running = true;
    }

    function finishContinue(): void {
        if (!root.continueLocalDone || !root.continueStreamDone) return;
        const local = root.continueLocalOk ? root.continueLocalResult.filter(t => t.next && t.watched < t.total) : [];
        const streamed = root.continueStreamOk ? MediatorService.streamResumeItems(root.continueStreamResult) : [];
        if (root.continueLocalOk && root.continueStreamOk) {
            MediatorService.saveContinueSnapshot(root.mergeResume(local, streamed));
        } else if (!MediatorService.continueSnapshotReady) {
            // Keep the successful source useful on a first load when no snapshot exists.
            MediatorService.continueSnapshot = root.mergeResume(local, streamed);
        }
        root.continueError = root.continueLocalOk && root.continueStreamOk ? "" : Translation.tr("Some watch history could not be loaded.");
        root.continueLoaded = true;
        root.continueBusy = false;
        if (root.continueQueued) { root.continueQueued = false; continueRefresh.restart(); }
    }

    Timer { id: continueRefresh; interval: 200; onTriggered: root.refreshContinue() }
    Connections {
        target: MediatorService
        function onRecentChanged() { continueRefresh.restart(); }
        function onStreamHistoryChanged() { continueRefresh.restart(); }
    }
    Process {
        id: continueLocal
        property string output: ""
        command: ["timeout", "15s", MediatorService.binary, "history", "-n", "14", "--json"]
        stdout: StdioCollector { onStreamFinished: continueLocal.output = text }
        onExited: code => {
            try { const data = JSON.parse(output); root.continueLocalOk = code === 0 && Array.isArray(data); root.continueLocalResult = data; }
            catch (e) { root.continueLocalOk = false; }
            root.continueLocalDone = true;
            root.finishContinue();
        }
    }
    Process {
        id: continueStream
        property string output: ""
        command: ["timeout", "15s", MediatorService.binary, "stream-state", "--all", "--shows", "--json"]
        stdout: StdioCollector { onStreamFinished: continueStream.output = text }
        onExited: code => {
            try { const data = JSON.parse(output); root.continueStreamOk = code === 0 && data.ok && Array.isArray(data.recent); root.continueStreamResult = data.recent; }
            catch (e) { root.continueStreamOk = false; }
            root.continueStreamDone = true;
            root.finishContinue();
        }
    }

    /// Library and streamed titles in one row, newest first. A show held both ways appears once, as
    /// whichever copy was played last.
    function mergeResume(local, streamed): var {
        const all = local.concat(streamed).sort((a, b) => Number(b.last_played ?? 0) - Number(a.last_played ?? 0));
        const seen = ({});
        const out = [];
        for (const t of all) {
            const key = MediatorService.normTitle(t.name);
            const kind = t.stream ? "stream" : "local";
            if (key !== "" && seen[key] !== undefined && seen[key] !== kind)
                continue;
            seen[key] = kind;
            out.push(t);
            if (out.length === 9)
                break;
        }
        return out;
    }

    /// A title found online from the All tab opens its page in the Streaming tab
    function openOnlineTitle(t): void {
        root.onlineKind = t.stremio ? "stremio" : "anime";
        root.setTab("stream");
        if (t.stremio)
            StremioService.openTitle(t.stremio);
        else
            AnimeBrowseService.openTitle(t.anime);
    }

    function openTitle(t): void {
        if (t.online) {
            root.openOnlineTitle(t);
            return;
        }
        if (t.stream) {
            root.openStreamTitle(t.stream);
            return;
        }
        MediatorService.loadDetail(t.id);
    }

    /// A streamed title in the library's row opens its page in the Streaming tab
    function openStreamTitle(state): void {
        const stremio = String(state.show_id).startsWith("stremio:");
        root.onlineKind = stremio ? "stremio" : "anime";
        root.setTab("stream");
        if (stremio) {
            const parts = String(state.show_id).split(":");  // stremio:series:tt0903747
            StremioService.openTitle({ "id": parts[2], "type": parts[1], "name": String(state.title ?? ""),
                "year": "", "poster": String(state.poster ?? "") });
        } else {
            AnimeBrowseService.openQueued(String(state.title ?? ""), Number(state.anilist_id ?? 0), 1,
                Number(state.total ?? 0));
        }
    }

    function play(t): void {
        if (t.online) {
            root.openOnlineTitle(t);
            return;
        }
        if (t.stream)
            MediatorService.resumeStream(t.stream);
        else
            MediatorService.continueTitle(t.id);
        // The overlay grabs the keyboard, so it gets out of mpv's way; the window stays and shows what plays
        if (root.overlay)
            root.closeRequested();
    }

    function openSettings(): void {
        MediatorService.clearDetail();
        root.streamOpen = false;
        root.settingsOpen = true;
    }

    function closeSettings(): void {
        root.settingsOpen = false;
        search.forceActiveFocus();
    }

    function openStream(query = "", anilistId = 0, season = 0, total = 0): void {
        root.streamInitialQuery = String(query ?? "").trim();
        root.streamAutoSearch = root.streamInitialQuery !== "";
        root.streamAniListId = Number(anilistId ?? 0);
        root.streamAniListSeason = Number(season ?? 0);
        root.streamAniListTotal = Number(total ?? 0);
        root.streamOpen = true;
    }

    function closeStream(): void {
        root.streamOpen = false;
        root.streamInitialQuery = "";
        root.streamAutoSearch = false;
        root.streamAniListId = 0;
        root.streamAniListSeason = 0;
        root.streamAniListTotal = 0;
        search.forceActiveFocus();
    }

    function setTab(key): void {
        root.settingsOpen = false;
        root.streamOpen = false;
        if (key === "stream" || key === "stremio") {
            const wasStreaming = root.streaming;
            // "stream" keeps whichever sub-tab was last open; "stremio" jumps to movies & shows
            if (key === "stremio")
                root.onlineKind = "stremio";
            root.streaming = true;
            root.tab = "";
            root.cur = 0;
            root.zone = "grid";
            root.query = "";
            if (search.text !== "")
                search.text = "";
            MediatorService.clearDetail();
            if (wasStreaming && !root.stremio)
                MediatorService.loadStreaming();
            search.forceActiveFocus();
            return;
        }
        root.streaming = false;
        root.tab = key === "all" ? "" : key;
        root.cur = 0;
        // The library and its Continue row are read on open only when the app lands on a library tab;
        // arriving from Streaming they would still be empty, leaving just the streamed titles
        if (!MediatorService.loaded || MediatorService.recent.length === 0)
            MediatorService.refresh();
        MediatorService.loadStreamHistory();
    }

    /// Leave Streaming for the library's own page of a title
    function openLocal(id): void {
        root.setTab("");
        MediatorService.loadDetail(id);
    }

    /// Anime or movies and shows; the search box keeps focus so typing carries on
    function setKind(kind): void {
        root.onlineKind = kind;
        search.forceActiveFocus();
    }

    function stepTab(delta): void {
        const i = root.tabs.findIndex(t => t.key === root.tabKey);
        root.setTab(root.tabs[(i + delta + root.tabs.length) % root.tabs.length].key);
    }

    /// Back to the top of the page, where the carousel is (the grid's own margin leaves room for it)
    function scrollToTop(): void {
        grid.contentY = grid.originY - grid.topMargin;
    }

    /// The streaming tab's cursor: the "continue watching" cards sit above the browse covers.
    property bool streamContinue: false

    /// The continue cards are at the top of the page, so entering them scrolls back up
    function _enterContinue(): void {
        root.streamContinue = true;
        pageLoader.item?.scrollTop?.();
    }

    function _leaveContinue(): void {
        root.streamContinue = false;
        continueRow.cursor = -1;
    }

    /// True when the arrow was used. The page order is: continue row, billboard, covers.
    function streamMove(page, dx, dy): bool {
        // A title page or stream list takes the arrows itself; the continue row steps aside
        if (page?.ownsKeys === true) {
            root._leaveContinue();
            return page.moveCursor(dx, dy);
        }
        const n = continueRow.visible ? continueRow.entries.length : 0;
        if (root.streamContinue) {
            if (dy < 0) {
                root._leaveContinue();
            } else if (dy > 0) {
                root._leaveContinue();
                if (page)
                    page.moveCursor(0, 1);
            } else if (dx !== 0) {
                continueRow.moveCursor(continueRow.cursor + dx);
            }
            return true;
        }
        if (!page)
            return false;
        if (page.heroFocus === true) {
            // The billboard: up goes on to the continue row, the rest is the page's
            if (dy < 0 && n > 0) {
                page.moveCursor(0, -1);
                root._enterContinue();
                continueRow.moveCursor(0);
                return true;
            }
            return page.moveCursor(dx, dy);
        }
        if (dy < 0 && page.cursor >= 0) {
            page.moveCursor(0, -1);
            // Off the top row of covers: up into the billboard, or the continue cards without one
            if (page.cursor < 0 && page.heroFocus !== true && n > 0) {
                root._enterContinue();
                continueRow.moveCursor(0);
            }
            return true;
        }
        if (dy > 0 && page.cursor < 0 && n > 0) {
            root._enterContinue();
            continueRow.moveCursor(0);
            return true;
        }
        return page.moveCursor(dx, dy);
    }

    function zonesList(): var {
        const out = [];
        if (root.heroTitle)
            out.push("hero");
        if (root.rowItems.length > 0)
            out.push("row");
        out.push("grid");
        return out;
    }

    function setZone(z): void {
        root.zoneChosen = true;
        root.zone = z;
    }

    function moveCursor(dx, dy): void {
        const zones = root.zonesList();
        if (!zones.includes(root.zone))
            root.zone = "grid";
        const zi = zones.indexOf(root.zone);
        if (root.zone === "hero") {
            if (dy > 0)
                root.setZone(zones[zi + 1]);
            return;
        }
        if (root.zone === "row") {
            if (dy !== 0) {
                root.setZone(zones[Math.max(0, Math.min(zones.length - 1, zi + dy))]);
                return;
            }
            const n = root.rowItems.length;
            // The carousel wraps once there are enough cards to fill both sides
            root.resumeCur = n >= 5 ? (root.resumeCur + dx + n) % n : Math.max(0, Math.min(n - 1, root.resumeCur + dx));
            return;
        }
        if (root.items.length === 0)
            return;
        const cols = grid.columns;
        if (dy < 0 && root.cur < cols && zi > 0) {
            root.setZone(zones[zi - 1]);
            return;
        }
        let n = root.cur + dx + dy * cols;
        // Down past the last short row lands on the last card
        if (dy > 0 && n >= root.items.length && root.cur < root.items.length - 1)
            n = root.items.length - 1;
        root.cur = Math.max(0, Math.min(root.items.length - 1, n));
        grid.positionViewAtIndex(root.cur, GridView.Contain);
    }

    function jump(n): void {
        root.zoneChosen = true;
        root.zone = "grid";
        if (root.items.length === 0)
            return;
        root.cur = Math.max(0, Math.min(root.items.length - 1, n));
        grid.positionViewAtIndex(root.cur, GridView.Contain);
    }

    function surprise(): void {
        if (root.items.length > 0)
            root.jump(Math.floor(Math.random() * root.items.length));
    }

    /// The title the cursor is on, wherever the cursor is.
    function focusedTitle(): var {
        if (root.zone === "hero")
            return root.heroTitle;
        if (root.zone === "row")
            return root.rowItems[root.resumeCur] ?? null;
        return root.items[root.cur] ?? null;
    }

    onStreamingChanged: root._leaveContinue()

    onOnlineKindChanged: {
        root._leaveContinue();
        if (!root.streaming)
            return;
        if (root.stremio)
            StremioService.loadHistory();
        else
            MediatorService.loadStreaming();
    }

    onQueryChanged: {
        root.cur = 0;
        root.zoneChosen = true;
        root.zone = "grid";
    }

    Component.onCompleted: {
        MediatorService.retain();
        root.refreshContinue();
        MediatorService.loadSettings();
        let pending = GlobalStates.mediatorPendingTab;
        GlobalStates.mediatorPendingTab = "";
        // A plain open (no tab or title asked for) picks up where it was left
        const last = GlobalStates.mediatorLast;
        const resume = last !== null && last !== undefined && pending === "all" && GlobalStates.mediatorPendingTitle === "";
        if (resume)
            pending = last.tab === "" ? "all" : last.tab;
        if (pending === "stream" || pending === "stremio") {
            MediatorService.refresh();
            root.setTab(pending);
        }
        else {
            root.tab = pending === "all" ? "" : pending;
            MediatorService.clearDetail();
            MediatorService.refresh();
            MediatorService.loadStreamHistory();
        }
        const pendingStream = GlobalStates.mediatorPendingStream;
        if (pendingStream) {
            GlobalStates.mediatorPendingStream = null;
            root.openStreamTitle(pendingStream);
        } else if (GlobalStates.mediatorPendingTitle !== "") {
            MediatorService.loadDetail(GlobalStates.mediatorPendingTitle);
            GlobalStates.mediatorPendingTitle = "";
        } else if (resume && last.detailId !== "") {
            MediatorService.loadDetail(last.detailId);
        }
        search.forceActiveFocus();
    }
    Component.onDestruction: {
        GlobalStates.mediatorLast = { tab: root.tab, detailId: MediatorService.detailId };
        MediatorService.clearDetail();
        MediatorService.release();
    }

    Connections {
        target: GlobalStates
        function onMediatorPendingTabChanged() {
            const pending = String(GlobalStates.mediatorPendingTab ?? "");
            if (pending === "")
                return;
            // A presentation switch tears this browser down. Leave the tab for the
            // browser on the destination surface instead of consuming it here.
            if (root.overlay && GlobalStates.mediatorWindowed)
                return;
            if (!root.overlay && !GlobalStates.mediatorWindowed)
                return;
            GlobalStates.mediatorPendingTab = "";
            root.setTab(pending === "all" ? "" : pending);
            const pendingStream = GlobalStates.mediatorPendingStream;
            if (pendingStream) {
                GlobalStates.mediatorPendingStream = null;
                root.openStreamTitle(pendingStream);
            }
            search.forceActiveFocus();
        }
    }

    // Starting an episode from the Streaming tab hands the screen to the player, so the
    // overlay steps aside instead of sitting in front of it
    Connections {
        target: MediatorService
        function onProviderStreamStarted() {
            if (root.overlay && root.streaming)
                root.closeRequested();
        }
    }

    function handleKey(event): void {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_T
                && !root.streamOpen && !root.settingsOpen) {
            MediatorService.watchTogether = !MediatorService.watchTogether;
            event.accepted = true;
            return;
        }
        // The native stream dialog owns keyboard input while it is open. The search field
        // below can retain focus for a frame during Loader transitions, so do not let its
        // global handler consume text intended for the modal.
        if (root.streamOpen || (root.inDetail && detail.streamOpen)) {
            event.accepted = false;
            return;
        }
        if (root.streaming) {
            const ctrl = event.modifiers & Qt.ControlModifier;
            if (ctrl && event.key === Qt.Key_W && root.overlay) {
                root.windowRequested();
                return;
            }
            if (ctrl && event.key === Qt.Key_Comma) {
                root.openSettings();
                return;
            }
            if ((event.modifiers & Qt.AltModifier) && event.key >= Qt.Key_1
                    && event.key < Qt.Key_1 + root.tabs.length) {
                root.setTab(root.tabs[event.key - Qt.Key_1].key);
                return;
            }
            if (ctrl && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                root.setKind(event.key === Qt.Key_Up ? "anime" : "stremio");
                return;
            }
            if (ctrl && (event.key === Qt.Key_Left || event.key === Qt.Key_Right)) {
                toolbar.stepBrowse(event.key === Qt.Key_Left ? -1 : 1);
                return;
            }
            if (ctrl && event.key === Qt.Key_R) {
                root._leaveContinue();
                pageLoader.item?.jumpCursor?.(-1);
                return;
            }
            if (!root.streamContinue && search.text === "" && pageLoader.item?.jumpCursor) {
                const p = pageLoader.item;
                const rows = Math.max(1, Math.floor(pageLoader.height / 300));
                if (event.key === Qt.Key_Home) {
                    p.jumpCursor(0);
                    return;
                }
                if (event.key === Qt.Key_End) {
                    p.jumpCursor(p.cursorCount - 1);
                    return;
                }
                if (event.key === Qt.Key_PageDown) {
                    p.jumpCursor(Math.max(0, p.cursor) + p.cursorColumns * rows);
                    return;
                }
                if (event.key === Qt.Key_PageUp) {
                    p.jumpCursor(Math.max(0, p.cursor) - p.cursorColumns * rows);
                    return;
                }
            }
            if (event.key === Qt.Key_Delete && root.streamContinue && search.text === "") {
                continueRow.removeCursor();
                return;
            }
            if (event.key === Qt.Key_Tab) {
                root.stepTab(1);
                return;
            }
            if (event.key === Qt.Key_Backtab) {
                root.stepTab(-1);
                return;
            }
            if (event.key === Qt.Key_Escape) {
                if (root.stremio && StremioService.view !== "home")
                    StremioService.back();
                else if (!root.stremio && AnimeBrowseService.view !== "home")
                    AnimeBrowseService.back();
                else if (!root.stremio && AnimeBrowseService.mode === "search") {
                    search.text = "";
                    AnimeBrowseService.load("trending");
                } else if (root.stremio && StremioService.searching) {
                    // The results outlive the text: clear both, so Esc really leaves the search
                    search.text = "";
                    StremioService.clearSearch();
                } else if (search.text !== "")
                    search.text = "";
                else
                    root.closeRequested();
                return;
            }
            const page = pageLoader.item;
            const atEdgeRight = search.cursorPosition >= search.text.length;
            const atEdgeLeft = search.cursorPosition === 0 || search.text === "";
            if (event.key === Qt.Key_Down && root.streamMove(page, 0, 1))
                return;
            if (event.key === Qt.Key_Up && root.streamMove(page, 0, -1))
                return;
            if (event.key === Qt.Key_Right && atEdgeRight && root.streamMove(page, 1, 0))
                return;
            if (event.key === Qt.Key_Left && atEdgeLeft && root.streamMove(page, -1, 0))
                return;
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && ctrl && page?.chooseCursor) {
                // Ctrl+Enter: choose the stream by hand for the episode under the cursor
                page.chooseCursor();
                return;
            }
            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ShiftModifier)) {
                // Shift+Enter: the library's copy of the title under the cursor, when there is one
                const local = root.streamContinue ? continueRow.localForCursor() : page?.localForCursor?.();
                if (local)
                    root.openLocal(local.id);
                return;
            }
            if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                // A card under the cursor opens; otherwise Enter searches what was typed
                if (search.text === "" && root.streamContinue && continueRow.activateCursor())
                    return;
                if (page && search.text === "") {
                    // Nothing selected and nothing typed: Enter steps onto the first cover
                    if (!page.activateCursor())
                        page.moveCursor(0, 1);
                    return;
                }
                if (root.stremio)
                    StremioService.search(search.text);
                else
                    AnimeBrowseService.search(search.text);
                return;
            }
            event.accepted = false;
            return;
        }
        event.accepted = true;
        if (root.inDetail) {
            if (detail.editingPoster) {
                event.accepted = false;
                return;
            }
            if (detail.handleKey(event))
                return;
            event.accepted = true;
            return;
        }
        if ((event.modifiers & Qt.ControlModifier) && MediatorService.now) {
            if (event.key === Qt.Key_Space) {
                MediatorService.control("toggle", null);
                return;
            }
            if (event.key === Qt.Key_Left || event.key === Qt.Key_Right) {
                MediatorService.control("seek", event.key === Qt.Key_Left ? -10 : 10);
                return;
            }
        }
        if (root.overlay && event.key === Qt.Key_W && (event.modifiers & Qt.ControlModifier)) {
            root.windowRequested();
            return;
        }
        if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            root.surprise();
            return;
        }
        if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + root.tabs.length
                && (event.modifiers & Qt.AltModifier)) {
            root.setTab(root.tabs[event.key - Qt.Key_1].key);
            return;
        }
        if (event.key === Qt.Key_Comma && (event.modifiers & Qt.ControlModifier)) {
            root.openSettings();
            return;
        }
        switch (event.key) {
        case Qt.Key_Escape:
            if (root.query !== "")
                search.text = "";
            else
                root.closeRequested();
            return;
        case Qt.Key_Home:
            root.jump(0);
            return;
        case Qt.Key_End:
            root.jump(root.items.length - 1);
            return;
        case Qt.Key_PageDown:
            root.jump(root.cur + grid.columns * Math.max(1, Math.floor(grid.height / grid.cellHeight)));
            return;
        case Qt.Key_PageUp:
            root.jump(root.cur - grid.columns * Math.max(1, Math.floor(grid.height / grid.cellHeight)));
            return;
        case Qt.Key_Tab:
            root.stepTab(1);
            return;
        case Qt.Key_Backtab:
            root.stepTab(-1);
            return;
        case Qt.Key_Down:
            root.moveCursor(0, 1);
            return;
        case Qt.Key_Up:
            root.moveCursor(0, -1);
            return;
        case Qt.Key_Right:
            if (search.cursorPosition >= search.text.length) {
                root.moveCursor(1, 0);
                return;
            }
            break;
        case Qt.Key_Left:
            if (search.cursorPosition === 0 || search.text === "") {
                root.moveCursor(-1, 0);
                return;
            }
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter: {
            const t = root.focusedTitle();
            if (t) {
                // The hero and the row are for resuming; the grid opens the page first
                const resumeFirst = root.zone !== "grid";
                if (resumeFirst !== !!(event.modifiers & Qt.ShiftModifier))
                    root.play(t);
                else
                    root.openTitle(t);
            }
            return;
        }
        }
        event.accepted = false;
    }

    Item {
        id: page
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            spacing: 22

            // Header: search, tabs, count
            RowLayout {
                Layout.fillWidth: true
                // Inside a title the header steps aside (it keeps focus, so collapse rather than hide)
                Layout.fillHeight: false
                Layout.preferredHeight: root.inDetail ? 0 : 48
                Layout.maximumHeight: root.inDetail ? 0 : 48
                Layout.bottomMargin: root.inDetail ? -22 : 0
                opacity: root.inDetail ? 0 : 1
                clip: true
                spacing: 20

                Rectangle {
                    Layout.preferredWidth: 380
                    Layout.preferredHeight: 48
                    radius: Appearance.rounding.full
                    color: Appearance.colors.colLayer1
                    border.width: search.activeFocus ? 2 : 0
                    border.color: Appearance.colors.colPrimary
                    RowLayout {
                        anchors { fill: parent; leftMargin: 16; rightMargin: 16 }
                        spacing: 10
                        MaterialSymbol { text: "search"; iconSize: 22; color: Appearance.colors.colSubtext }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            color: Appearance.colors.colOnLayer0
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            selectByMouse: true
                            clip: true
                            // Modal panels load a frame after they open; until they take focus, keep stray typing out of search
                            readOnly: root.streamOpen || root.settingsOpen || (root.inDetail && detail.editingPoster)
                            onTextChanged: root.query = text
                            // Emptying the field by hand also leaves a Stremio search
                            onTextEdited: if (text === "" && root.streaming && root.stremio && StremioService.searching)
                                StremioService.clearSearch()
                            Keys.onPressed: event => root.handleKey(event)
                            StyledText {
                                visible: search.text === ""
                                text: root.stremio ? "Search movies and series" : root.streaming ? "Search anime" : "Search your library"
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.normal
                            }
                        }
                    }
                }

                Row {
                    visible: root.overlay
                    spacing: 6
                    Repeater {
                        model: root.tabs
                        delegate: Rectangle {
                            id: tabPill
                            required property var modelData
                            readonly property bool on: tabPill.modelData.key === root.tabKey
                            width: tabRow.implicitWidth + 32
                            height: 40
                            radius: Appearance.rounding.full
                            color: tabPill.on ? Appearance.colors.colSecondaryContainer
                                 : tabArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                            Behavior on color {
                                ColorAnimation { duration: Appearance.dur(120) }
                            }
                            RowLayout {
                                id: tabRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol {
                                    text: tabPill.modelData.icon
                                    iconSize: 20
                                    fill: tabPill.on ? 1 : 0
                                    color: Appearance.colors.colOnLayer0
                                }
                                StyledText {
                                    text: tabPill.modelData.label
                                    color: Appearance.colors.colOnLayer0
                                    font.weight: tabPill.on ? Font.Medium : Font.Normal
                                }
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.setTab(tabPill.modelData.key)
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    visible: root.overlay
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.full
                    color: winArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                    MaterialSymbol { anchors.centerIn: parent; text: "open_in_new"; iconSize: 22; color: Appearance.colors.colOnLayer0 }
                    MouseArea {
                        id: winArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.windowRequested()
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.full
                    color: streamArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                    MaterialSymbol { anchors.centerIn: parent; text: "live_tv"; iconSize: 22; color: Appearance.colors.colOnLayer0 }
                    MouseArea {
                        id: streamArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.stremio)
                                StremioService.search(search.text);
                            else if (root.streaming)
                                AnimeBrowseService.search(search.text);
                            else
                                root.setTab("stream");
                        }
                    }
                    StyledToolTip {
                        extraVisibleCondition: streamArea.containsMouse
                        text: root.stremio ? "Search Stremio" : root.streaming ? "Search anime online" : "Open the streaming section"
                    }
                }

                // Watch Together: one click, no trip to Settings. Lit while Syncplay is on.
                Rectangle {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.full
                    color: MediatorService.watchTogether ? Appearance.colors.colPrimaryContainer
                         : togetherArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "group"
                        iconSize: 22
                        fill: MediatorService.watchTogether ? 1 : 0
                        color: MediatorService.watchTogether ? Appearance.colors.colOnPrimaryContainer
                             : Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: togetherArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            MediatorService.watchTogether = !MediatorService.watchTogether;
                            // First time on: the room settings live in the Syncplay window.
                            if (MediatorService.watchTogether && !SyncplayService.configured)
                                root.openRoom();
                        }
                        StyledToolTip {
                            requireOverlay: false
                            text: MediatorService.watchTogether
                                ? Translation.tr("Watch Together is on (Syncplay) · Ctrl+T")
                                : Translation.tr("Watch Together is off · Ctrl+T")
                        }
                    }
                }

                // The room: who is watching, chat, ready. Only while Watch Together is on.
                Rectangle {
                    visible: MediatorService.watchTogether
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.full
                    color: roomArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: SyncplayService.connected ? "forum" : "meeting_room"
                        iconSize: 22
                        fill: SyncplayService.connected ? 1 : 0
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: roomArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.openRoom()
                        StyledToolTip {
                            requireOverlay: false
                            text: SyncplayService.connected
                                ? Translation.tr("Open the room · %1").arg(SyncplayService.room)
                                : Translation.tr("Set up the room")
                        }
                    }
                }

                Rectangle {
                    visible: root.overlay
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    radius: Appearance.rounding.full
                    color: root.settingsOpen ? Appearance.colors.colSecondaryContainer
                         : gearArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "settings"
                        iconSize: 22
                        fill: root.settingsOpen ? 1 : 0
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: gearArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.settingsOpen ? root.closeSettings() : root.openSettings()
                    }
                }

                // Library only: show or hide the Jellyfin server's titles (the same switch as in Settings)
                Rectangle {
                    id: jfToggle
                    readonly property bool configured: MediatorService.settings?.jellyfin?.configured ?? false
                    readonly property bool on: MediatorService.settings?.jellyfin?.include ?? false
                    visible: !root.streaming && jfToggle.configured
                    implicitWidth: jfRow.implicitWidth + 24
                    implicitHeight: 32
                    radius: Appearance.rounding.full
                    color: jfToggle.on ? Appearance.colors.colSecondaryContainer
                         : jfArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                    border.width: jfToggle.on ? 0 : 1
                    border.color: Appearance.colors.colOutlineVariant
                    opacity: MediatorService.saving ? 0.6 : 1
                    Row {
                        id: jfRow
                        anchors.centerIn: parent
                        spacing: 6
                        MaterialSymbol {
                            anchors.verticalCenter: parent.verticalCenter
                            text: jfToggle.on ? "cloud_done" : "cloud_off"
                            fill: jfToggle.on ? 1 : 0
                            iconSize: 17
                            color: Appearance.colors.colOnLayer0
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Jellyfin"
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: jfToggle.on ? Font.Medium : Font.Normal
                        }
                    }
                    MouseArea {
                        id: jfArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.saveSettings({ "jellyfin.include": !jfToggle.on })
                    }
                    StyledToolTip {
                        extraVisibleCondition: jfArea.containsMouse
                        text: jfToggle.on ? "Showing Jellyfin titles. Click to hide them" : "Click to add your Jellyfin titles to the library"
                    }
                }

                StyledText {
                    text: root.stremio ? (StremioService.busy ? "Loading…" : StremioService.heading)
                        : root.streaming
                        ? (MediatorService.anilistWatchingBusy ? "Loading AniList…"
                            : (MediatorService.anilistStatus?.ok
                                ? `${MediatorService.anilistWatching.length} watching`
                                : "AniList not connected"))
                        : MediatorService.enrich.running ? `Fetching info ${MediatorService.enrich.done}/${MediatorService.enrich.total}…`
                            : MediatorService.loading ? "Scanning…"
                            : `${root.localItems.length} ${root.localItems.length === 1 ? "title" : "titles"}`
                                + (onlineSearch.busy ? " · searching online…" : root.onlineItems.length > 0 ? ` · ${root.onlineItems.length} online` : "")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            // Hero: the title to pick up next, big
            RoundedBox {
                id: hero
                Layout.fillWidth: true
                Layout.preferredHeight: 250
                visible: root.heroTitle !== null && !root.inDetail && !root.settingsOpen && !root.streaming
                radius: Appearance.rounding.verylarge
                color: Appearance.colors.colLayer1
                readonly property var t: root.heroTitle ?? ({})
                readonly property var n: t.next ?? null
                readonly property real frac: (t.total ?? 0) > 0 ? (t.watched ?? 0) / t.total : 0

                readonly property bool hasBanner: (hero.t.banner ?? "") !== ""
                Image {
                    id: heroBack
                    anchors.fill: parent
                    source: hero.hasBanner ? `file://${hero.t.banner}` : MediatorService.posterUrl(hero.t.poster)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: hero.hasBanner ? 1600 : 400
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: heroBack
                    autoPaddingEnabled: false
                    blurEnabled: !hero.hasBanner
                    blur: 1.0
                    blurMax: 64
                    brightness: -0.1
                    saturation: 0.3
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.55) }
                        GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.1) }
                    }
                }
                RowLayout {
                    anchors { fill: parent; margins: 20 }
                    spacing: 24
                    RoundedBox {
                        Layout.fillHeight: true
                        Layout.preferredWidth: height * 2 / 3
                        radius: Appearance.rounding.normal
                        color: Appearance.colors.colLayer2
                        Image {
                            anchors.fill: parent
                            source: MediatorService.posterUrl(hero.t.poster)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize.width: 400
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: 6
                        StyledText {
                            text: "CONTINUE WATCHING"
                            color: "#ccffffff"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.letterSpacing: 1.5
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: hero.t.display ?? hero.t.name ?? ""
                            elide: Text.ElideRight
                            color: "white"
                            font.pixelSize: Appearance.font.pixelSize.huge * 1.2
                            font.weight: Font.DemiBold
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: {
                                const n = hero.n;
                                if (!n)
                                    return "";
                                return n.reason === "resume" && n.position > 0 ? `${n.label} · stopped at ${MediatorService.clock(n.position)}` : n.label;
                            }
                            elide: Text.ElideRight
                            color: "#ddffffff"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 720
                            visible: (hero.t.blurb ?? "") !== ""
                            text: hero.t.blurb ?? ""
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            color: "#ccffffff"
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        Item { Layout.fillHeight: true }
                        Rectangle {
                            Layout.preferredWidth: 280
                            Layout.preferredHeight: 4
                            radius: 2
                            visible: hero.frac > 0
                            color: "#44ffffff"
                            Rectangle {
                                width: parent.width * hero.frac
                                height: parent.height
                                radius: 2
                                color: Appearance.colors.colPrimary
                            }
                        }
                        RowLayout {
                            spacing: 10
                            Rectangle {
                                Layout.preferredHeight: 44
                                Layout.preferredWidth: resumeLabel.implicitWidth + 64
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colPrimary
                                border.width: root.zone === "hero" ? 3 : 0
                                border.color: "white"
                                RowLayout {
                                    id: resumeLabel
                                    anchors.centerIn: parent
                                    spacing: 6
                                    MaterialSymbol { text: "play_arrow"; fill: 1; iconSize: 24; color: Appearance.colors.colOnPrimary }
                                    StyledText { text: "Resume"; color: Appearance.colors.colOnPrimary; font.weight: Font.Medium }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.play(hero.t)
                                }
                            }
                            Rectangle {
                                Layout.preferredHeight: 44
                                Layout.preferredWidth: 44
                                radius: Appearance.rounding.full
                                color: "#33ffffff"
                                MaterialSymbol { anchors.centerIn: parent; text: "info"; iconSize: 22; color: "white" }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.openTitle(hero.t)
                                }
                            }
                        }
                    }
                }
            }

            // Grid or detail
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true  // the streaming header slides up under the search bar as the page scrolls

                    // Continue watching
                    ColumnLayout {
                        id: upNext
                        width: parent.width
                        z: 2
                        // Rides with the grid so scrolling carries it away; the hero above stays put
                        y: -(grid.contentY + grid.topMargin)
                        visible: (root.rowItems.length > 0 || !root.continueLoaded || root.continueError !== "") && root.query === "" && root.tab === "" && !root.inDetail && !root.settingsOpen && !root.streaming
                        spacing: 10
                        StyledText {
                            visible: (!root.continueLoaded && root.continueBusy) || root.continueError !== ""
                            text: root.continueError !== "" ? root.continueError : Translation.tr("Loading watch history…")
                            color: Appearance.colors.colSubtext
                        }
                        ResumeCarousel {
                            visible: root.rowItems.length > 0
                            id: resumeList
                            Layout.fillWidth: true
                            Layout.preferredHeight: implicitHeight
                            model: root.rowItems
                            current: root.resumeCur
                            active: root.zone === "row"
                            onCurrentRequested: index => {
                                root.resumeCur = index;
                                root.zone = "row";
                            }
                            onActivated: title => root.play(title)
                            onOpenRequested: title => root.openTitle(title)
                        }
                    }

                GridView {
                    WheelScroll {}
                    id: grid
                    anchors.fill: parent
                    visible: !root.inDetail && !root.settingsOpen && !root.streaming
                    readonly property int columns: Math.max(2, Math.floor(width / 190))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: cellWidth * 1.5 + 70
                    clip: true
                    topMargin: upNext.visible ? upNext.implicitHeight + 10 : 0
                    // The row's height arrives after the grid has settled at 0: start from the top again
                    onTopMarginChanged: Qt.callLater(() => grid.contentY = grid.originY - grid.topMargin)
                    model: root.items
                    boundsBehavior: Flickable.StopAtBounds
                    currentIndex: root.cur

                    delegate: PosterCard {
                        id: card
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        title: card.modelData
                        selected: root.zone === "grid" && card.index === root.cur
                        onActivated: {
                            root.cur = card.index;
                            root.openTitle(card.modelData);
                        }
                        onPlayRequested: root.play(card.modelData)
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.items.length === 0 && !MediatorService.loading
                        text: MediatorService.error !== "" ? MediatorService.error : onlineSearch.busy ? "Searching online…" : "Nothing matches"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.large
                    }
                }

                Component {
                    id: animePage
                    StreamingSection {
                        onSearchRequested: (query, anilistId, season, total) =>
                            root.openStream(query, anilistId, season, total)
                        onSettingsRequested: root.openSettings()
                        onLocalRequested: id => root.openLocal(id)
                    }
                }

                Component {
                    id: stremioPage
                    StremioSection {
                        onLocalRequested: id => root.openLocal(id)
                    }
                }

                // Sub-tabs of the Streaming section: anime providers, or movies & shows via Stremio
                Column {
                    id: topArea
                    // A title page or stream list is the whole screen: no continue row or toolbar above it
                    visible: root.streaming && !root.settingsOpen && !root.inDetail
                        && pageLoader.item?.ownsKeys !== true
                    width: parent.width
                    spacing: 12
                    z: 5
                    // Scrolls away with the page: the section reports how far it has moved
                    y: pageLoader.item ? -Number(pageLoader.item.scrollOffset ?? 0) : 0

                StartingBanner {
                    width: parent.width
                }

                // Parked for now: hidden here, and the keyboard skips it (it reads `visible`)
                ContinueWatching {
                    id: continueRow
                    width: parent.width
                    visible: false
                }

                OnlineSearch {
                    id: onlineSearch
                    query: root.query
                    active: root.tab === "" && !root.streaming && !root.settingsOpen && !root.inDetail
                }

                // Room for the toolbar, which rides above and pins once the page scrolls under it
                Item {
                    id: toolbarSlot
                    width: parent.width
                    height: toolbar.implicitHeight
                }
                }

                StreamToolbar {
                    id: toolbar
                    visible: topArea.visible
                    width: parent.width
                    z: 6
                    onlineKind: root.onlineKind
                    // Ride with the page, then stay at the top of the view
                    y: Math.max(0, topArea.y + toolbarSlot.y)
                    stuck: topArea.y + toolbarSlot.y < -2
                    onKindRequested: kind => root.setKind(kind)
                    onSettingsRequested: root.openSettings()
                    onRefreshRequested: pageLoader.item?.reload?.()
                }

                Loader {
                    id: pageLoader
                    anchors.fill: parent
                    active: root.streaming && !root.settingsOpen && !root.inDetail
                    sourceComponent: root.stremio ? stremioPage : animePage
                }

                // The page leaves room for the header at the top of its own scroll area
                Binding {
                    target: pageLoader.item
                    property: "stickyHeight"
                    value: toolbar.implicitHeight + 16
                    when: pageLoader.item !== null
                }

                Binding {
                    target: pageLoader.item
                    property: "headerHeight"
                    value: topArea.visible ? topArea.height + 12 : 0
                    when: pageLoader.item !== null
                }

                Loader {
                    anchors.fill: parent
                    active: root.settingsOpen
                    sourceComponent: SettingsPanel {
                        onCloseRequested: root.closeSettings()
                    }
                }

                Loader {
                    anchors.fill: parent
                    active: root.streamOpen && !root.settingsOpen && !root.inDetail
                    z: 10
                    sourceComponent: AnimeStreamDialog {
                        searchMode: true
                        initialQuery: root.streamInitialQuery
                        autoSearch: root.streamAutoSearch
                        anilistId: root.streamAniListId
                        anilistSeason: root.streamAniListSeason
                        anilistTotal: root.streamAniListTotal
                        onCloseRequested: root.closeStream()
                        onStreamStarted: {
                            root.closeStream();
                            if (root.overlay)
                                root.closeRequested();
                            else
                                root.setTab("stream");
                        }
                    }
                }

                TitleDetail {
                    id: detail
                    anchors.fill: parent
                    visible: root.inDetail && !root.settingsOpen && !root.streaming
                    title: root.detailTitle ?? ({})
                    closeAfterStream: root.overlay
                    onCloseRequested: {
                        MediatorService.clearDetail();
                        root.streamOpen = false;
                        search.forceActiveFocus();
                    }
                    onRefocusRequested: search.forceActiveFocus()
                    onContinueRequested: root.play(root.detailTitle)
                    onStreamStarted: if (root.overlay) root.closeRequested()
                    onPlayRequested: path => {
                        MediatorService.playPath(root.detailTitle.id, path);
                        if (root.overlay)
                            root.closeRequested();
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -14
                Layout.preferredHeight: 16
                verticalAlignment: Text.AlignVCenter
                text: root.settingsOpen ? "Esc back  ·  Tab next field  ·  Changes apply when you press Save"
                    : root.streaming ? (root.stremio ? "Type to search movies and series" : "Type to search anime")
                        + "  ·  ←↑↓→ move  ·  Enter opens  ·  Shift+Enter library copy  ·  Ctrl+←→ browse  ·  Ctrl+↑↓ source  ·  Ctrl+R random  ·  Esc back"
                    : root.inDetail && detail.isMovie ? "Esc back  ·  Enter play  ·  W mark watched  ·  P change poster"
                    : root.inDetail ? "Esc back  ·  ↑↓ episode  ·  ←→ season  ·  Enter play  ·  W mark watched  ·  P change poster"
                                    : root.overlay ? "Type to search  ·  ←↑↓→ move  ·  Tab section  ·  Enter opens or resumes  ·  Shift+Enter the other  ·  Ctrl+R random  ·  Ctrl+, settings  ·  Ctrl+W window  ·  Esc closes"
                    : "Type to search  ·  ←↑↓→ move  ·  Tab section  ·  Enter opens or resumes  ·  Shift+Enter the other  ·  Ctrl+R random  ·  Ctrl+, settings  ·  Ctrl+Q closes"
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}

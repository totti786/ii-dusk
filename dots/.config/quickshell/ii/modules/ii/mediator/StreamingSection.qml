pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The online half of mediator: what is playing or paused, the provider's own recent
 * episodes, and the user's AniList watching queue. Local files and Jellyfin stay in
 * the library tabs; this page never reads the local catalog.
 */
Item {
    id: root

    signal searchRequested(string query, int anilistId, int season, int total)
    signal settingsRequested()
    signal localRequested(string id)

    readonly property var current: MediatorService.nativeState
    readonly property bool hasCurrent: MediatorService.nativeHasState
    readonly property bool currentActive: MediatorService.nativeActive
    readonly property bool currentPaused: MediatorService.nativePaused
    readonly property var history: {
        // `stream-state --all` is per episode. The hub wants one row per show: the
        // latest episode. The current show lives in the card above, so it is not
        // repeated in Recent streams.
        const currentShow = root.hasCurrent ? String(root.current?.show_id ?? "") : "";
        return MediatorService.streamShows(MediatorService.streamHistory, item => {
            const show = String(item?.show_id ?? "");
            return !show.startsWith("stremio:") && !(currentShow !== "" && show === currentShow);
        });
    }
    readonly property var watching: Array.isArray(MediatorService.anilistWatching)
        ? MediatorService.anilistWatching : []
    readonly property var anilist: MediatorService.anilistStatus ?? ({})
    readonly property bool anilistConfigured: Boolean(root.anilist?.configured)
    readonly property bool anilistOk: Boolean(root.anilist?.ok)
    readonly property string anilistUser: String(root.anilist?.username ?? "")
    readonly property int anilistPending: Number(root.anilist?.pending ?? 0)
    readonly property bool busy: MediatorService.streamHistoryBusy
        || MediatorService.anilistWatchingBusy

    readonly property real currentFraction: Number(root.current?.duration ?? 0) > 0
        ? Math.max(0, Math.min(1, Number(root.current?.position ?? 0) / Number(root.current.duration)))
        : 0
    readonly property var currentNext: root.nextOf(root.current)

    function nextOf(state): var {
        if (!state)
            return null;
        const episodes = Array.isArray(state.episodes) ? state.episodes : [];
        const id = String(state.episode_id ?? "");
        const index = episodes.findIndex(item => String(item?.id ?? "") === id);
        return index >= 0 && index + 1 < episodes.length ? episodes[index + 1] : null;
    }

    function resumeState(state): void {
        if (!state)
            return;
        const showId = String(state.show_id ?? "");
        let episodeId = String(state.episode_id ?? "");
        if (Boolean(state.watched)) {
            const next = root.nextOf(state);
            if (next)
                episodeId = String(next.id ?? episodeId);
        }
        if (showId === "" || episodeId === "")
            return;
        MediatorService.playProviderEpisode(showId, episodeId,
            String(state.title ?? ""), Boolean(state.dub),
            String(state.quality ?? "best"), String(state.poster ?? ""), true,
            Number(state.anilist_id ?? 0), Number(state.season ?? 0),
            Number(state.total ?? 0));
    }

    function playNext(): void {
        const next = root.currentNext;
        if (!next || !root.hasCurrent)
            return;
        MediatorService.playProviderEpisode(String(root.current.show_id), String(next.id),
            String(root.current.title ?? ""), Boolean(root.current.dub),
            String(root.current.quality ?? "best"), String(root.current.poster ?? ""), true,
            Number(root.current.anilist_id ?? 0), Number(root.current.season ?? 0),
            Number(root.current.total ?? 0));
    }

    function toggleCurrent(): void {
        if (root.currentActive)
            MediatorService.nativeControl("toggle");
        else
            root.resumeState(root.current);
    }

    function nativeForAniList(entry): var {
        const mediaId = Number(entry?.id ?? 0);
        if (mediaId <= 0)
            return null;
        const all = [root.current].concat(root.history);
        return all.find(state => Number(state?.anilist_id ?? 0) === mediaId) ?? null;
    }

    function openAniList(entry): void {
        if (!entry)
            return;
        // A linked native state already carries the exact provider ids and resume
        // position. Prefer it over a fresh title search.
        const native = root.nativeForAniList(entry);
        if (native) {
            const nativeEpisode = Number(native?.episode_number ?? 0);
            const anilistProgress = Number(entry?.progress ?? 0);
            if (anilistProgress === 0 || anilistProgress <= nativeEpisode) {
                root.resumeState(native);
                return;
            }
        }
        AnimeBrowseService.openQueued(String(entry.title ?? ""), Number(entry.id ?? 0),
            String(entry.format ?? "").toUpperCase() === "MOVIE" ? 0 : 1,
            Number(entry.total ?? 0));
    }

    function refresh(): void {
        MediatorService.loadStreaming();
        if (AnimeBrowseService.items.length === 0 && AnimeBrowseService.view === "home")
            AnimeBrowseService.load(AnimeBrowseService.mode);
    }

    /// The toolbar's refresh: fetch the current list and the queue again
    function reload(): void {
        MediatorService.loadStreaming();
        MediatorService.loadAniListWatching();
        AnimeBrowseService.load(AnimeBrowseService.mode === "search" ? "trending" : AnimeBrowseService.mode);
    }

    Component.onCompleted: root.refresh()

    // ── Keyboard: a cursor over the browse cards, then over the AniList queue below them ──
    property int cursor: -1
    property int wcursor: -1
    property bool heroFocus: false
    readonly property bool ownsKeys: AnimeBrowseService.view === "title"
    onBillboardShownChanged: if (!root.billboardShown) root.heroFocus = false
    Connections {
        target: AnimeBrowseService
        function onViewChanged() { titlePage.cursor = -1; }
    }
    // Billboard candidates: the first entries that have a banner
    readonly property var featured: AnimeBrowseService.mode === "search" ? []
        : AnimeBrowseService.items.slice(0, 14).filter(i => i.banner).slice(0, 5)
    property int featuredIndex: 0
    readonly property bool billboardShown: AnimeBrowseService.view === "home" && root.featured.length > 0
    onFeaturedChanged: if (root.featuredIndex >= root.featured.length) root.featuredIndex = 0
    readonly property int cursorColumns: Math.max(2, Math.floor(scroll.width / 186))
    readonly property int cursorCount: AnimeBrowseService.items.length
    readonly property int watchingCount: root.anilistOk ? root.watching.length : 0

    function _show(index): void {
        const card = browseRepeater.itemAt(index);
        if (!card)
            return;
        root._reveal(card.mapToItem(scroll.contentItem, 0, 0).y, card.height);
    }

    /// Keep a band of the page clear of the pinned toolbar and the hint bar
    function _reveal(y, height): void {
        if (y < scroll.contentY + root.stickyHeight)
            scroll.contentY = Math.max(0, y - root.stickyHeight - 8);
        else if (y + height > scroll.contentY + scroll.height - 24)
            scroll.contentY = y + height - scroll.height + 32;
    }

    function _showWatching(): void {
        watchingList.positionViewAtIndex(root.wcursor, ListView.Contain);
        root._reveal(watchingList.mapToItem(scroll.contentItem, 0, 0).y, watchingList.height);
    }

    function scrollTop(): void {
        scroll.contentY = 0;
    }

    /// Jump to a card (a negative index picks one at random); off-range values clamp
    function jumpCursor(index): void {
        if (AnimeBrowseService.view !== "home" || root.cursorCount === 0)
            return;
        root.wcursor = -1;
        root.cursor = index < 0 ? Math.floor(Math.random() * root.cursorCount)
            : Math.max(0, Math.min(root.cursorCount - 1, index));
        root._show(root.cursor);
    }

    /// True when the key was used. Up from the first row hands control back (cursor off).
    function moveCursor(dx, dy): bool {
        if (AnimeBrowseService.view === "title") {
            const n = AnimeBrowseService.episodes.length;
            if (n === 0 || dy === 0)
                return true;
            let c = titlePage.cursor;
            if (c < 0) {
                const next = AnimeBrowseService.episodes.findIndex(e => String(e.id) === titlePage.nextId);
                c = dy > 0 ? Math.max(0, next) : n - 1;
            } else {
                c = Math.max(0, Math.min(n - 1, c + dy));
            }
            titlePage.cursor = c;
            const item = titlePage.episodeItem(c);
            if (item)
                root._reveal(item.mapToItem(scroll.contentItem, 0, 0).y, item.height);
            return true;
        }
        if (AnimeBrowseService.view !== "home")
            return false;
        if (root.wcursor >= 0) {
            if (dy < 0) {
                // Back up to the last row of covers, under the card the queue was left from
                root.wcursor = -1;
                root.cursor = Math.max(0, root.cursorCount - 1);
                root._show(root.cursor);
            } else if (dx !== 0) {
                root.wcursor = Math.max(0, Math.min(root.watchingCount - 1, root.wcursor + dx));
                root._showWatching();
            }
            return true;
        }
        if (root.heroFocus) {
            if (dx !== 0) {
                root.featuredIndex = (root.featuredIndex + dx + root.featured.length) % root.featured.length;
            } else if (dy < 0) {
                root.heroFocus = false;
            } else if (dy > 0) {
                root.heroFocus = false;
                root.cursor = root.cursorCount > 0 ? 0 : -1;
                if (root.cursor >= 0)
                    root._show(0);
            }
            return true;
        }
        if (root.cursorCount === 0)
            return false;
        if (root.cursor < 0) {
            if (dy <= 0 && dx === 0)
                return false;
            if (dy > 0 && root.billboardShown) {
                root.heroFocus = true;
                root.scrollTop();
                return true;
            }
            root.cursor = 0;
        } else {
            const cols = root.cursorColumns;
            let n = root.cursor + dx + dy * cols;
            if (dy < 0 && root.cursor < cols) {
                root.cursor = -1;
                if (root.billboardShown) {
                    root.heroFocus = true;
                    root.scrollTop();
                }
                return true;
            }
            const last = Math.floor((root.cursorCount - 1) / cols);
            if (dy > 0 && Math.floor(root.cursor / cols) >= last) {
                // Past the last row: into the AniList queue when it has cards
                if (root.watchingCount > 0) {
                    root.cursor = -1;
                    root.wcursor = 0;
                    root._showWatching();
                }
                return true;
            }
            if (dy > 0 && n >= root.cursorCount)
                n = root.cursorCount - 1;
            root.cursor = Math.max(0, Math.min(root.cursorCount - 1, n));
        }
        root._show(root.cursor);
        return true;
    }

    /// The library title behind the card under the cursor, if it has one
    function localForCursor(): var {
        const card = browseRepeater.itemAt(root.cursor);
        return root.cursor >= 0 && card ? card.local : null;
    }

    function activateCursor(): bool {
        if (AnimeBrowseService.view === "title") {
            const ep = AnimeBrowseService.episodes[titlePage.cursor];
            if (!ep)
                return false;
            AnimeBrowseService.play(ep);
            return true;
        }
        if (root.heroFocus) {
            const f = root.featured[root.featuredIndex];
            if (!f)
                return false;
            AnimeBrowseService.openTitle(f);
            return true;
        }
        if (root.wcursor >= 0 && root.wcursor < root.watchingCount) {
            root.openAniList(root.watching[root.wcursor]);
            return true;
        }
        if (root.cursor < 0 || root.cursor >= root.cursorCount)
            return false;
        AnimeBrowseService.openTitle(AnimeBrowseService.items[root.cursor]);
        return true;
    }

    onCursorCountChanged: if (root.cursor >= root.cursorCount) root.cursor = -1
    onWatchingCountChanged: if (root.wcursor >= root.watchingCount) root.wcursor = -1

    /// Set by the host: how much of the page the pinned toolbar covers when scrolled
    property real stickyHeight: 0
    property real headerHeight: 0
    readonly property real scrollOffset: scroll.contentY

    Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight + 28
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}

        ColumnLayout {
            id: body
            width: scroll.width
            spacing: 14

            // The unified header from the host floats over this gap and scrolls away with the page
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(0, root.headerHeight - body.spacing)
            }

            ColumnLayout {
                id: homeSection
                Layout.fillWidth: true
                spacing: 14
                visible: AnimeBrowseService.view === "home"

            // The controls live in the toolbar above; this line only names a search
            RowLayout {
                visible: AnimeBrowseService.mode === "search"
                Layout.fillWidth: true
                spacing: 10

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: AnimeBrowseService.heading
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                }
                StyledText {
                    text: "Esc for trending"
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            BackdropHero {
                id: billboard
                readonly property var f: root.featured[root.featuredIndex] ?? null
                visible: root.billboardShown
                name: f?.title ?? ""
                background: f?.banner ?? ""
                poster: f?.poster ?? ""
                description: f?.description ?? ""
                rating: f?.rating ?? ""
                facts: [f?.format === "MOVIE" ? "Movie" : "Series", f?.year,
                    f?.episodes > 0 ? f.episodes + " episodes" : "", f?.runtime].concat((f?.genres ?? []).slice(0, 3))
                dots: root.featured.length
                dotIndex: root.featuredIndex
                focused: root.heroFocus
                onDotRequested: i => root.featuredIndex = i

                ClockButton {
                    symbol: "play_arrow"
                    label: "Open"
                    variant: "filled"
                    onClicked: AnimeBrowseService.openTitle(billboard.f)
                }
                ClockButton {
                    readonly property var local: billboard.f
                        ? MediatorService.ownedFor([billboard.f.title, billboard.f.search], billboard.f.year) : null
                    visible: local !== null
                    symbol: "video_library"
                    label: "In your library"
                    variant: "tonal"
                    onClicked: root.localRequested(local.id)
                }
            }

            Timer {
                interval: 9000
                repeat: true
                running: root.billboardShown && root.featured.length > 1 && !billboard.hovered && root.visible
                onTriggered: root.featuredIndex = (root.featuredIndex + 1) % root.featured.length
            }

            StyledText {
                visible: AnimeBrowseService.mode !== "search" && AnimeBrowseService.heading !== ""
                Layout.topMargin: 6
                text: AnimeBrowseService.heading
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.huge
                font.weight: Font.DemiBold
            }

            Flow {
                visible: AnimeBrowseService.busy && AnimeBrowseService.items.length === 0
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: Math.max(2, Math.floor(scroll.width / 186)) * 2
                    CoverSkeleton {
                        width: Math.max(150, Math.floor(scroll.width / Math.max(2, Math.floor(scroll.width / 186))) - 1)
                    }
                }
            }

            Flow {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    id: browseRepeater
                    model: AnimeBrowseService.items

                    CoverCard {
                        required property var modelData
                        required property int index
                        selected: root.cursor === index
                        readonly property var local: MediatorService.ownedFor([modelData.title, modelData.search], modelData.year)
                        owned: local !== null
                        width: Math.max(150, Math.floor(scroll.width / Math.max(2, Math.floor(scroll.width / 186))) - 1)
                        poster: modelData.poster
                        name: modelData.title
                        rating: modelData.rating
                        subtitle: [modelData.format === "MOVIE" ? "Movie" : modelData.episodes > 0
                            ? modelData.episodes + " eps" : "Anime", modelData.year].filter(x => x).join(" · ")
                        onActivated: AnimeBrowseService.openTitle(modelData)
                    }
                }
            }

            StyledText {
                visible: AnimeBrowseService.error !== ""
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: AnimeBrowseService.error
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            // ── AniList queue ─────────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        text: root.anilistOk ? "AniList · Watching" : "AniList"
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        visible: root.anilistOk
                        text: MediatorService.anilistWatchingBusy ? "Loading…"
                            : `${root.watching.length} watching`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    RoundedBox {
                        visible: root.anilistOk
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        radius: Appearance.rounding.full
                        color: refreshArea.containsMouse
                            ? Appearance.colors.colLayer2 : "transparent"
                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 18
                            color: Appearance.colors.colOnLayer0
                        }
                        MouseArea {
                            id: refreshArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: MediatorService.loadAniListWatching()
                        }
                    }
                }

                // Not logged in: one quiet invitation, not a second settings page.
                RoundedBox {
                    visible: !root.anilistOk
                    Layout.fillWidth: true
                    Layout.preferredHeight: 72
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer1
                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 10
                        MaterialSymbol {
                            text: "account_circle"
                            iconSize: 22
                            color: Appearance.colors.colSubtext
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1
                            StyledText {
                                text: "Connect AniList to see your Watching queue"
                                color: Appearance.colors.colOnLayer0
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.weight: Font.Medium
                            }
                            StyledText {
                                text: "Progress from native streams syncs back automatically."
                                color: Appearance.colors.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                        StyledText {
                            text: "Settings"
                            color: Appearance.colors.colPrimary
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.settingsRequested()
                    }
                }

                ListView {
                    id: watchingList
                    WheelScroll {}
                    visible: root.anilistOk && root.watching.length > 0
                    Layout.fillWidth: true
                    Layout.preferredHeight: 136
                    orientation: ListView.Horizontal
                    spacing: 12
                    clip: true
                    topMargin: 4
                    bottomMargin: 4
                    leftMargin: 2
                    rightMargin: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.watching
                    delegate: StreamCard {
                        required property var modelData
                        readonly property var linkedState: {
                            const state = root.nativeForAniList(modelData);
                            if (!state)
                                return null;
                            const nativeEpisode = Number(state?.episode_number ?? 0);
                            const anilistProgress = Number(modelData?.progress ?? 0);
                            return anilistProgress === 0 || anilistProgress <= nativeEpisode ? state : null;
                        }
                        required property int index
                        selected: root.wcursor === index
                        poster: String(modelData?.poster ?? "")
                        title: String(modelData?.title ?? "")
                        subtitle: `${String(modelData?.status ?? "CURRENT") === "REPEATING"
                            ? "Rewatching" : "Watching"}${String(modelData?.format ?? "") !== ""
                                ? ` · ${modelData.format}` : ""}${linkedState ? " · resume" : " · find online"}`
                        meta: `${modelData?.progress ?? 0} / ${Number(modelData?.total ?? 0) > 0
                            ? modelData.total : "?"}`
                        badge: "ANILIST"
                        actionIcon: linkedState ? "play_arrow" : "travel_explore"
                        fraction: Number(modelData?.total ?? 0) > 0
                            ? Number(modelData?.progress ?? 0) / Number(modelData.total) : 0
                        onActivated: root.openAniList(modelData)
                    }
                }

                StyledText {
                    visible: root.anilistOk && MediatorService.anilistWatchingError !== ""
                    text: MediatorService.anilistWatchingError
                    color: Appearance.colors.colError
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                StyledText {
                    visible: root.anilistOk && !MediatorService.anilistWatchingBusy
                        && root.watching.length === 0 && MediatorService.anilistWatchingError === ""
                    text: "Nothing in Watching right now."
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            }

            // ── Title page ─────────────────────────────────────────────────
            AnimeTitle {
                id: titlePage
                Layout.fillWidth: true
                onLocalRequested: id => root.localRequested(id)
                visible: AnimeBrowseService.view === "title"
            }
        }
    }
}

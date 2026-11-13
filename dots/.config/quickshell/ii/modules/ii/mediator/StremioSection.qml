pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Stremio tab: catalog or search results as a poster grid, a title page with backdrop
 * and episodes, and the addon stream list. Search is driven by the browser's own search
 * field; playback runs in mpv. Stremio's app is never opened.
 */
Item {
    id: root

    signal localRequested(string id)

    property int season: 1
    readonly property var title: StremioService.title
    readonly property string view: StremioService.view
    readonly property var seasons: {
        const seen = ({});
        const out = [];
        for (const v of root.title?.videos ?? []) {
            if (v.season > 0 && !seen[v.season]) {
                seen[v.season] = true;
                out.push(v.season);
            }
        }
        return out;
    }
    readonly property var episodes: (root.title?.videos ?? []).filter(v => v.season === root.season)
    // Billboard candidates: the first catalog entries that have a backdrop
    readonly property var featured: StremioService.searching ? []
        : StremioService.items.slice(0, 14).filter(i => i.background).slice(0, 5)
    property int featuredIndex: 0
    onFeaturedChanged: if (root.featuredIndex >= root.featured.length) root.featuredIndex = 0
    readonly property int columns: Math.max(2, Math.floor(flick.width / 186))
    readonly property real cardWidth: Math.floor(flick.width / root.columns) - 1

    function clock(sec): string {
        const t = Math.max(0, Math.floor(Number(sec) || 0));
        const h = Math.floor(t / 3600);
        const m = Math.floor((t % 3600) / 60);
        const ss = String(t % 60).padStart(2, "0");
        return h > 0 ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
    }

    // Where this title was left, as a short label for the Resume button
    function resumeLabel(entry): string {
        if (!entry)
            return "";
        const target = StremioService.resumeTarget(entry);
        if (!target)
            return "Watched";
        const tag = entry.watched ? (target.number ?? "") : (entry.episode_number ?? "");
        const at = !entry.watched && entry.position > 5 ? " · " + root.clock(entry.position) : "";
        return "Resume" + (tag ? " " + tag : "") + at;
    }

    readonly property var entry: root.title ? StremioService.historyFor(root.title) : null
    readonly property var movieDownload: root.title ? StremioService.downloadState(root.title, String(root.title.id)) : null

    function dlLabel(d): string {
        if (!d)
            return "";
        if (d.progress >= 1)
            return "Downloaded";
        return d.state.startsWith("paused") || d.state.startsWith("stopped") ? "Paused " + Math.round(d.progress * 100) + "%"
            : "Downloading " + Math.round(d.progress * 100) + "%";
    }

    Component.onCompleted: {
        StremioService.loadHistory();
        if (StremioService.items.length === 0 && StremioService.view === "home")
            StremioService.top("movie");
    }

    Connections {
        target: StremioService
        function onTitleChanged() {
            if (root.seasons.length > 0 && !root.seasons.includes(root.season))
                root.season = root.seasons[0];
        }
    }

    // Room the host keeps at the top for the unified header, which scrolls with the page

    // ── Keyboard: a cursor over the browse cards (arrows move it, Enter opens) ──
    property int cursor: -1
    readonly property int cursorColumns: root.columns
    readonly property int cursorCount: StremioService.items.length

    function _show(index): void {
        const card = browseRepeater.itemAt(index);
        if (!card)
            return;
        const y = card.mapToItem(flick.contentItem, 0, 0).y;
        if (y < flick.contentY + root.stickyHeight)
            flick.contentY = Math.max(0, y - root.stickyHeight - 8);
        else if (y + card.height > flick.contentY + flick.height - 24)
            flick.contentY = y + card.height - flick.height + 32;
    }

    function scrollTop(): void {
        flick.contentY = 0;
    }

    /// Jump to a card (a negative index picks one at random); off-range values clamp
    function jumpCursor(index): void {
        if (root.view !== "home" || root.cursorCount === 0)
            return;
        root.cursor = index < 0 ? Math.floor(Math.random() * root.cursorCount)
            : Math.max(0, Math.min(root.cursorCount - 1, index));
        root._show(root.cursor);
    }

    // Title page and stream list take the arrows themselves (the host asks before routing)
    readonly property bool ownsKeys: root.view !== "home"
    property int epCursor: -1
    property int shelfCursor: -1
    /// 0 = "more like this", 1 = "top rated"
    property int shelfRow: 0
    /// Keyboard cursor on the title page's buttons (-1 none)
    property int btnCursor: -1
    function heroButtons() { return Array.from(titleHero.actionItems).filter(b => b.visible && b.enabled !== false); }
    onBtnCursorChanged: titleHero.focusItem = root.btnCursor >= 0 ? (heroButtons()[root.btnCursor] ?? null) : null
    function shelfList(row) { return row === 1 ? StremioService.topRated : StremioService.similar; }
    property bool heroFocus: false
    readonly property bool billboardShown: root.view === "home" && !StremioService.searching && root.featured.length > 0
    property int streamCursor: -1

    /// The episode Enter would continue with: where this show was left, else the first of the season
    readonly property string nextId: {
        const target = root.entry ? StremioService.resumeTarget(root.entry) : null;
        return target ? String(target.id) : "";
    }

    onViewChanged: {
        root.epCursor = -1;
        root.shelfCursor = -1;
        root.shelfRow = 0;
        root.btnCursor = -1;
        root.heroFocus = false;
        root.streamCursor = -1;
        flick.contentY = 0;
    }
    onSeasonChanged: root.epCursor = -1
    Connections {
        target: StremioService
        function onStreamFilterChanged() { root.streamCursor = -1; }
    }

    function _showItem(item): void {
        if (!item)
            return;
        const y = item.mapToItem(flick.contentItem, 0, 0).y;
        if (y < flick.contentY + 8)
            flick.contentY = Math.max(0, y - 8);
        else if (y + item.height > flick.contentY + flick.height - 16)
            flick.contentY = y + item.height - flick.height + 24;
    }

    function _stepList(count, current, dy, start): int {
        if (count <= 0)
            return -1;
        if (current < 0)
            return dy >= 0 ? Math.max(0, Math.min(count - 1, start)) : count - 1;
        return Math.max(0, Math.min(count - 1, current + dy));
    }

    /// True when the key was used. Up from the first row hands control back (cursor off).
    function moveCursor(dx, dy): bool {
        if (root.view === "streams") {
            if (dx !== 0 && dy === 0) {
                const opts = ["all"].concat(StremioService.qualityOptions);
                const i = Math.max(0, opts.indexOf(StremioService.streamFilter));
                StremioService.streamFilter = opts[Math.max(0, Math.min(opts.length - 1, i + dx))];
                root.streamCursor = -1;
                return true;
            }
            root.streamCursor = root._stepList(StremioService.streamRows.length, root.streamCursor, dy,
                Math.max(0, StremioService.recommendedIndex));
            root._showItem(streamRepeater.itemAt(root.streamCursor));
            return true;
        }
        if (root.view === "title") {
            const n = StremioService.similar.length;
            if (root.shelfCursor >= 0) {
                const cur = root.shelfList(root.shelfRow);
                if (dy > 0 && root.shelfRow === 0 && StremioService.topRated.length > 0) {
                    root.shelfRow = 1;
                    root.shelfCursor = Math.min(root.shelfCursor, StremioService.topRated.length - 1);
                    shelf2.show(root.shelfCursor);
                } else if (dy < 0 && root.shelfRow === 1) {
                    root.shelfRow = 0;
                    root.shelfCursor = Math.min(root.shelfCursor, n - 1);
                    shelf.show(root.shelfCursor);
                } else if (dy < 0) {
                    root.shelfCursor = -1;
                    if (root.title?.type === "series") {
                        root.epCursor = root.episodes.length - 1;
                        root._showItem(epRepeater.itemAt(root.epCursor));
                    } else {
                        root.btnCursor = 0;
                        flick.contentY = 0;
                    }
                } else if (dx !== 0) {
                    root.shelfCursor = Math.max(0, Math.min(cur.length - 1, root.shelfCursor + dx));
                    (root.shelfRow === 0 ? shelf : shelf2).show(root.shelfCursor);
                }
                return true;
            }
            const enterShelf = () => {
                if (n === 0)
                    return false;
                root.epCursor = -1;
                root.btnCursor = -1;
                root.shelfCursor = 0;
                root._showItem(shelf);
                return true;
            };
            if (root.title?.type !== "series") {
                // A movie has one thing to do (Enter plays); Down goes on to the shelf
                const nb = root.heroButtons().length;
                if (root.btnCursor < 0) {
                    root.btnCursor = 0;
                } else if (dx !== 0) {
                    root.btnCursor = Math.max(0, Math.min(nb - 1, root.btnCursor + dx));
                } else if (dy > 0) {
                    enterShelf();
                }
                return dy !== 0 || dx !== 0;
            }
            if (root.btnCursor >= 0) {
                const nb = root.heroButtons().length;
                if (dx !== 0) {
                    root.btnCursor = Math.max(0, Math.min(nb - 1, root.btnCursor + dx));
                } else if (dy > 0) {
                    root.btnCursor = -1;
                    root.epCursor = Math.max(0, root.episodes.findIndex(e => String(e.id) === root.nextId));
                    root._showItem(epRepeater.itemAt(root.epCursor));
                }
                return true;
            }
            if (dy < 0 && root.epCursor <= 0 && root.shelfCursor < 0) {
                root.epCursor = -1;
                root.btnCursor = 0;
                flick.contentY = 0;
                return true;
            }
            if (dx !== 0 && dy === 0) {
                const i = root.seasons.indexOf(root.season);
                const next = root.seasons[Math.max(0, Math.min(root.seasons.length - 1, i + dx))];
                if (next !== undefined)
                    root.season = next;
                return true;
            }
            if (dy > 0 && root.epCursor >= root.episodes.length - 1 && root.epCursor >= 0 && enterShelf())
                return true;
            const nextAt = root.episodes.findIndex(e => String(e.id) === root.nextId);
            root.epCursor = root._stepList(root.episodes.length, root.epCursor, dy, nextAt);
            root._showItem(epRepeater.itemAt(root.epCursor));
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
            if (dy > 0 && n >= root.cursorCount && root.cursor < root.cursorCount - 1)
                n = root.cursorCount - 1;
            root.cursor = Math.max(0, Math.min(root.cursorCount - 1, n));
        }
        root._show(root.cursor);
        return true;
    }

    /// Ctrl+Enter: pick the stream by hand for what the cursor is on
    function chooseCursor(): bool {
        if (root.view !== "title" || !root.title)
            return false;
        if (root.title.type !== "series") {
            StremioService.loadStreams(root.title.id, root.title.name);
            return true;
        }
        const ep = root.episodes[root.epCursor];
        if (!ep)
            return false;
        StremioService.loadStreams(ep.id, "S" + ep.season + "E" + ep.episode);
        return true;
    }

    /// The library title behind the card under the cursor, if it has one
    function localForCursor(): var {
        const card = browseRepeater.itemAt(root.cursor);
        return root.cursor >= 0 && card ? card.local : null;
    }

    function activateCursor(): bool {
        if (root.heroFocus) {
            const f = root.featured[root.featuredIndex];
            if (!f)
                return false;
            StremioService.openTitle(f);
            return true;
        }
        if (root.view === "title" && root.shelfCursor >= 0) {
            const it = root.shelfList(root.shelfRow)[root.shelfCursor];
            if (!it)
                return false;
            StremioService.openTitle(it);
            return true;
        }
        if (root.view === "streams") {
            const st = StremioService.streamRows[root.streamCursor];
            if (!st)
                return false;
            StremioService.play(st);
            return true;
        }
        if (root.view === "title" && root.btnCursor >= 0) {
            const b = root.heroButtons()[root.btnCursor];
            if (!b)
                return false;
            b.clicked();
            return true;
        }
        if (root.view === "title") {
            if (root.title?.type !== "series") {
                StremioService.playEpisode(String(root.title.id));
                return true;
            }
            const ep = root.episodes[root.epCursor];
            if (!ep)
                return false;
            StremioService.playEpisode(ep.id);
            return true;
        }
        if (root.cursor < 0 || root.cursor >= root.cursorCount)
            return false;
        StremioService.openTitle(StremioService.items[root.cursor]);
        return true;
    }

    onCursorCountChanged: if (root.cursor >= root.cursorCount) root.cursor = -1

    /// Set by the host: how much of the page the pinned toolbar covers when scrolled
    property real stickyHeight: 0
    property real headerHeight: 0
    readonly property real scrollOffset: flick.contentY

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight + 28
        onAtYEndChanged: if (atYEnd && root.view === "home") StremioService.more()
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 14

            // The unified header from the host floats over this gap and scrolls away with the page
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(0, root.headerHeight - body.spacing)
            }

            // ── Home ───────────────────────────────────────────────────────
            // Featured billboard: the top few of the catalog, one at a time
            BackdropHero {
                id: billboard
                readonly property var f: root.featured[root.featuredIndex] ?? null
                visible: root.view === "home" && !StremioService.searching && root.featured.length > 0
                name: f?.name ?? ""
                logo: f?.logo ?? ""
                background: f?.background ?? ""
                description: f?.description ?? ""
                rating: f?.rating ?? ""
                facts: [f?.type === "series" ? "Series" : "Movie", f?.year, f?.runtime]
                    .concat((f?.genres ?? []).slice(0, 3))
                dots: root.featured.length
                dotIndex: root.featuredIndex
                focused: root.heroFocus
                onDotRequested: i => root.featuredIndex = i

                ClockButton {
                    symbol: "play_arrow"
                    label: "Open"
                    variant: "filled"
                    onClicked: StremioService.openTitle(billboard.f)
                }
                ClockButton {
                    readonly property var local: billboard.f
                        ? MediatorService.ownedFor([billboard.f.name], billboard.f.year) : null
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
                running: root.view === "home" && root.featured.length > 1 && !billboard.hovered && root.visible
                onTriggered: root.featuredIndex = (root.featuredIndex + 1) % root.featured.length
            }

            // What the cards below are: "Popular movies · Drama", or the search being shown
            RowLayout {
                visible: root.view === "home"
                Layout.fillWidth: true
                Layout.topMargin: 6
                spacing: 8

                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: StremioService.heading
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                }
            }

            // Sort, then genres (or years) scrolling sideways: one quiet row each
            RowLayout {
                visible: root.view === "home" && !StremioService.searching
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: [{ "v": "popular", "t": "Popular" }, { "v": "top", "t": "Top rated" }, { "v": "year", "t": "By year" }]
                    FilterChip {
                        required property var modelData
                        label: modelData.t
                        selected: StremioService.sort === modelData.v
                        onClicked: StremioService.browse(StremioService.kind, modelData.v,
                            modelData.v === "year" ? StremioService.years[0] : "")
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 1
                    Layout.preferredHeight: 20
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    color: Appearance.colors.colOutlineVariant
                }

                Flickable {
                    id: filterRow
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    contentWidth: filters.implicitWidth
                    contentHeight: height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.HorizontalFlick
                    WheelScroll {}

                    Row {
                        id: filters
                        spacing: 6
                        height: parent.height

                        FilterChip {
                            visible: StremioService.sort !== "year"
                            label: "All"
                            selected: StremioService.genre === ""
                            onClicked: StremioService.browse(StremioService.kind, StremioService.sort, "")
                        }
                        Repeater {
                            model: StremioService.sort === "year" ? StremioService.years : StremioService.genres
                            FilterChip {
                                required property string modelData
                                label: modelData
                                selected: StremioService.genre === modelData
                                onClicked: StremioService.browse(StremioService.kind, StremioService.sort, modelData)
                            }
                        }
                    }
                }
            }

            Flow {
                visible: root.view === "home" && StremioService.busy && StremioService.items.length === 0
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: root.columns * 2
                    CoverSkeleton { width: root.cardWidth }
                }
            }

            Flow {
                visible: root.view === "home"
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    id: browseRepeater
                    model: StremioService.items

                    CoverCard {
                        required property var modelData
                        required property int index
                        selected: root.cursor === index
                        readonly property var local: MediatorService.ownedFor([modelData.name], modelData.year)
                        owned: local !== null
                        width: root.cardWidth
                        poster: modelData.poster
                        name: modelData.name
                        rating: modelData.rating
                        subtitle: [modelData.type === "series" ? "Series" : "Movie", modelData.year]
                            .filter(x => x).join(" · ")
                        onActivated: StremioService.openTitle(modelData)
                    }
                }
            }

            ClockButton {
                visible: root.view === "home" && StremioService.items.length > 0
                    && StremioService.moreAvailable && !StremioService.searching
                Layout.alignment: Qt.AlignHCenter
                symbol: StremioService.loadingMore ? "hourglass_top" : "expand_more"
                label: StremioService.loadingMore ? "Loading…" : "Load more"
                variant: "tonal"
                enabled: !StremioService.loadingMore
                onClicked: StremioService.more()
            }

            // ── Title page ─────────────────────────────────────────────────
            BackdropHero {
                id: titleHero
                visible: root.view === "title"
                tall: true
                name: root.title?.name ?? ""
                logo: root.title?.logo ?? ""
                poster: root.title?.poster ?? ""
                background: root.title?.background ?? ""
                description: root.title?.description ?? ""
                rating: root.title?.rating ?? ""
                facts: [root.title?.type === "series" ? "Series" : "Movie", root.title?.year, root.title?.runtime]
                    .concat((root.title?.genres ?? []).slice(0, 4))
                onBackRequested: StremioService.back()

                ClockButton {
                    readonly property var local: root.view === "title"
                        ? MediatorService.ownedFor([root.title?.name], root.title?.year) : null
                    visible: local !== null
                    symbol: "video_library"
                    label: "In your library"
                    variant: "tonal"
                    onClicked: root.localRequested(local.id)
                }
                ClockButton {
                    visible: root.view === "title" && root.entry !== null
                        && StremioService.resumeTarget(root.entry) !== null
                    symbol: "play_arrow"
                    label: root.resumeLabel(root.entry)
                    variant: "filled"
                    onClicked: StremioService.resume(root.entry)
                }
                ClockButton {
                    visible: root.view === "title" && root.title?.type !== "series"
                        && !(root.entry !== null && StremioService.resumeTarget(root.entry) !== null)
                    symbol: "play_arrow"
                    label: "Play"
                    variant: "filled"
                    enabled: !StremioService.starting
                    onClicked: StremioService.playEpisode(String(root.title.id))
                }
                ClockButton {
                    visible: root.view === "title" && root.title?.type === "series" && root.episodes.length > 0
                        && !(root.entry !== null && StremioService.resumeTarget(root.entry) !== null)
                    symbol: "play_arrow"
                    label: "Play S" + (root.title?.videos?.find(v => v.season > 0)?.season ?? 1) + "E1"
                    variant: "filled"
                    enabled: !StremioService.starting
                    onClicked: StremioService.playEpisode((root.title.videos.find(v => v.season > 0) ?? root.episodes[0]).id)
                }
                ClockButton {
                    visible: root.view === "title" && root.title?.type !== "series"
                    symbol: "list"
                    label: "Choose stream"
                    variant: "tonal"
                    onClicked: StremioService.loadStreams(root.title.id, root.title.name)
                }
                ClockButton {
                    visible: root.view === "title" && root.title?.type === "series" && root.episodes.length > 0
                    symbol: "download"
                    label: "Download season " + root.season
                    variant: "tonal"
                    onClicked: StremioService.downloadSeason(root.season)
                }
                ClockButton {
                    visible: root.view === "title" && root.title?.type !== "series"
                    symbol: root.movieDownload ? (root.movieDownload.progress >= 1 ? "download_done" : "downloading") : "download"
                    label: root.movieDownload ? root.dlLabel(root.movieDownload) : "Download"
                    variant: "tonal"
                    enabled: !root.movieDownload
                    onClicked: StremioService.downloadBest(String(root.title.id))
                }
                ClockButton {
                    visible: root.view === "title" && (root.title?.trailer ?? "") !== ""
                    symbol: "smart_display"
                    label: "Trailer"
                    variant: "tonal"
                    onClicked: Qt.openUrlExternally("https://www.youtube.com/watch?v=" + root.title.trailer)
                }
            }

            // ── About: the facts and the people, straight on the page ──
            InfoGrid {
                visible: root.view === "title"
                Layout.fillWidth: true
                Layout.topMargin: 4
                rows: [
                    { "k": "Director", "v": (root.title?.director ?? []).join(", ") },
                    { "k": "Writer", "v": (root.title?.writer ?? []).join(", ") },
                    { "k": "Released", "v": root.title?.released ?? "" },
                    { "k": "Country", "v": root.title?.country ?? "" },
                    { "k": "Status", "v": root.title?.status ?? "" },
                    { "k": "Awards", "v": root.title?.awards ?? "" }
                ]
            }

            CastRow {
                visible: root.view === "title" && names.length > 0
                Layout.fillWidth: true
                names: root.title?.cast ?? []
            }

            // ── Episodes ───────────────────────────────────────────────────
            Flow {
                visible: root.view === "title" && root.seasons.length > 1
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    model: root.seasons

                    FilterChip {
                        required property int modelData
                        label: "Season " + modelData
                        selected: root.season === modelData
                        onClicked: root.season = modelData
                    }
                }
            }

            StyledText {
                visible: root.view === "title" && root.title?.type === "series" && root.episodes.length > 0
                Layout.fillWidth: true
                text: {
                    const total = root.episodes.length;
                    const seen = root.episodes.filter(e => StremioService.episodeState(root.title, e.id)?.watched).length;
                    return `Season ${root.season} · ${total} episodes` + (seen > 0 ? ` · ${seen} watched` : "")
                        + "   ↑↓ choose · Enter play · Ctrl+Enter pick stream";
                }
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }

            ColumnLayout {
                visible: root.view === "title" && root.title?.type === "series"
                Layout.fillWidth: true
                spacing: 6

                Repeater {
                    id: epRepeater
                    model: root.episodes

                    Rectangle {
                        id: ep
                        required property var modelData
                        required property int index
                        readonly property var watchState: StremioService.episodeState(root.title, modelData.id)
                        readonly property var dl: StremioService.downloadState(root.title, modelData.id)
                        readonly property bool upNext: String(modelData.id) === root.nextId
                        readonly property bool selected: root.epCursor === index
                        readonly property bool partial: watchState !== null && !watchState.watched && watchState.position > 5
                        readonly property real fraction: partial && Number(watchState.duration) > 0
                            ? Math.min(1, watchState.position / watchState.duration) : 0
                        readonly property bool unreleased: modelData.released !== ""
                            && modelData.released > new Date().toISOString().slice(0, 10)

                        Layout.fillWidth: true
                        implicitHeight: 92
                        radius: Appearance.rounding.normal
                        color: epArea.containsMouse || ep.selected ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                        border.width: ep.selected ? 2 : 0
                        border.color: Appearance.colors.colPrimary
                        opacity: ep.unreleased ? 0.6 : 1
                        Behavior on color {
                            ColorAnimation { duration: Appearance.dur(120) }
                        }

                        RowLayout {
                            anchors { fill: parent; margins: 10; rightMargin: 12 }
                            spacing: 14

                            // Still from the episode, with the resume position along its foot
                            RoundedBox {
                                Layout.preferredWidth: 128
                                Layout.preferredHeight: 72
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2

                                Image {
                                    anchors.fill: parent
                                    source: ep.modelData.thumbnail ? MediatorService.cachedImage(ep.modelData.thumbnail) : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 320
                                    opacity: status === Image.Ready ? (ep.watchState?.watched ? 0.55 : 1) : 0
                                    Behavior on opacity {
                                        NumberAnimation { duration: Appearance.dur(180) }
                                    }
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    text: ep.modelData.episode
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.huge
                                    font.weight: Font.DemiBold
                                    visible: !ep.modelData.thumbnail
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: epArea.containsMouse || ep.selected
                                    text: "play_arrow"
                                    fill: 1
                                    iconSize: 34
                                    color: "white"
                                }
                                Rectangle {
                                    visible: ep.upNext
                                    anchors { left: parent.left; top: parent.top; margins: 5 }
                                    implicitWidth: upText.implicitWidth + 12
                                    implicitHeight: 18
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colPrimary
                                    StyledText {
                                        id: upText
                                        anchors.centerIn: parent
                                        text: ep.partial ? "RESUME" : "UP NEXT"
                                        color: Appearance.colors.colOnPrimary
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.Bold
                                    }
                                }
                                MaterialSymbol {
                                    visible: ep.watchState?.watched === true
                                    anchors { right: parent.right; top: parent.top; margins: 4 }
                                    text: "check_circle"
                                    fill: 1
                                    iconSize: 20
                                    color: Appearance.colors.colPrimary
                                }
                                Rectangle {
                                    visible: ep.partial
                                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                    height: 4
                                    color: "#66000000"
                                    Rectangle {
                                        width: ep.fraction > 0 ? parent.width * ep.fraction : parent.width * 0.35
                                        height: parent.height
                                        color: Appearance.colors.colPrimary
                                    }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    StyledText {
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                        text: `${ep.modelData.episode}. ` + (ep.modelData.title || "Episode " + ep.modelData.episode)
                                        color: Appearance.colors.colOnLayer0
                                        font.weight: Font.Medium
                                    }
                                    StyledText {
                                        visible: ep.partial
                                        text: "Left at " + root.clock(ep.watchState?.position ?? 0)
                                        color: Appearance.colors.colPrimary
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                    StyledText {
                                        visible: ep.dl !== null
                                        text: root.dlLabel(ep.dl)
                                        color: Appearance.colors.colTertiary
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                    StyledText {
                                        text: ep.unreleased ? "Airs " + ep.modelData.released : ep.modelData.released
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                    text: ep.modelData.overview
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }

                            ClockButton {
                                iconOnly: true
                                variant: "text"
                                symbol: "list"
                                label: "Choose a stream"
                                onClicked: StremioService.loadStreams(ep.modelData.id,
                                    "S" + ep.modelData.season + "E" + ep.modelData.episode)
                            }
                            ClockButton {
                                iconOnly: true
                                variant: "text"
                                symbol: ep.dl ? (ep.dl.progress >= 1 ? "download_done" : "downloading") : "download"
                                label: ep.dl ? root.dlLabel(ep.dl) : "Download this episode"
                                enabled: !ep.dl
                                onClicked: StremioService.downloadBest(String(ep.modelData.id))
                            }
                        }
                        MouseArea {
                            id: epArea
                            anchors { left: parent.left; top: parent.top; bottom: parent.bottom; right: parent.right; rightMargin: 112 }
                            hoverEnabled: true
                            cursorShape: StremioService.starting ? Qt.BusyCursor : Qt.PointingHandCursor
                            onClicked: StremioService.playEpisode(ep.modelData.id)
                            onContainsMouseChanged: if (containsMouse) root.epCursor = ep.index
                        }
                    }
                }
            }

            // ── Streams ────────────────────────────────────────────────────
            RowLayout {
                visible: root.view === "streams"
                Layout.fillWidth: true
                spacing: 6

                ClockButton {
                    iconOnly: true
                    variant: "tonal"
                    symbol: "arrow_back"
                    label: "Back (Esc)"
                    onClicked: StremioService.back()
                }
                StyledText {
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    text: StremioService.busy ? "Looking for streams for " + StremioService.pickedLabel + "…"
                        : "Streams for " + StremioService.pickedLabel
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.larger
                    font.weight: Font.Medium
                }
                FilterChip {
                    visible: StremioService.qualityOptions.length > 1
                    label: "All"
                    selected: StremioService.streamFilter === "all"
                    onClicked: StremioService.streamFilter = "all"
                }
                Repeater {
                    model: StremioService.qualityOptions
                    FilterChip {
                        required property string modelData
                        label: modelData
                        selected: StremioService.streamFilter === modelData
                        onClicked: StremioService.streamFilter = modelData
                    }
                }
            }

            ColumnLayout {
                visible: root.view === "streams"
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    id: streamRepeater
                    model: StremioService.streamRows

                    StremioStreamRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        stream: modelData
                        selected: root.streamCursor === index
                        recommended: index === StremioService.recommendedIndex && StremioService.streamRows.length > 1
                        onActivated: StremioService.play(modelData)
                        onDownloadRequested: StremioService.download(modelData)
                    }
                }
            }

            StyledText {
                visible: root.view === "streams" && !StremioService.busy && StremioService.streamRows.length === 0
                Layout.fillWidth: true
                text: "No streams found for " + StremioService.pickedLabel + ". Try another quality, or check the sources in Settings."
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            // Home with nothing to show: say why and offer a retry
            ColumnLayout {
                visible: root.view === "home" && !StremioService.busy && StremioService.items.length === 0
                Layout.fillWidth: true
                Layout.topMargin: 40
                spacing: 10
                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: StremioService.searching ? "search_off" : "cloud_off"
                    iconSize: 44
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: StremioService.searching ? "Nothing found for that search" : "Couldn't load the catalog"
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.larger
                }
                ClockButton {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "refresh"
                    label: StremioService.searching ? "Back to browsing" : "Try again"
                    variant: "tonal"
                    onClicked: StremioService.top(StremioService.kind)
                }
            }

            TitleShelf {
                id: shelf
                visible: root.view === "title" && items.length > 0
                Layout.fillWidth: true
                Layout.topMargin: 8
                heading: root.title?.type === "series" ? "More series like this" : "More movies like this"
                items: StremioService.similar
                cursor: root.shelfRow === 0 ? root.shelfCursor : -1
                onActivated: item => StremioService.openTitle(item)
            }

            TitleShelf {
                id: shelf2
                visible: root.view === "title" && items.length > 0
                Layout.fillWidth: true
                heading: `Top rated ${String((root.title?.genres ?? [])[0] ?? "").toLowerCase()} ${root.title?.type === "series" ? "series" : "movies"}`
                items: StremioService.topRated
                cursor: root.shelfRow === 1 ? root.shelfCursor : -1
                onActivated: item => StremioService.openTitle(item)
            }

            StyledText {
                visible: StremioService.notice.length > 0
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: StremioService.notice
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }
}

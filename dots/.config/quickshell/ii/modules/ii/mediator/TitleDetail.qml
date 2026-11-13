pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One title opened: poster, the Resume / Play button and the episode list by season.
 * `title` is the row from the grid (poster, counts); MediatorService.detail holds the
 * entries once `mediator show --json` has answered.
 */
Item {
    id: root

    required property var title

    signal closeRequested()
    signal playRequested(string path)
    signal continueRequested()
    signal refocusRequested()
    signal streamStarted()

    property bool closeAfterStream: false
    readonly property var detail: MediatorService.detail
    readonly property var entries: root.detail?.entries ?? []

    // Season/kind groups, in the order the entries come
    readonly property var groups: {
        const seen = {};
        const out = [];
        for (const e of root.entries) {
            const key = root.groupKey(e);
            if (seen[key])
                continue;
            seen[key] = true;
            out.push({ key: key, label: root.groupLabel(e) });
        }
        // Seasons first, then specials, movies and extras
        return out.sort((a, b) => (a.key.startsWith("S") ? 0 : 1) - (b.key.startsWith("S") ? 0 : 1));
    }
    /// meta.py's short record with info.py's richer one laid over it
    readonly property var inf: root.detail?.info ?? ({})
    readonly property var m: {
        const base = root.detail?.meta ?? ({});
        const i = root.inf;
        const merged = Object.assign({}, base, i);
        merged.synopsis = i.description || base.synopsis || "";
        merged.cast = i.cast ? i.cast.map(c => c.name).filter(n => n) : (base.cast ?? []);
        return merged;
    }
    readonly property var castPeople: (root.inf.cast ?? []).filter(c => c.name)
    readonly property string airingText: {
        const n = root.inf.next_airing;
        if (!n)
            return "";
        const when = n.at ? new Date(n.at * 1000) : (n.date ? new Date(n.date + "T12:00:00") : null);
        if (!when)
            return "";
        const days = Math.round((when.getTime() - Date.now()) / 86400000);
        const rel = days <= 0 ? "today" : days === 1 ? "tomorrow" : `in ${days} days`;
        return `Episode ${n.episode} airs ${rel}`;
    }
    readonly property bool isMovie: root.title.lib === "movies" || root.title.episodes === 0
    readonly property real rating: root.m.rating ?? 0
    property bool expanded: false
    property bool editingPoster: false
    property bool streamOpen: false

    /// Episodes the metadata says exist and have aired, in seasons you already have some of,
    /// that are not in the library
    readonly property var missing: {
        if (root.isMovie || root.entries.length === 0)
            return [];
        const have = new Set();
        const seasonsHeld = new Set();
        for (const e of root.entries) {
            if (e.kind !== "episode" || e.episode === undefined || e.episode === null)
                continue;
            const season = Number(e.season ?? 1) || 1;
            have.add(`${season}:${Number(e.episode)}`);
            seasonsHeld.add(season);
        }
        const today = new Date().toISOString().slice(0, 10);
        let expected = (root.inf.episodes ?? []).map(e => ({
            season: Number(e.season), number: Number(e.number), title: e.title ?? "", airdate: e.airdate ?? ""
        }));
        if (expected.length === 0) {
            for (const sn of (root.inf.seasons ?? []))
                for (let n = 1; n <= Number(sn.episodes ?? 0); n++)
                    expected.push({ season: Number(sn.season), number: n, title: "", airdate: "" });
        }
        return expected.filter(e => e.season >= 1 && e.number >= 1 && seasonsHeld.has(e.season)
            && (!e.airdate || e.airdate <= today) && !have.has(`${e.season}:${e.number}`));
    }

    // Year, runtime and the rest as one line
    readonly property var facts: {
        const out = [];
        const year = root.title.year ?? root.m.year;
        if (year)
            out.push(String(year));
        if (root.m.runtime)
            out.push(root.durationText(root.m.runtime) + (root.isMovie ? "" : " per episode"));
        if (!root.isMovie) {
            const t = root.title;
            if (t.seasons > 0)
                out.push(`${t.seasons} season${t.seasons === 1 ? "" : "s"}`);
            if (t.episodes > 0)
                out.push(`${t.episodes} episode${t.episodes === 1 ? "" : "s"}`);
        }
        if (root.m.studio)
            out.push(root.m.studio);
        if (root.m.status && !root.isMovie)
            out.push(root.m.status);
        return out;
    }
    readonly property string credits: {
        const parts = [];
        if (root.m.director)
            parts.push(`Directed by ${root.m.director}`);
        if ((root.m.cast ?? []).length > 0)
            parts.push(`Starring ${root.m.cast.join(", ")}`);
        return parts.join("   ·   ");
    }

    // The single file of a movie, and how far through it you are
    readonly property var movieEntry: root.isMovie ? (root.entries[0] ?? null) : null
    readonly property bool movieDone: root.movieEntry?.progress?.watched ?? false
    readonly property string movieFile: root.movieEntry ? root.movieEntry.path.split("/").pop() : ""
    readonly property real movieFrac: {
        const p = root.movieEntry?.progress;
        return p && p.duration > 0 && !p.watched ? Math.min(1, p.position / p.duration) : 0;
    }
    readonly property string movieProgressText: {
        const p = root.movieEntry?.progress;
        return p ? `Stopped at ${MediatorService.clock(p.position)} of ${MediatorService.clock(p.duration)}` : "";
    }

    property string group: ""
    /// The season the list is on, 0 for specials, movies and extras
    readonly property int groupSeason: /^S\d+$/.test(root.group) ? Number(root.group.slice(1)) : 0
    readonly property var missingHere: root.groupSeason > 0 ? root.missing.filter(e => e.season === root.groupSeason) : []
    /// This group's files, with the episodes that are not in the library in their place
    readonly property var shown: {
        const local = root.entries.filter(e => root.groupKey(e) === root.group);
        if (root.missingHere.length === 0)
            return local;
        const pad = n => String(n).padStart(2, "0");
        const gone = root.missingHere.map(e => ({
            kind: "episode", season: e.season, episode: e.number, missingEp: true, missingRef: e,
            code: `S${pad(e.season)}E${pad(e.number)}`, name: e.title, path: "",
            episode_info: { title: e.title, airdate: e.airdate }
        }));
        return local.concat(gone).sort((a, b) => Number(a.episode ?? 1e9) - Number(b.episode ?? 1e9));
    }
    property int cur: 0

    function groupKey(e): string {
        return e.kind === "episode" ? `S${e.season ?? 0}` : e.kind;
    }

    function groupLabel(e): string {
        if (e.kind === "episode")
            return e.season ? `Season ${e.season}` : "Episodes";
        return ({ special: "Specials", movie: "Movies", extra: "Extras" })[e.kind] ?? e.kind;
    }

    function stremioId(): string {
        const candidates = [root.m.imdb_id, root.m.imdb, root.m.imdbId,
            root.detail?.imdb_id, root.title.imdb_id];
        for (const value of candidates) {
            const text = String(value ?? "").trim();
            if (/^tt[0-9]+$/.test(text))
                return text;
        }
        const hit = JSON.stringify(root.m).match(/tt[0-9]{6,}/);
        return hit ? hit[0] : "";
    }

    function openInStremio(): void {
        const id = root.stremioId();
        if (id.length > 0) {
            StremioService.openTitle({ "id": id, "type": root.isMovie ? "movie" : "series",
                "name": String(root.title.name ?? ""), "year": String(root.title.year ?? ""),
                "poster": String(root.title.poster ?? "") });
            return;
        }
        const title = String(root.title.name ?? root.m.title ?? root.m.name ?? "").trim();
        if (title.length > 0)
            StremioService.search(title);
    }

    function durationText(min): string {
        return min >= 60 ? `${Math.floor(min / 60)}h ${min % 60}m` : `${min} min`;
    }

    readonly property string continueLabel: {
        const n = root.detail?.next ?? root.title.next;
        if (!n)
            return "Play";
        const at = n.code ? ` ${n.code}` : "";
        if (n.reason === "resume")
            return root.isMovie ? `Resume from ${MediatorService.clock(n.position)}` : `Resume${at} · ${MediatorService.clock(n.position)}`;
        if (n.reason === "replay")
            return root.isMovie ? "Watch again" : `Watch again${at}`;
        if (n.reason === "next")
            return `Next${at}`;
        return root.isMovie ? "Play movie" : `Play${at}`;
    }

    // Land on the group that holds what plays next
    function pickStart(): void {
        const code = (root.detail?.next ?? root.title.next)?.code;
        const hit = root.entries.find(e => e.code === code);
        root.group = hit ? root.groupKey(hit) : (root.groups[0]?.key ?? "");
        const i = root.shown.findIndex(e => e.code === code);
        root.cur = Math.max(0, i);
        Qt.callLater(() => episodes.positionViewAtIndex(root.cur, ListView.Contain));
    }

    onGroupsChanged: if (root.group === "" || !root.groups.some(g => g.key === root.group)) root.pickStart()

    function move(delta): void {
        if (root.shown.length === 0)
            return;
        root.cur = Math.max(0, Math.min(root.shown.length - 1, root.cur + delta));
        episodes.positionViewAtIndex(root.cur, ListView.Contain);
    }

    function moveGroup(delta): void {
        const i = root.groups.findIndex(g => g.key === root.group);
        const n = root.groups[Math.max(0, Math.min(root.groups.length - 1, i + delta))];
        if (n) {
            root.group = n.key;
            root.cur = 0;
        }
    }

    function playCurrent(): void {
        if (root.isMovie) {
            root.continueRequested();
            return;
        }
        const e = root.shown[root.cur];
        if (e?.missingEp)
            missingCtl.item?.stream(e.missingRef);
        else if (e)
            root.playRequested(e.path);
    }

    function toggleWatched(): void {
        if (root.isMovie) {
            MediatorService.setWatchedAll(root.title.id, !root.movieDone);
            return;
        }
        const e = root.shown[root.cur];
        if (e)
            MediatorService.setWatched(root.title.id, e.code, !(e.progress?.watched ?? false));
    }

    function togglePosterEditor(): void {
        root.editingPoster = !root.editingPoster;
        if (root.editingPoster) {
            MediatorService.posterMessage = "";
            posterField.input.forceActiveFocus();
        } else {
            root.refocusRequested();
        }
    }

    onVisibleChanged: if (!visible) root.editingPoster = false

    function handleKey(event): bool {
        if (root.streamOpen)
            return false;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Backspace:
            root.closeRequested();
            return true;
        case Qt.Key_Down:
            root.move(1);
            return true;
        case Qt.Key_Up:
            root.move(-1);
            return true;
        case Qt.Key_Left:
            root.moveGroup(-1);
            return true;
        case Qt.Key_Right:
            root.moveGroup(1);
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (event.modifiers & Qt.ShiftModifier)
                root.continueRequested();
            else
                root.playCurrent();
            return true;
        case Qt.Key_C:
            root.continueRequested();
            return true;
        case Qt.Key_W:
            root.toggleWatched();
            return true;
        case Qt.Key_P:
            root.togglePosterEditor();
            return true;
        }
        return false;
    }

    // ── layout: a compact hero, then the episodes with room to breathe, About on the side ──
    readonly property bool wide: root.width >= 1050
    readonly property bool hasBackdrop: (root.title.banner ?? "") !== ""

    ColumnLayout {
        anchors.fill: parent
        spacing: 18

        // Hero: backdrop, poster, title, facts, actions
        RoundedBox {
            Layout.fillWidth: true
            Layout.preferredHeight: 268
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            Image {
                anchors.fill: parent
                source: root.hasBackdrop ? `file://${root.title.banner}` : MediatorService.posterUrl(root.title.poster)
                fillMode: Image.PreserveAspectCrop
                verticalAlignment: root.hasBackdrop ? Image.AlignVCenter : Image.AlignTop
                asynchronous: true
                sourceSize.width: root.hasBackdrop ? 1600 : 500
                opacity: root.hasBackdrop ? 1 : 0.5
            }
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0; color: Qt.rgba(0, 0, 0, 0.88) }
                    GradientStop { position: 0.55; color: Qt.rgba(0, 0, 0, 0.62) }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.25) }
                }
            }

            RowLayout {
                anchors { fill: parent; margins: 24 }
                spacing: 26

                RoundedBox {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredHeight: 220
                    Layout.preferredWidth: 147
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    Image {
                        anchors.fill: parent
                        source: MediatorService.posterUrl(root.title.poster)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 460
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    RowLayout {
                        spacing: 10
                        Rectangle {
                            implicitWidth: backRow.implicitWidth + 22
                            implicitHeight: 30
                            radius: Appearance.rounding.full
                            color: backArea.containsMouse ? "#44ffffff" : "#26ffffff"
                            RowLayout {
                                id: backRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol { text: "arrow_back"; iconSize: 17; color: "white" }
                                StyledText { text: "Back"; color: "white"; font.pixelSize: Appearance.font.pixelSize.smaller }
                            }
                            MouseArea {
                                id: backArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.closeRequested()
                            }
                        }
                        StyledText {
                            text: root.isMovie ? "MOVIE" : (root.title.lib ?? "")
                            color: "#bbffffff"
                            font.capitalization: Font.AllUppercase
                            font.letterSpacing: 1.4
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            visible: root.airingText !== ""
                            implicitWidth: airRow.implicitWidth + 20
                            implicitHeight: 28
                            radius: Appearance.rounding.full
                            color: Appearance.colors.colTertiaryContainer
                            RowLayout {
                                id: airRow
                                anchors.centerIn: parent
                                spacing: 5
                                MaterialSymbol { text: "schedule"; iconSize: 16; color: Appearance.colors.colOnTertiaryContainer }
                                StyledText { text: root.airingText; color: Appearance.colors.colOnTertiaryContainer; font.pixelSize: Appearance.font.pixelSize.smaller }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.title.name ?? ""
                        elide: Text.ElideRight
                        color: "white"
                        font.pixelSize: 34
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 12
                        Rectangle {
                            visible: root.rating > 0
                            implicitWidth: ratingRow.implicitWidth + 18
                            implicitHeight: 26
                            radius: Appearance.rounding.full
                            color: "#33ffffff"
                            RowLayout {
                                id: ratingRow
                                anchors.centerIn: parent
                                spacing: 4
                                MaterialSymbol { text: "star"; fill: 1; iconSize: 15; color: "#ffd166" }
                                StyledText { text: root.rating.toFixed(1); color: "white"; font.weight: Font.DemiBold; font.pixelSize: Appearance.font.pixelSize.smaller }
                                StyledText { text: root.m.rating_source ?? ""; color: "#99ffffff"; font.pixelSize: Appearance.font.pixelSize.smallest }
                            }
                        }
                        Rectangle {
                            visible: (root.m.certification ?? "") !== ""
                            implicitWidth: certText.implicitWidth + 14
                            implicitHeight: 24
                            radius: 5
                            color: "transparent"
                            border.width: 1
                            border.color: "#88ffffff"
                            StyledText {
                                id: certText
                                anchors.centerIn: parent
                                text: root.m.certification ?? ""
                                color: "#ddffffff"
                                font.pixelSize: Appearance.font.pixelSize.smallest
                            }
                        }
                        SourceTag {
                            source: root.title.source ?? "local"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.facts.join("  ·  ")
                            elide: Text.ElideRight
                            color: "#ddffffff"
                            font.pixelSize: Appearance.font.pixelSize.small
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: (root.m.genres ?? []).length > 0
                        text: (root.m.genres ?? []).join("  ·  ")
                        elide: Text.ElideRight
                        color: "#bbffffff"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 860
                        visible: !root.wide && (root.m.synopsis ?? "") !== ""
                        text: root.m.synopsis ?? ""
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                        elide: Text.ElideRight
                        lineHeight: 1.2
                        color: "#eeffffff"
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        spacing: 10
                        Rectangle {
                            implicitWidth: playRow.implicitWidth + 36
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: playArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                            RowLayout {
                                id: playRow
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol { text: "play_arrow"; fill: 1; iconSize: 24; color: Appearance.colors.colOnPrimary }
                                StyledText { text: root.continueLabel; color: Appearance.colors.colOnPrimary; font.weight: Font.Medium }
                            }
                            MouseArea {
                                id: playArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.continueRequested()
                            }
                        }
                        Rectangle {
                            visible: root.isMovie
                            implicitWidth: markRow.implicitWidth + 30
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: markArea.containsMouse ? "#55ffffff" : "#33ffffff"
                            RowLayout {
                                id: markRow
                                anchors.centerIn: parent
                                spacing: 7
                                MaterialSymbol { text: root.movieDone ? "check_circle" : "radio_button_unchecked"; fill: root.movieDone ? 1 : 0; iconSize: 21; color: "white" }
                                StyledText { text: root.movieDone ? "Watched" : "Mark watched"; color: "white" }
                            }
                            MouseArea {
                                id: markArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleWatched()
                            }
                        }
                        Rectangle {
                            visible: (root.inf.trailer ?? "") !== ""
                            implicitWidth: trailerRow.implicitWidth + 26
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: trailerArea.containsMouse ? "#55ffffff" : "#33ffffff"
                            RowLayout {
                                id: trailerRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol { text: "smart_display"; iconSize: 21; color: "white" }
                                StyledText { text: "Trailer"; color: "white" }
                            }
                            MouseArea {
                                id: trailerArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: MediatorService.openTrailer(root.inf.trailer)
                            }
                        }
                        Rectangle {
                            visible: StremioService.available && root.title.lib !== "anime"
                            implicitWidth: stremioRow.implicitWidth + 26
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: stremioArea.containsMouse ? "#55ffffff" : "#33ffffff"
                            RowLayout {
                                id: stremioRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol { text: "play_circle"; iconSize: 21; fill: 1; color: "white" }
                                StyledText { text: "Stremio"; color: "white" }
                            }
                            MouseArea {
                                id: stremioArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.openInStremio()
                            }
                        }
                        Rectangle {
                            visible: root.title.lib === "anime"
                            implicitWidth: streamRow.implicitWidth + 26
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: streamArea.containsMouse ? "#55ffffff" : "#33ffffff"
                            RowLayout {
                                id: streamRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol { text: "live_tv"; iconSize: 21; color: "white" }
                                StyledText { text: "Stream"; color: "white" }
                            }
                            MouseArea {
                                id: streamArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.streamOpen = true
                            }
                        }
                        Rectangle {
                            implicitWidth: 44
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: posterBtnArea.containsMouse || root.editingPoster ? "#55ffffff" : "#33ffffff"
                            MaterialSymbol { anchors.centerIn: parent; text: "image"; iconSize: 21; color: "white" }
                            MouseArea {
                                id: posterBtnArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePosterEditor()
                            }
                            StyledToolTip { text: "Change poster (P)" }
                        }
                        Rectangle {
                            visible: !root.isMovie && root.entries.length > 0 && root.entries[0].media === undefined
                            implicitWidth: probeRow.implicitWidth + 26
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: probeArea.containsMouse ? "#55ffffff" : "#33ffffff"
                            RowLayout {
                                id: probeRow
                                anchors.centerIn: parent
                                spacing: 6
                                MaterialSymbol { text: "info"; iconSize: 20; color: "white" }
                                StyledText {
                                    text: MediatorService.probingId === root.title.id ? "Reading files…" : "Read file info"
                                    color: "white"
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                            }
                            MouseArea {
                                id: probeArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: if (MediatorService.probingId === "") MediatorService.probeTitle(root.title.id)
                            }
                        }
                    }
                }
            }
        }

        // Wrong or missing poster: point it at an image file or a URL
        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 640
            visible: root.editingPoster
                spacing: 8
                SettingsField {
                    id: posterField
                    label: "Image file or URL"
                    placeholder: "~/Pictures/poster.jpg or https://…"
                    onAccepted: applyPoster.clicked()
                    input.Keys.onEscapePressed: {
                        root.editingPoster = false;
                        root.refocusRequested();
                    }
                }
                RowLayout {
                    spacing: 12
                    Rectangle {
                        id: applyPoster
                        signal clicked()
                        implicitWidth: applyText.implicitWidth + 32
                        implicitHeight: 36
                        radius: Appearance.rounding.full
                        opacity: MediatorService.posterBusy ? 0.5 : 1
                        color: Appearance.colors.colPrimary
                        onClicked: {
                            MediatorService.setPoster(root.title.id, posterField.text);
                            posterField.text = "";
                        }
                        StyledText {
                            id: applyText
                            anchors.centerIn: parent
                            text: MediatorService.posterBusy ? "Fetching…" : "Use this"
                            color: Appearance.colors.colOnPrimary
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: applyPoster.clicked()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: MediatorService.posterMessage
                        color: MediatorService.posterMessage === "Poster updated" ? Appearance.colors.colPrimary : Appearance.m3colors.m3error
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
            }
        }

        // AniList actions stay close to the title, while token/account setup remains in Settings.
        ColumnLayout {
            Layout.fillWidth: true
            Layout.maximumWidth: 760
            visible: root.title.lib === "anime"
            spacing: 8
            StyledText {
                text: "ANILIST"
                color: Appearance.colors.colPrimary
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.letterSpacing: 1.3
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                SettingsField {
                    id: scoreValue
                    Layout.fillWidth: true
                    label: "Score"
                    placeholder: "0–100 (your AniList format)"
                    onAccepted: MediatorService.scoreAniListTitle(root.title.id, scoreValue.text, scoreSeason.text)
                }
                SettingsField {
                    id: scoreSeason
                    Layout.preferredWidth: 150
                    label: "Season"
                    placeholder: "Optional"
                }
                Rectangle {
                    implicitWidth: syncAniText.implicitWidth + 28
                    implicitHeight: 44
                    radius: Appearance.rounding.full
                    opacity: MediatorService.anilistBusy ? 0.45 : 1
                    color: syncAniArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
                    StyledText {
                        id: syncAniText
                        anchors.centerIn: parent
                        text: MediatorService.anilistBusy && MediatorService.anilistAction === "sync-title"
                            ? "Syncing…" : "Sync"
                        color: Appearance.colors.colOnLayer0
                    }
                    MouseArea {
                        id: syncAniArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !MediatorService.anilistBusy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.syncAniListTitle(root.title.id)
                    }
                }
                Rectangle {
                    implicitWidth: scoreText.implicitWidth + 28
                    implicitHeight: 44
                    radius: Appearance.rounding.full
                    opacity: MediatorService.anilistBusy ? 0.45 : 1
                    color: scoreArea.containsMouse ? Appearance.colors.colPrimaryHover : Appearance.colors.colPrimary
                    StyledText {
                        id: scoreText
                        anchors.centerIn: parent
                        text: MediatorService.anilistBusy && MediatorService.anilistAction === "score" ? "Saving…" : "Set score"
                        color: Appearance.colors.colOnPrimary
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        id: scoreArea
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: !MediatorService.anilistBusy
                        cursorShape: Qt.PointingHandCursor
                        onClicked: MediatorService.scoreAniListTitle(root.title.id, scoreValue.text, scoreSeason.text)
                    }
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: MediatorService.anilistError !== "" || MediatorService.anilistMessage !== ""
                text: MediatorService.anilistError !== "" ? MediatorService.anilistError : MediatorService.anilistMessage
                color: MediatorService.anilistError !== "" ? Appearance.m3colors.m3error : Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                wrapMode: Text.Wrap
            }
        }

        // Body: the episodes, and About beside them
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 22

            // Episodes (or, for a movie, where it will pick up)
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 12
                visible: !root.isMovie

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    StyledText {
                        text: "Episodes"
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                    }
                    StyledText {
                        text: `${root.title.watched} of ${root.title.total} watched`
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                    Rectangle {
                        visible: root.missingHere.length > 0
                        implicitWidth: dlAllRow.implicitWidth + 22
                        implicitHeight: 28
                        radius: Appearance.rounding.full
                        color: dlAllArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                        RowLayout {
                            id: dlAllRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol { text: "download"; iconSize: 16; color: Appearance.colors.colOnLayer1 }
                            StyledText {
                                text: `Download ${root.missingHere.length} not in library`
                                color: Appearance.colors.colOnLayer1
                                font.pixelSize: Appearance.font.pixelSize.smaller
                            }
                        }
                        MouseArea {
                            id: dlAllArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: missingCtl.item?.downloadAll()
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Flow {
                        spacing: 8
                        visible: root.groups.length > 1
                        Repeater {
                            model: root.groups
                            delegate: Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool on: chip.modelData.key === root.group
                                implicitWidth: chipText.implicitWidth + 26
                                implicitHeight: 32
                                radius: Appearance.rounding.full
                                color: chip.on ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                                StyledText {
                                    id: chipText
                                    anchors.centerIn: parent
                                    text: chip.modelData.label
                                    color: Appearance.colors.colOnLayer0
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.group = chip.modelData.key;
                                        root.cur = 0;
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.missingHere.length > 0 && (missingCtl.item?.note ?? "") !== ""
                    text: missingCtl.item?.note ?? ""
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                ListView {
                    WheelScroll {}
                    id: episodes
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 4
                    model: root.shown
                    boundsBehavior: Flickable.StopAtBounds

                    StyledText {
                        anchors.centerIn: parent
                        visible: root.detail === null
                        text: "Loading episodes…"
                        color: Appearance.colors.colSubtext
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool sel: row.index === root.cur
                        readonly property bool gone: row.modelData.missingEp === true
                        readonly property string stateLabel: row.gone ? (missingCtl.item?.stateText(row.modelData.missingRef) ?? "") : ""
                        readonly property bool done: row.modelData.progress?.watched ?? false
                        readonly property var ep: row.modelData.episode_info ?? null
                        readonly property string still: row.ep?.image ?? ""
                        readonly property real frac: {
                            const p = row.modelData.progress;
                            return p && p.duration > 0 && !p.watched ? Math.min(1, p.position / p.duration) : 0;
                        }
                        readonly property string num: {
                            const e = row.modelData;
                            const m = /E(\d+)$/.exec(e.code ?? "");
                            return m ? `${parseInt(m[1])}` : (e.code ?? "");
                        }
                        readonly property string name: {
                            const e = row.modelData;
                            if (row.ep?.title)
                                return row.ep.title;
                            if (e.name)
                                return e.name;
                            if (e.kind === "episode" && e.episode)
                                return `Episode ${e.episode}`;
                            return e.label || e.code || "";
                        }
                        readonly property string meta: {
                            const bits = [];
                            if (row.ep?.airdate)
                                bits.push(row.ep.airdate);
                            if (row.ep?.runtime)
                                bits.push(`${row.ep.runtime} min`);
                            if (row.ep?.filler)
                                bits.push("Filler");
                            if (row.modelData.media?.summary)
                                bits.push(row.modelData.media.summary);
                            return bits.join("  ·  ");
                        }
                        width: ListView.view.width
                        height: row.still !== "" || (row.ep?.summary ?? "") !== "" ? 92 : 56
                        radius: Appearance.rounding.normal
                        color: row.sel ? Appearance.colors.colSecondaryContainer
                             : rowArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"

                        RowLayout {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 16; topMargin: 8; bottomMargin: 8 }
                            spacing: 14
                            opacity: row.gone ? 0.82 : 1
                            z: 1  // above the row's own click area, or the buttons never get a click
                            RoundedBox {
                                Layout.preferredWidth: row.still !== "" ? 114 : 40
                                Layout.preferredHeight: row.still !== "" ? 64 : 40
                                Layout.alignment: Qt.AlignVCenter
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                Image {
                                    anchors.fill: parent
                                    visible: row.still !== ""
                                    source: row.still
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: true
                                    sourceSize.width: 260
                                    opacity: row.done ? 0.5 : 1
                                }
                                StyledText {
                                    anchors.centerIn: parent
                                    visible: row.still === ""
                                    text: row.num
                                    color: Appearance.colors.colSubtext
                                    font.weight: Font.Medium
                                }
                                Rectangle {
                                    visible: row.still !== ""
                                    anchors { left: parent.left; bottom: parent.bottom }
                                    width: numText.implicitWidth + 14
                                    height: 20
                                    topRightRadius: 8
                                    color: "#99000000"
                                    StyledText {
                                        id: numText
                                        anchors.centerIn: parent
                                        text: row.num
                                        color: "white"
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        font.weight: Font.DemiBold
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.name
                                        elide: Text.ElideRight
                                        color: row.done ? Appearance.colors.colSubtext : Appearance.colors.colOnLayer0
                                        font.weight: Font.Medium
                                    }
                                    Rectangle {
                                        visible: row.gone
                                        implicitWidth: goneRow.implicitWidth + 14
                                        implicitHeight: 20
                                        radius: Appearance.rounding.full
                                        color: Appearance.colors.colSecondaryContainer
                                        RowLayout {
                                            id: goneRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            MaterialSymbol { text: "cloud"; iconSize: 13; color: Appearance.colors.colOnSecondaryContainer }
                                            StyledText {
                                                text: row.stateLabel !== "" ? row.stateLabel : "Not in library"
                                                color: Appearance.colors.colOnSecondaryContainer
                                                font.pixelSize: Appearance.font.pixelSize.smallest
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: (row.ep?.summary ?? "") !== ""
                                    text: row.ep?.summary ?? ""
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: row.meta !== ""
                                    text: row.meta
                                    elide: Text.ElideRight
                                    color: Appearance.colors.colOutline
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                            Repeater {
                                model: row.gone ? [
                                    { icon: "play_arrow", tip: "Stream this episode", act: "stream" },
                                    { icon: "download", tip: "Download this episode", act: "download" }
                                ] : []
                                delegate: Rectangle {
                                    id: act
                                    required property var modelData
                                    Layout.preferredWidth: 36
                                    Layout.preferredHeight: 36
                                    radius: Appearance.rounding.full
                                    color: actArea.containsMouse ? Appearance.colors.colLayer2Hover : Appearance.colors.colLayer1
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        text: act.modelData.icon
                                        iconSize: 20
                                        color: Appearance.colors.colOnLayer1
                                    }
                                    MouseArea {
                                        id: actArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            if (act.modelData.act === "stream")
                                                missingCtl.item?.stream(row.modelData.missingRef);
                                            else
                                                missingCtl.item?.download(row.modelData.missingRef);
                                        }
                                    }
                                    StyledToolTip { text: act.modelData.tip }
                                }
                            }
                            Rectangle {
                                visible: row.frac > 0
                                Layout.preferredWidth: 72
                                Layout.preferredHeight: 4
                                radius: 2
                                color: Appearance.colors.colOutlineVariant
                                Rectangle {
                                    width: parent.width * row.frac
                                    height: parent.height
                                    radius: 2
                                    color: Appearance.colors.colPrimary
                                }
                            }
                            MaterialSymbol {
                                visible: !row.gone
                                text: row.done ? "check_circle" : "radio_button_unchecked"
                                fill: row.done ? 1 : 0
                                iconSize: 20
                                color: row.done ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant
                            }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.cur = row.index;
                                root.playCurrent();
                            }
                        }
                    }
                }
            }

            // About: synopsis, cast, tags, related
            Flickable {
                WheelScroll {}
                Layout.fillHeight: true
                Layout.fillWidth: root.isMovie
                Layout.preferredWidth: root.isMovie ? -1 : (root.wide ? 340 : 0)
                visible: root.isMovie || root.wide
                contentHeight: about.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: about
                    width: parent.width
                    spacing: 14

                    StyledText {
                        text: "About"
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                    }

                    // A movie in progress: where it will pick up
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 520
                        visible: root.isMovie && root.movieFrac > 0
                        spacing: 6
                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 5
                            radius: 3
                            color: Appearance.colors.colOutlineVariant
                            Rectangle {
                                width: parent.width * root.movieFrac
                                height: parent.height
                                radius: 3
                                color: Appearance.colors.colPrimary
                            }
                        }
                        StyledText {
                            text: root.movieProgressText
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.maximumWidth: 900
                        visible: (root.m.synopsis ?? "") !== ""
                        text: root.m.synopsis ?? ""
                        wrapMode: Text.Wrap
                        lineHeight: 1.25
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: 8
                        visible: (root.inf.tags ?? []).length > 0
                        Repeater {
                            model: (root.inf.tags ?? []).slice(0, 8)
                            delegate: Rectangle {
                                id: tag
                                required property string modelData
                                implicitWidth: tagText.implicitWidth + 18
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: Appearance.colors.colLayer1
                                StyledText {
                                    id: tagText
                                    anchors.centerIn: parent
                                    text: tag.modelData
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.credits !== "" && !root.castPeople.some(c => c.image)
                        text: root.credits
                        wrapMode: Text.Wrap
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                    }

                    StyledText {
                        visible: root.castPeople.some(c => c.image)
                        text: "Cast"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.letterSpacing: 1
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 12
                        visible: root.castPeople.some(c => c.image)
                        Repeater {
                            model: root.castPeople.filter(c => c.image).slice(0, 10)
                            delegate: RowLayout {
                                id: person
                                required property var modelData
                                width: root.isMovie ? 230 : about.width
                                spacing: 10
                                RoundedBox {
                                    Layout.preferredWidth: 44
                                    Layout.preferredHeight: 44
                                    radius: Appearance.rounding.full
                                    color: Appearance.colors.colLayer2
                                    Image {
                                        anchors.fill: parent
                                        source: person.modelData.image
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 100
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: person.modelData.name
                                        elide: Text.ElideRight
                                        color: Appearance.colors.colOnLayer0
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        font.weight: Font.Medium
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: (person.modelData.role ?? "") !== ""
                                        text: person.modelData.role ?? ""
                                        elide: Text.ElideRight
                                        color: Appearance.colors.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        visible: (root.inf.related ?? []).length > 0
                        text: "Related"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.letterSpacing: 1
                    }
                    Repeater {
                        model: (root.inf.related ?? []).slice(0, 6)
                        delegate: StyledText {
                            required property var modelData
                            Layout.fillWidth: true
                            text: `${modelData.relation}  ·  ${modelData.title ?? ""}${modelData.year ? ` (${modelData.year})` : ""}`
                            elide: Text.ElideRight
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: root.isMovie && root.movieFile !== ""
                        text: root.movieFile
                        elide: Text.ElideMiddle
                        color: Appearance.colors.colOutlineVariant
                        font.pixelSize: Appearance.font.pixelSize.smallest
                    }
                }
            }
        }

        // What a missing episode can do. By file, not by type name: a new file is not in the
        // module's type list until the shell restarts, and a missing type would stop this page loading
        Loader {
            id: missingCtl
            active: !root.isMovie && root.title.lib !== undefined
            source: "MissingEpisodes.qml"
            onLoaded: {
                item.title = Qt.binding(() => root.title);
                item.isAnime = root.title.lib === "anime";
                item.seasons = Qt.binding(() => root.inf.seasons ?? []);
                item.imdbId = Qt.binding(() => root.stremioId());
                item.season = Qt.binding(() => root.groupSeason);
                item.shown = Qt.binding(() => root.missingHere);
                item.streamStarted.connect(() => {
                    if (root.closeAfterStream)
                        root.streamStarted();
                });
            }
        }

        Loader {
            anchors.fill: parent
            active: missingCtl.item?.pickerOpen === true
            z: 20
            source: "StremioStreamPicker.qml"
            onLoaded: item.closeRequested.connect(() => {
                missingCtl.item.pickerOpen = false;
                if (StremioService.view === "streams")
                    StremioService.back();
            })
        }

        Loader {
            anchors.fill: parent
            active: root.streamOpen
            z: 20
            sourceComponent: AnimeStreamDialog {
                searchMode: false
                titleId: root.title.id ?? ""
                titleLabel: root.title.display ?? root.title.name ?? ""
                defaultSeason: root.group.startsWith("S") ? root.group.slice(1) : ""
                defaultEpisode: root.shown[root.cur]?.episode ? String(root.shown[root.cur].episode) : ""
                onCloseRequested: root.streamOpen = false
                onStreamStarted: {
                    root.streamOpen = false;
                    if (root.closeAfterStream)
                        root.streamStarted();
                }
            }
        }
    }
}

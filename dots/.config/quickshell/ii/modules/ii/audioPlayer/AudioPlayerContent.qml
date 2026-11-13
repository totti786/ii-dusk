pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A local music player. Playback, the queue and MPRIS all belong to LocalMediaService (the same
 * engine Media Mode uses), so music keeps playing when this window closes. This view adds the
 * library: ~/Music is indexed once with the shell's scanner, cached, and browsed by song,
 * album and artist, with the current track's artwork and (synced) lyrics on the Now Playing page.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property string home: String(Quickshell.env("HOME") || "")
    readonly property string musicDir: String(Quickshell.env("XDG_MUSIC_DIR") || (root.home + "/Music"))
    readonly property string cachePath: Directories.cache + "/media/audio-player-library.json"
    readonly property var player: LocalMediaService.player

    // ── library ──
    readonly property var libraryDirs: {
        const saved = Array.from(Persistent.states.background.mediaMode.audioLibraryDirs ?? []);
        return saved.length > 0 ? saved : [root.musicDir];
    }
    property var scanQueue: []
    property var tracks: []
    property bool scanning: false
    property int scanCount: 0
    property string query: ""
    /// Songs page scope: "" (all), "album" or "artist"
    property string scopeKind: ""
    property string scopeName: ""
    property string page: "songs"

    readonly property var albums: {
        const map = new Map();
        for (const t of root.tracks) {
            const name = t.album || "";
            if (!name)
                continue;
            const key = name + "\u0000" + (t.artist || "");
            let a = map.get(key);
            if (!a) {
                a = { name: name, artist: t.artist || "", artUrl: "", count: 0 };
                map.set(key, a);
            }
            a.count++;
            if (!a.artUrl && t.artUrl)
                a.artUrl = t.artUrl;
        }
        return Array.from(map.values()).sort((x, y) => x.name.localeCompare(y.name));
    }
    readonly property var artists: {
        const map = new Map();
        for (const t of root.tracks) {
            const name = t.artist || "";
            if (!name)
                continue;
            let a = map.get(name);
            if (!a) {
                a = { name: name, artUrl: "", count: 0 };
                map.set(name, a);
            }
            a.count++;
            if (!a.artUrl && t.artUrl)
                a.artUrl = t.artUrl;
        }
        return Array.from(map.values()).sort((x, y) => x.name.localeCompare(y.name));
    }
    readonly property var shown: {
        const q = root.query.trim().toLowerCase();
        return root.tracks.filter(t => {
            if (root.scopeKind === "album" && (t.album || "") !== root.scopeName)
                return false;
            if (root.scopeKind === "artist" && (t.artist || "") !== root.scopeName)
                return false;
            if (q.length === 0)
                return true;
            return (t.title || "").toLowerCase().includes(q)
                || (t.artist || "").toLowerCase().includes(q)
                || (t.album || "").toLowerCase().includes(q);
        });
    }

    // ── playback ──
    readonly property bool hasTrack: LocalMediaService.hasSession && root.player.trackTitle.length > 0
    readonly property var queueEntries: LocalMediaService.queueSnapshot?.entries ?? []
    readonly property string currentEntryId: String(LocalMediaService.queueSnapshot?.currentEntryId ?? "")
    readonly property string currentPath: {
        for (const e of root.queueEntries)
            if (String(e.entryId ?? "") === root.currentEntryId)
                return String(e.path ?? "");
        return "";
    }
    property real basePos: 0
    property real baseTime: Date.now()
    property real pos: 0
    property bool seeking: false
    property real seekValue: 0
    readonly property real duration: Math.max(0, root.player.length)
    readonly property real shownPos: root.seeking ? root.seekValue : Math.min(root.pos, root.duration > 0 ? root.duration : root.pos)

    // Lyrics come from LyricsService, the same providers Media Mode uses (the song's own
    // .lrc or tags first, then LRCLIB, Better Lyrics, Genius, YouTube Music, ...)
    readonly property bool lyricsSynced: LyricsService.hasSyncedLines
    readonly property var lyricLines: {
        if (LyricsService.hasSyncedLines)
            return LyricsService.syncedLines;
        return String(LyricsService.plainLyrics ?? "").split("\n")
            .map(l => l.trim()).filter(l => l.length > 0).map(l => ({ time: -1, text: l }));
    }
    readonly property int lyricIndex: root.lyricsSynced ? LyricsService.currentIndex : -1

    focus: true

    function fmt(sec: real): string {
        const s = Math.max(0, Math.floor(sec));
        const m = Math.floor(s / 60);
        const r = s % 60;
        if (m >= 60)
            return `${Math.floor(m / 60)}:${String(m % 60).padStart(2, "0")}:${String(r).padStart(2, "0")}`;
        return `${m}:${String(r).padStart(2, "0")}`;
    }

    function entryFor(t: var): var {
        return {
            path: t.path, trackId: t.trackId, title: t.title, artist: t.artist, album: t.album,
            durationSec: t.durationSec, artUrl: t.artUrl, lyricsPath: t.lyricsPath,
            mtime: t.mtime, ctime: t.ctime
        };
    }

    /// Plays `list` starting at `index`: the list is rotated so the chosen song is first and
    /// the rest follow in order
    function playList(list: var, index: int): void {
        if (!list || list.length === 0)
            return;
        const start = Math.max(0, Math.min(list.length - 1, index));
        const ordered = list.slice(start).concat(list.slice(0, start));
        LocalMediaService.openEntries(ordered.map(t => root.entryFor(t)), ordered.length === 1 ? "single" : "playlist");
    }

    function shuffleList(list: var): void {
        if (!list || list.length === 0)
            return;
        const pick = Math.floor(Math.random() * list.length);
        root.playList(list, pick);
        shuffleOnOpen.restart();
    }

    function go(page: string): void {
        root.page = page;
        if (page !== "songs") {
            root.scopeKind = "";
            root.scopeName = "";
        }
    }

    function scope(kind: string, name: string): void {
        root.scopeKind = kind;
        root.scopeName = name;
        root.query = "";
        root.page = "songs";
    }

    function rescan(): void {
        if (libScan.running || root.scanning)
            return;
        libScan.found = [];
        root.scanCount = 0;
        root.scanning = true;
        root.scanQueue = root.libraryDirs.slice();
        root.scanNext();
    }

    function scanNext(): void {
        if (root.scanQueue.length === 0) {
            root.finishScan();
            return;
        }
        const dir = root.scanQueue[0];
        root.scanQueue = root.scanQueue.slice(1);
        libScan.command = [Directories.scriptPath + "/media/library-index-venv.sh", "--folder", dir, "--request-id", "audio-player-library"];
        libScan.running = true;
    }

    function finishScan(): void {
        const seen = new Set();
        const unique = libScan.found.filter(t => !seen.has(t.path) && seen.add(t.path));
        const sorted = unique.sort((a, b) =>
            (a.artist || "").localeCompare(b.artist || "")
            || (a.album || "").localeCompare(b.album || "")
            || (a.title || "").localeCompare(b.title || ""));
        root.tracks = sorted;
        root.scanning = false;
        cacheFile.setText(JSON.stringify(sorted));
    }

    function setDirs(dirs: var): void {
        const clean = Array.from(new Set(dirs.map(d => String(d).trim().replace(/\/+$/, "")).filter(d => d.length > 0)));
        Persistent.states.background.mediaMode.audioLibraryDirs = clean;
        root.rescan();
    }

    function addDir(dir: string): void {
        const d = String(dir).trim().replace(/^~(?=\/|$)/, root.home);
        if (d.length === 0)
            return;
        const saved = Array.from(Persistent.states.background.mediaMode.audioLibraryDirs ?? []);
        root.setDirs((saved.length > 0 ? saved : root.libraryDirs).concat([d]));
    }

    function removeDir(dir: string): void {
        root.setDirs(root.libraryDirs.filter(d => d !== dir));
    }

    function songsIn(dir: string): int {
        let n = 0;
        for (const t of root.tracks)
            if (t.path.startsWith(dir + "/"))
                n++;
        return n;
    }

    function openRequested(): void {
        const path = GlobalStates.audioPlayerPath;
        if (path.length === 0)
            return;
        root.page = "now";
        if (path.endsWith("/") || !/\.[A-Za-z0-9]{2,5}$/.test(path)) {
            openScan.found = [];
            openScan.command = [Directories.scriptPath + "/media/library-index-venv.sh", "--folder", path, "--request-id", "audio-player-open"];
            openScan.running = true;
        } else {
            // Scanned here so the artwork and tags come from the same index as the library
            openScan.found = [];
            openScan.command = [Directories.scriptPath + "/media/library-index-venv.sh", "--path", path, "--request-id", "audio-player-open"];
            openScan.running = true;
        }
    }

    // Keep the position moving between the helper's updates
    function syncPosition(): void {
        root.basePos = root.player.position;
        root.baseTime = Date.now();
        root.pos = root.basePos;
    }

    Connections {
        target: LocalMediaService
        function onStateChanged(): void {
            root.syncPosition();
        }
    }

    Connections {
        target: GlobalStates
        function onAudioPlayerRequestChanged(): void {
            root.openRequested();
        }
        function onAudioPlayerRescanChanged(): void {
            root.rescan();
        }
    }

    Timer {
        interval: 250
        repeat: true
        running: root.player.isPlaying && !root.seeking
        onTriggered: root.pos = root.basePos + (Date.now() - root.baseTime) / 1000 * (root.player.rate || 1)
    }

    Timer {
        id: shuffleOnOpen
        interval: 400
        onTriggered: LocalMediaService.setShuffle(true)
    }

    Component.onCompleted: {
        root.syncPosition();
        cacheFile.reload();
        LyricsService.initiliazeLyrics();
        root.openRequested();
        root.forceActiveFocus();
    }

    // ── scanning and cache ──
    component ScanJob: Process {
        id: job
        property var found: []
        property int counted: 0
        stdout: SplitParser {
            onRead: line => {
                if (line.indexOf('"event":"track"') < 0)
                    return;
                try {
                    const msg = JSON.parse(line);
                    job.found.push(msg.payload.track);
                    job.counted = job.found.length;
                } catch (e) {}
            }
        }
    }

    ScanJob {
        id: libScan
        onCountedChanged: root.scanCount = libScan.counted
        onExited: root.scanNext()
    }

    Process {
        id: dirPicker
        command: ["bash", "-c", "if command -v kdialog >/dev/null 2>&1; then kdialog --getexistingdirectory \"$HOME/Music\" 2>/dev/null; "
            + "elif command -v zenity >/dev/null 2>&1; then zenity --file-selection --directory --filename=\"$HOME/Music/\" 2>/dev/null; fi"]
        stdout: SplitParser {
            onRead: line => root.addDir(line)
        }
    }

    ScanJob {
        id: openScan
        onExited: {
            if (openScan.found.length > 0)
                root.playList(openScan.found, 0);
        }
    }

    FileView {
        id: cacheFile
        path: root.cachePath
        onLoaded: {
            try {
                const data = JSON.parse(cacheFile.text());
                if (Array.isArray(data) && data.length > 0) {
                    root.tracks = data;
                    return;
                }
            } catch (e) {}
            root.rescan();
        }
        onLoadFailed: root.rescan()
    }

    // ── keys ──
    readonly property bool typing: searchInput.activeFocus
    Shortcut { sequence: "Space"; enabled: !root.typing; onActivated: LocalMediaService.playPause() }
    Shortcut { sequence: "Left"; enabled: !root.typing; onActivated: root.seekBy(-5) }
    Shortcut { sequence: "Right"; enabled: !root.typing; onActivated: root.seekBy(5) }
    Shortcut { sequence: "Ctrl+Left"; onActivated: LocalMediaService.previous() }
    Shortcut { sequence: "Ctrl+Right"; onActivated: LocalMediaService.next() }
    Shortcut { sequence: "Up"; enabled: !root.typing; onActivated: root.player.volume = Math.min(1, root.player.volume + 0.05) }
    Shortcut { sequence: "Down"; enabled: !root.typing; onActivated: root.player.volume = Math.max(0, root.player.volume - 0.05) }
    Shortcut { sequence: "Ctrl+F"; onActivated: { root.go("songs"); searchInput.forceActiveFocus(); } }
    Shortcut { sequence: "Ctrl+R"; onActivated: root.rescan() }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (searchInput.activeFocus) {
                root.query = "";
                root.forceActiveFocus();
            } else if (root.scopeKind !== "") {
                root.scopeKind = "";
                root.scopeName = "";
            } else {
                root.closeRequested();
            }
        }
    }

    function seekBy(delta: real): void {
        if (!root.hasTrack || !root.player.canSeek)
            return;
        const target = Math.max(0, Math.min(root.duration, root.pos + delta));
        root.pos = target;
        root.basePos = target;
        root.baseTime = Date.now();
        root.player.seek(target);
    }

    // ── small building blocks ──
    component Round: Rectangle {
        id: btn
        property string symbol: ""
        property real size: 40
        property real iconSize: 22
        property bool filled: false
        property bool accent: false
        property bool active: false
        property bool enabled2: true
        signal clicked()
        implicitWidth: size
        implicitHeight: size
        radius: size / 2
        color: accent ? ClockStyle.colPrimary
            : (active ? ClockStyle.colSecondaryContainer : (area.containsMouse ? ClockStyle.colSurfaceHover : "transparent"))
        opacity: btn.enabled2 ? 1 : 0.38
        scale: area.pressed ? 0.92 : 1
        Behavior on scale { NumberAnimation { duration: Appearance.dur(90) } }
        Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
        MaterialSymbol {
            anchors.centerIn: parent
            text: btn.symbol
            iconSize: btn.iconSize
            fill: btn.filled || btn.accent ? 1 : 0
            color: btn.accent ? ClockStyle.colOnPrimary
                : (btn.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface)
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            enabled: btn.enabled2
            cursorShape: Qt.PointingHandCursor
            onClicked: btn.clicked()
        }
    }

    component Art: Item {
        id: art
        property string source: ""
        property real corner: 10
        property real glyph: 28
        ClippingRectangle {
            anchors.fill: parent
            radius: art.corner
            color: ClockStyle.colSurfaceHighest
            Image {
                id: img
                anchors.fill: parent
                source: art.source
                sourceSize.width: Math.max(96, art.width * 2)
                sourceSize.height: Math.max(96, art.height * 2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(180) } }
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: img.status !== Image.Ready
                text: "music_note"
                iconSize: art.glyph
                color: ClockStyle.colSubtext
                fill: 1
            }
        }
    }

    // ── layout ──
    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Sidebar
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 212
                color: ClockStyle.colSurface

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 4

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.bottomMargin: 14
                        spacing: 10
                        Rectangle {
                            implicitWidth: 36
                            implicitHeight: 36
                            radius: Appearance.rounding.small
                            color: ClockStyle.colPrimaryContainer
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "headphones"
                                iconSize: 20
                                fill: 1
                                color: ClockStyle.colOnPrimaryContainer
                            }
                        }
                        StyledText {
                            text: Translation.tr("Music")
                            font.pixelSize: 20
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                        }
                    }

                    Repeater {
                        model: [
                            { id: "now", icon: "graphic_eq", label: Translation.tr("Now playing") },
                            { id: "songs", icon: "music_note", label: Translation.tr("Songs") },
                            { id: "albums", icon: "album", label: Translation.tr("Albums") },
                            { id: "artists", icon: "person", label: Translation.tr("Artists") },
                            { id: "queue", icon: "queue_music", label: Translation.tr("Queue") }
                        ]
                        delegate: Rectangle {
                            id: nav
                            required property var modelData
                            readonly property bool current: root.page === nav.modelData.id
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: nav.current ? ClockStyle.colSecondaryContainer
                                : (navArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                            Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 12
                                spacing: 12
                                MaterialSymbol {
                                    text: nav.modelData.icon
                                    iconSize: 22
                                    fill: nav.current ? 1 : 0
                                    color: nav.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: nav.modelData.label
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: nav.current ? Font.DemiBold : Font.Normal
                                    color: nav.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                }
                            }
                            MouseArea {
                                id: navArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.go(nav.modelData.id)
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        text: root.scanning
                            ? Translation.tr("Indexing… %1 songs").arg(root.scanCount)
                            : Translation.tr("%1 songs · %2 albums").arg(root.tracks.length).arg(root.albums.length)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ClockStyle.colSubtext
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: root.page === "folders" ? ClockStyle.colSecondaryContainer
                            : (foldersArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                text: "folder_managed"
                                iconSize: 18
                                color: ClockStyle.colOnSurfaceVariant
                            }
                            StyledText {
                                text: Translation.tr("Library folders")
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: ClockStyle.colOnSurfaceVariant
                            }
                        }
                        MouseArea {
                            id: foldersArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.go("folders")
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 40
                        radius: Appearance.rounding.full
                        color: rescanArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            MaterialSymbol {
                                id: spinIcon
                                text: "refresh"
                                iconSize: 18
                                color: ClockStyle.colOnSurfaceVariant
                                RotationAnimator on rotation {
                                    running: (root.scanning) && !Appearance.motionOff
                                    from: 0
                                    to: 360
                                    duration: 900
                                    loops: Animation.Infinite
                                }
                            }
                            StyledText {
                                text: Translation.tr("Rescan library")
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: ClockStyle.colOnSurfaceVariant
                            }
                        }
                        MouseArea {
                            id: rescanArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.rescan()
                        }
                    }
                }
            }

            // Pages
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // ── Now playing ──
                Item {
                    id: nowPage
                    anchors.fill: parent
                    visible: root.page === "now"
                    clip: true

                    Image {
                        id: backdrop
                        anchors.fill: parent
                        source: root.player.trackArtUrl
                        sourceSize.width: 96
                        sourceSize.height: 96
                        fillMode: Image.PreserveAspectCrop
                        visible: false
                        asynchronous: true
                    }
                    FastBlur {
                        anchors.fill: parent
                        source: backdrop
                        radius: 64
                        opacity: backdrop.status === Image.Ready ? 0.55 : 0
                        Behavior on opacity { NumberAnimation { duration: Appearance.dur(400) } }
                    }
                    Rectangle {
                        anchors.fill: parent
                        color: ClockStyle.colBackground
                        opacity: 0.45
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 36
                        spacing: 40
                        visible: root.hasTrack

                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            readonly property real cover: Math.max(140, Math.min(380, nowPage.height - 72 - 120 - 22, nowPage.width * 0.42))
                            Layout.preferredWidth: cover
                            Layout.maximumWidth: cover
                            spacing: 22

                            Item {
                                Layout.preferredWidth: parent.cover
                                Layout.preferredHeight: parent.cover
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.topMargin: 14
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    radius: 28
                                    color: "black"
                                    opacity: 0.35
                                    layer.enabled: true
                                    layer.effect: FastBlur { radius: 36 }
                                }
                                Art {
                                    anchors.fill: parent
                                    source: root.player.trackArtUrl
                                    corner: 26
                                    glyph: 96
                                    scale: root.player.isPlaying ? 1 : 0.94
                                    Behavior on scale { NumberAnimation { duration: Appearance.dur(320); easing.type: Easing.OutCubic } }
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 4
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.player.trackTitle
                                    font.pixelSize: 24
                                    font.weight: Font.Bold
                                    color: ClockStyle.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.player.trackArtist
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    color: ClockStyle.colPrimary
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: root.player.trackAlbum
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: ClockStyle.colSubtext
                                    elide: Text.ElideRight
                                    visible: text.length > 0
                                }
                            }
                        }

                        // Lyrics
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            visible: nowPage.width > 760

                            ListView {
                                id: lyricsView
                                anchors.fill: parent
                                visible: root.lyricLines.length > 0
                                model: root.lyricLines
                                clip: true
                                spacing: 10
                                topMargin: height / 2 - 30
                                bottomMargin: height / 2
                                boundsBehavior: Flickable.StopAtBounds
                                highlightFollowsCurrentItem: false
                                cacheBuffer: 800
                                delegate: StyledText {
                                    id: ly
                                    required property var modelData
                                    required property int index
                                    readonly property bool now: root.lyricsSynced && index === root.lyricIndex
                                    width: ListView.view.width
                                    text: ly.modelData.text.length > 0 ? ly.modelData.text : "♪"
                                    wrapMode: Text.WordWrap
                                    font.pixelSize: ly.now ? 28 : 22
                                    font.weight: ly.now || !root.lyricsSynced ? Font.Bold : Font.DemiBold
                                    color: root.lyricsSynced
                                        ? (ly.now ? ClockStyle.colOnSurface : ClockStyle.colSubtext)
                                        : ClockStyle.colOnSurface
                                    opacity: root.lyricsSynced ? (ly.now ? 1 : 0.45) : 0.9
                                    horizontalAlignment: Text.AlignLeft
                                    Behavior on opacity { NumberAnimation { duration: Appearance.dur(220) } }
                                    Behavior on font.pixelSize { NumberAnimation { duration: Appearance.dur(180) } }
                                    MouseArea {
                                        anchors.fill: parent
                                        enabled: root.lyricsSynced && ly.modelData.time >= 0
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.seekBy(ly.modelData.time - root.pos)
                                    }
                                }
                                Connections {
                                    target: root
                                    function onLyricIndexChanged(): void {
                                        if (root.lyricIndex >= 0 && !lyricsView.moving)
                                            lyricsView.positionViewAtIndex(root.lyricIndex, ListView.Center);
                                    }
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                visible: root.lyricLines.length === 0
                                spacing: 8
                                MaterialSymbol {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: LyricsService.searching ? "hourglass_top" : "lyrics"
                                    iconSize: 44
                                    color: ClockStyle.colSubtext
                                    opacity: 0.5
                                }
                                StyledText {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: LyricsService.searching ? Translation.tr("Looking for lyrics…") : Translation.tr("No lyrics for this song")
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: !root.hasTrack
                        spacing: 12
                        MaterialSymbol {
                            Layout.alignment: Qt.AlignHCenter
                            text: "music_note"
                            iconSize: 64
                            color: ClockStyle.colSubtext
                            opacity: 0.5
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            text: Translation.tr("Nothing playing")
                            font.pixelSize: 18
                            color: ClockStyle.colOnSurface
                        }
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: playAllLabel.implicitWidth + 40
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: ClockStyle.colPrimary
                            visible: root.tracks.length > 0
                            StyledText {
                                id: playAllLabel
                                anchors.centerIn: parent
                                text: Translation.tr("Shuffle my music")
                                color: ClockStyle.colOnPrimary
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: { root.shuffleList(root.tracks); root.page = "now"; }
                            }
                        }
                    }
                }

                // ── Songs ──
                ColumnLayout {
                    anchors.fill: parent
                    visible: root.page === "songs"
                    spacing: 0

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 20
                        Layout.bottomMargin: 10
                        spacing: 12

                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: ClockStyle.colField
                            border.width: searchInput.activeFocus ? 2 : 0
                            border.color: ClockStyle.colPrimary
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 14
                                anchors.rightMargin: 8
                                spacing: 8
                                MaterialSymbol { text: "search"; iconSize: 20; color: ClockStyle.colSubtext }
                                TextInput {
                                    id: searchInput
                                    Layout.fillWidth: true
                                    Layout.alignment: Qt.AlignVCenter
                                    text: root.query
                                    onTextChanged: root.query = text
                                    color: ClockStyle.colOnSurface
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.family: Appearance.font.family.main
                                    selectByMouse: true
                                    clip: true
                                    Keys.onReturnPressed: root.playList(root.shown, 0)
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: searchInput.text.length === 0
                                        text: Translation.tr("Search songs, artists, albums")
                                        color: ClockStyle.colSubtext
                                        font.pixelSize: Appearance.font.pixelSize.small
                                    }
                                }
                                Round {
                                    size: 30
                                    iconSize: 18
                                    symbol: "close"
                                    visible: root.query.length > 0
                                    onClicked: { searchInput.text = ""; root.forceActiveFocus(); }
                                }
                            }
                        }

                        Round {
                            size: 44
                            symbol: "play_arrow"
                            accent: true
                            enabled2: root.shown.length > 0
                            onClicked: { root.playList(root.shown, 0); }
                        }
                        Round {
                            size: 44
                            symbol: "shuffle"
                            active: true
                            enabled2: root.shown.length > 0
                            onClicked: root.shuffleList(root.shown)
                        }
                    }

                    // Scope chip (an album or artist being browsed)
                    Rectangle {
                        Layout.leftMargin: 20
                        Layout.bottomMargin: 8
                        visible: root.scopeKind !== ""
                        implicitWidth: scopeRow.implicitWidth + 20
                        implicitHeight: 32
                        radius: Appearance.rounding.full
                        color: ClockStyle.colSecondaryContainer
                        RowLayout {
                            id: scopeRow
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                text: root.scopeKind === "album" ? "album" : "person"
                                iconSize: 16
                                color: ClockStyle.colOnSecondaryContainer
                            }
                            StyledText {
                                text: root.scopeName
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: ClockStyle.colOnSecondaryContainer
                            }
                            MaterialSymbol {
                                text: "close"
                                iconSize: 16
                                color: ClockStyle.colOnSecondaryContainer
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: { root.scopeKind = ""; root.scopeName = ""; }
                        }
                    }

                    ListView {
                        id: songsView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: root.shown
                        boundsBehavior: Flickable.StopAtBounds
                        reuseItems: true
                        cacheBuffer: 600
                        leftMargin: 12
                        rightMargin: 12
                        bottomMargin: 8
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        delegate: Rectangle {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool playing: root.currentPath === row.modelData.path
                            width: ListView.view.width - ListView.view.leftMargin - ListView.view.rightMargin
                            height: 58
                            radius: Appearance.rounding.small
                            color: row.playing ? ClockStyle.colSecondaryContainer
                                : (rowArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                            Behavior on color { ColorAnimation { duration: Appearance.dur(100) } }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 16
                                spacing: 14
                                Art {
                                    Layout.preferredWidth: 42
                                    Layout.preferredHeight: 42
                                    source: row.modelData.artUrl || ""
                                    corner: 8
                                    glyph: 20
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: row.playing
                                        text: root.player.isPlaying ? "equalizer" : "pause"
                                        iconSize: 22
                                        fill: 1
                                        color: "white"
                                        z: 2
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Appearance.rounding.verysmall
                                        color: "black"
                                        opacity: row.playing ? 0.45 : 0
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 1
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.title
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: row.playing ? Font.DemiBold : Font.Normal
                                        color: row.playing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: row.modelData.artist || Translation.tr("Unknown artist")
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: ClockStyle.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                                StyledText {
                                    Layout.preferredWidth: Math.min(220, songsView.width * 0.25)
                                    visible: songsView.width > 640
                                    text: row.modelData.album || ""
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: ClockStyle.colSubtext
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    text: root.fmt(row.modelData.durationSec)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: ClockStyle.colSubtext
                                }
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.playList(root.shown, row.index)
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            visible: root.shown.length === 0
                            spacing: 8
                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.scanning ? "hourglass_top" : "search_off"
                                iconSize: 48
                                color: ClockStyle.colSubtext
                                opacity: 0.5
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: root.scanning ? Translation.tr("Indexing your music…")
                                    : (root.tracks.length === 0 ? Translation.tr("No music found in %1").arg(root.musicDir)
                                        : Translation.tr("No matches"))
                                color: ClockStyle.colSubtext
                                font.pixelSize: Appearance.font.pixelSize.small
                            }
                        }
                    }
                }

                // ── Albums ──
                GridView {
                    id: albumsView
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: root.page === "albums"
                    clip: true
                    model: root.albums
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property int columns: Math.max(2, Math.floor(width / 190))
                    cellWidth: Math.floor(width / columns)
                    cellHeight: cellWidth + 56
                    cacheBuffer: 800
                    delegate: Item {
                        id: card
                        required property var modelData
                        width: albumsView.cellWidth
                        height: albumsView.cellHeight
                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: 18
                            color: cardArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                            Behavior on color { ColorAnimation { duration: Appearance.dur(100) } }
                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 8
                                Art {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: width
                                    source: card.modelData.artUrl
                                    corner: 14
                                    glyph: 44
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.modelData.name
                                        font.pixelSize: Appearance.font.pixelSize.smallie
                                        font.weight: Font.DemiBold
                                        color: ClockStyle.colOnSurface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: card.modelData.artist
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: ClockStyle.colSubtext
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                            MouseArea {
                                id: cardArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.scope("album", card.modelData.name)
                            }
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.albums.length === 0
                        text: Translation.tr("No albums yet")
                        color: ClockStyle.colSubtext
                    }
                }

                // ── Artists ──
                ListView {
                    id: artistsView
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: root.page === "artists"
                    clip: true
                    model: root.artists
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: ar
                        required property var modelData
                        width: ListView.view.width
                        height: 64
                        radius: Appearance.rounding.normal
                        color: arArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 16
                            spacing: 14
                            Art {
                                Layout.preferredWidth: 46
                                Layout.preferredHeight: 46
                                source: ar.modelData.artUrl
                                corner: 23
                                glyph: 22
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: ar.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: ClockStyle.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: Translation.tr("%1 songs").arg(ar.modelData.count)
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: ClockStyle.colSubtext
                            }
                        }
                        MouseArea {
                            id: arArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.scope("artist", ar.modelData.name)
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.artists.length === 0
                        text: Translation.tr("No artists yet")
                        color: ClockStyle.colSubtext
                    }
                }

                // ── Library folders ──
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    visible: root.page === "folders"
                    spacing: 12

                    StyledText {
                        text: Translation.tr("Library folders")
                        font.pixelSize: Appearance.font.pixelSize.huge
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Music in these folders (and their subfolders) is indexed into your library.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: ClockStyle.colSubtext
                    }

                    Repeater {
                        model: root.libraryDirs
                        delegate: Rectangle {
                            id: dirRow
                            required property string modelData
                            Layout.fillWidth: true
                            implicitHeight: 60
                            radius: Appearance.rounding.normal
                            color: ClockStyle.colSurface
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 10
                                spacing: 14
                                MaterialSymbol { text: "folder"; iconSize: 24; fill: 1; color: ClockStyle.colPrimary }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: dirRow.modelData
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: ClockStyle.colOnSurface
                                        elide: Text.ElideMiddle
                                    }
                                    StyledText {
                                        text: Translation.tr("%1 songs").arg(root.songsIn(dirRow.modelData))
                                        font.pixelSize: Appearance.font.pixelSize.smaller
                                        color: ClockStyle.colSubtext
                                    }
                                }
                                Round {
                                    size: 38
                                    iconSize: 20
                                    symbol: "delete"
                                    enabled2: root.libraryDirs.length > 1 || (Persistent.states.background.mediaMode.audioLibraryDirs ?? []).length > 0
                                    onClicked: root.removeDir(dirRow.modelData)
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Rectangle {
                            Layout.fillWidth: true
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: ClockStyle.colField
                            border.width: pathInput.activeFocus ? 2 : 0
                            border.color: ClockStyle.colPrimary
                            TextInput {
                                id: pathInput
                                anchors.fill: parent
                                anchors.leftMargin: 18
                                anchors.rightMargin: 18
                                verticalAlignment: TextInput.AlignVCenter
                                color: ClockStyle.colOnSurface
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.family: Appearance.font.family.main
                                selectByMouse: true
                                clip: true
                                Keys.onReturnPressed: { root.addDir(text); text = ""; }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    visible: pathInput.text.length === 0
                                    text: Translation.tr("Type or paste a folder path")
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.small
                                }
                            }
                        }
                        Round {
                            size: 44
                            symbol: "add"
                            active: true
                            enabled2: pathInput.text.trim().length > 0
                            onClicked: { root.addDir(pathInput.text); pathInput.text = ""; }
                        }
                        Rectangle {
                            implicitWidth: browseRow.implicitWidth + 36
                            implicitHeight: 44
                            radius: Appearance.rounding.full
                            color: ClockStyle.colPrimary
                            RowLayout {
                                id: browseRow
                                anchors.centerIn: parent
                                spacing: 8
                                MaterialSymbol { text: "folder_open"; iconSize: 20; color: ClockStyle.colOnPrimary }
                                StyledText {
                                    text: Translation.tr("Browse…")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    font.weight: Font.DemiBold
                                    color: ClockStyle.colOnPrimary
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: dirPicker.running = true
                            }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                // ── Queue ──
                ListView {
                    id: queueView
                    anchors.fill: parent
                    anchors.margins: 12
                    visible: root.page === "queue"
                    clip: true
                    model: root.queueEntries
                    boundsBehavior: Flickable.StopAtBounds
                    onVisibleChanged: if (visible) {
                        for (let i = 0; i < root.queueEntries.length; ++i)
                            if (String(root.queueEntries[i].entryId ?? "") === root.currentEntryId) {
                                positionViewAtIndex(i, ListView.Center);
                                break;
                            }
                    }
                    delegate: Rectangle {
                        id: qr
                        required property var modelData
                        required property int index
                        readonly property bool playing: String(qr.modelData.entryId ?? "") === root.currentEntryId
                        width: ListView.view.width
                        height: 54
                        radius: Appearance.rounding.small
                        color: qr.playing ? ClockStyle.colSecondaryContainer
                            : (qrArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 8
                            spacing: 12
                            StyledText {
                                Layout.preferredWidth: 28
                                text: qr.playing ? "▶" : String(qr.index + 1)
                                horizontalAlignment: Text.AlignHCenter
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: qr.playing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                            }
                            Art {
                                Layout.preferredWidth: 38
                                Layout.preferredHeight: 38
                                source: String(qr.modelData.artUrl ?? "")
                                corner: 8
                                glyph: 18
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(qr.modelData.title ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.small
                                    color: qr.playing ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(qr.modelData.artist ?? "")
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: ClockStyle.colSubtext
                                    elide: Text.ElideRight
                                }
                            }
                            StyledText {
                                text: root.fmt(Number(qr.modelData.durationSec ?? 0))
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: ClockStyle.colSubtext
                            }
                            Round {
                                size: 34
                                iconSize: 18
                                symbol: "close"
                                opacity: 0.7
                                visible: !qr.playing
                                onClicked: LocalMediaService.removeQueueEntries([String(qr.modelData.entryId)])
                            }
                        }
                        MouseArea {
                            id: qrArea
                            anchors.fill: parent
                            hoverEnabled: true
                            z: -1
                            cursorShape: Qt.PointingHandCursor
                            onClicked: LocalMediaService.playQueueEntry(String(qr.modelData.entryId))
                        }
                    }
                    StyledText {
                        anchors.centerIn: parent
                        visible: root.queueEntries.length === 0
                        text: Translation.tr("The queue is empty")
                        color: ClockStyle.colSubtext
                    }
                }
            }
        }

        // ── Transport ──
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 92
            color: ClockStyle.colSurface

            Rectangle {
                anchors.top: parent.top
                width: parent.width
                height: 1
                color: ClockStyle.colOutline
                opacity: 0.5
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 18
                anchors.rightMargin: 18
                spacing: 18

                // Current track
                RowLayout {
                    Layout.preferredWidth: Math.max(180, root.width * 0.24)
                    Layout.maximumWidth: Math.max(180, root.width * 0.24)
                    spacing: 12
                    Art {
                        Layout.preferredWidth: 58
                        Layout.preferredHeight: 58
                        source: root.player.trackArtUrl
                        corner: 12
                        glyph: 26
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.page = "now"
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: root.hasTrack ? root.player.trackTitle : Translation.tr("Not playing")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.player.trackArtist
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: ClockStyle.colSubtext
                            elide: Text.ElideRight
                        }
                    }
                }

                // Controls and seek
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 6
                        Round {
                            size: 38
                            iconSize: 20
                            symbol: "shuffle"
                            active: root.player.shuffle
                            enabled2: root.hasTrack
                            onClicked: LocalMediaService.setShuffle(!root.player.shuffle)
                        }
                        Round {
                            size: 44
                            iconSize: 28
                            symbol: "skip_previous"
                            filled: true
                            enabled2: root.hasTrack
                            onClicked: LocalMediaService.previous()
                        }
                        Round {
                            size: 54
                            iconSize: 32
                            accent: true
                            symbol: root.player.isPlaying ? "pause" : "play_arrow"
                            enabled2: root.hasTrack
                            onClicked: LocalMediaService.playPause()
                        }
                        Round {
                            size: 44
                            iconSize: 28
                            symbol: "skip_next"
                            filled: true
                            enabled2: root.hasTrack
                            onClicked: LocalMediaService.next()
                        }
                        Round {
                            size: 38
                            iconSize: 20
                            symbol: root.player.loopState === 2 ? "repeat_one" : "repeat"
                            active: root.player.loopState !== 0
                            enabled2: root.hasTrack
                            onClicked: LocalMediaService.setLoopState((root.player.loopState + 1) % 3)
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        StyledText {
                            Layout.preferredWidth: 46
                            horizontalAlignment: Text.AlignRight
                            text: root.fmt(root.shownPos)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: ClockStyle.colSubtext
                        }
                        Item {
                            id: seekBar
                            Layout.fillWidth: true
                            implicitHeight: 20
                            readonly property real frac: root.duration > 0 ? Math.max(0, Math.min(1, root.shownPos / root.duration)) : 0
                            Rectangle {
                                id: seekTrack
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: seekArea.containsMouse || root.seeking ? 8 : 5
                                radius: height / 2
                                color: ClockStyle.colSecondaryContainer
                                Behavior on height { NumberAnimation { duration: Appearance.dur(100) } }
                                Rectangle {
                                    width: parent.width * seekBar.frac
                                    height: parent.height
                                    radius: parent.radius
                                    color: ClockStyle.colPrimary
                                }
                            }
                            Rectangle {
                                x: seekTrack.width * seekBar.frac - width / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: seekArea.containsMouse || root.seeking ? 14 : 0
                                height: width
                                radius: width / 2
                                color: ClockStyle.colPrimary
                                Behavior on width { NumberAnimation { duration: Appearance.dur(100) } }
                            }
                            MouseArea {
                                id: seekArea
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: root.hasTrack && root.player.canSeek && root.duration > 0
                                cursorShape: Qt.PointingHandCursor
                                function value(mx: real): real {
                                    return Math.max(0, Math.min(1, mx / width)) * root.duration;
                                }
                                onPressed: mouse => {
                                    root.seeking = true;
                                    root.seekValue = value(mouse.x);
                                }
                                onPositionChanged: mouse => {
                                    if (pressed)
                                        root.seekValue = value(mouse.x);
                                }
                                onReleased: mouse => {
                                    const target = value(mouse.x);
                                    root.pos = target;
                                    root.basePos = target;
                                    root.baseTime = Date.now();
                                    root.player.seek(target);
                                    root.seeking = false;
                                }
                            }
                        }
                        StyledText {
                            Layout.preferredWidth: 46
                            text: root.fmt(root.duration)
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: ClockStyle.colSubtext
                        }
                    }
                }

                // Volume
                RowLayout {
                    Layout.preferredWidth: Math.max(150, root.width * 0.16)
                    Layout.maximumWidth: Math.max(150, root.width * 0.16)
                    spacing: 6
                    Round {
                        size: 36
                        iconSize: 20
                        symbol: root.player.volume <= 0.001 ? "volume_off" : (root.player.volume < 0.5 ? "volume_down" : "volume_up")
                        onClicked: root.player.volume = root.player.volume > 0.001 ? 0 : 0.7
                    }
                    Item {
                        id: volBar
                        Layout.fillWidth: true
                        implicitHeight: 20
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: 5
                            radius: 3
                            color: ClockStyle.colSecondaryContainer
                            Rectangle {
                                width: parent.width * root.player.volume
                                height: parent.height
                                radius: parent.radius
                                color: ClockStyle.colPrimary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onPressed: mouse => root.player.volume = Math.max(0, Math.min(1, mouse.x / width))
                            onPositionChanged: mouse => {
                                if (pressed)
                                    root.player.volume = Math.max(0, Math.min(1, mouse.x / width));
                            }
                            onWheel: wheel => root.player.volume = Math.max(0, Math.min(1, root.player.volume + (wheel.angleDelta.y > 0 ? 0.04 : -0.04)))
                        }
                    }
                }
            }
        }
    }
}

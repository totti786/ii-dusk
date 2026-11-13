pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Songs, albums and playlists from YouTube Music. */
Rectangle {
    id: root

    property bool compact: false
    property string kind: "songs"
    signal collectionRequested(string kind, string id)

    color: "transparent"

    function focusSearch(): void {
        field.focusInput();
    }

    function run(): void {
        MusicService.search(field.text, root.kind);
    }

    // Results are stale the moment the text moves on from what they were for
    readonly property bool stale: MusicService.searching && MusicService.searchItems.length > 0 && MusicService.searchKind === root.kind
    readonly property bool skeleton: MusicService.searching && (MusicService.searchItems.length === 0 || MusicService.searchKind !== root.kind)

    Component.onCompleted: {
        field.text = MusicService.searchQuery;
        root.kind = MusicService.searchKind;
        Qt.callLater(root.focusSearch);
    }

    Timer {
        id: debounce
        interval: 350
        onTriggered: root.run()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        ClockFormField {
            id: field
            symbol: "search"
            caption: Translation.tr("Search YouTube Music")
            placeholder: Translation.tr("Song, artist or album")
            onAccepted: { debounce.stop(); root.run(); }
            input.onTextChanged: {
                if (field.text.trim().length >= 2)
                    debounce.restart();
                else
                    debounce.stop();
            }
        }

        RowLayout {
            spacing: 8
            Repeater {
                model: [{ id: "songs", label: Translation.tr("Songs"), icon: "music_note" },
                        { id: "artists", label: Translation.tr("Artists"), icon: "person" },
                        { id: "albums", label: Translation.tr("Albums"), icon: "album" },
                        { id: "playlists", label: Translation.tr("Playlists"), icon: "queue_music" }]
                delegate: ClockChip {
                    required property var modelData
                    symbol: modelData.icon
                    label: modelData.label
                    selected: root.kind === modelData.id
                    onClicked: { root.kind = modelData.id; if (field.text.trim().length > 0) root.run(); }
                }
            }
            Item { Layout.fillWidth: true }
            StyledText {
                visible: MusicService.searching
                text: Translation.tr("Searching…")
                color: ClockStyle.colSubtext
            }
        }

        // A thin bar under the chips while a search is out
        StyledIndeterminateProgressBar {
            Layout.fillWidth: true
            Layout.topMargin: -8
            Layout.bottomMargin: -8
            implicitHeight: 3
            opacity: MusicService.searching ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Appearance.dur(150) } }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            // Placeholder rows while the first results are on their way
            Column {
                visible: root.skeleton
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                spacing: 8
                clip: true
                Repeater {
                    model: 7
                    delegate: Row {
                        id: ph
                        required property int index
                        width: parent.width
                        height: 52
                        spacing: 12
                        opacity: 1 - ph.index * 0.1
                        Rectangle { width: 52; height: 52; radius: ClockStyle.radiusSmall; color: ClockStyle.colSurfaceHigh }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8
                            Rectangle { width: 150 + (ph.index * 37) % 120; height: 11; radius: height / 2; color: ClockStyle.colSurfaceHigh }
                            Rectangle { width: 90 + (ph.index * 53) % 80; height: 9; radius: height / 2; color: ClockStyle.colSurfaceHigh }
                        }
                    }
                }
            }

            ClockEmptyState {
                visible: MusicService.searchItems.length === 0 && !MusicService.searching
                anchors.centerIn: parent
                symbol: MusicService.searchError !== "" ? "cloud_off" : "search"
                title: MusicService.searchError !== "" ? Translation.tr("Search failed")
                    : MusicService.searchQuery !== "" ? Translation.tr("No results") : Translation.tr("Find something to play")
                subtitle: MusicService.searchError !== "" ? MusicService.searchError
                    : Translation.tr("Press Enter to search")
            }

            TrackList {
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                visible: root.kind === "songs" && MusicService.searchKind === "songs"
                opacity: root.stale ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(150) } }
                tracks: visible ? MusicService.searchItems : []
            }

            GridView {
                WheelScroll {}
                id: grid
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                visible: root.kind !== "songs" && MusicService.searchKind !== "songs"
                opacity: root.stale ? 0.45 : 1
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(150) } }
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                readonly property int perRow: Math.max(1, Math.floor(width / 176))
                cellWidth: Math.floor(width / perRow)
                cellHeight: 214
                model: visible ? MusicService.searchItems : []
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                delegate: Item {
                    required property var modelData
                    width: grid.cellWidth
                    height: grid.cellHeight
                    Card {
                        anchors.horizontalCenter: parent.horizontalCenter
                        round: parent.modelData.kind === "artist"
                        track: parent.modelData.kind === "album" && (parent.modelData.artistRefs ?? []).length > 0 ? parent.modelData : null
                        path: parent.modelData.thumb ?? ""
                        title: parent.modelData.title
                        subtitle: parent.modelData.kind === "artist" ? Translation.tr("Artist")
                            : [parent.modelData.artist, parent.modelData.year].filter(s => s && String(s).length > 0).join(" · ")
                        onActivated: parent.modelData.kind === "artist"
                            ? MusicService.requestArtist(parent.modelData.id, parent.modelData.title, parent.modelData.art ?? "")
                            : root.collectionRequested(parent.modelData.kind, parent.modelData.id)
                    }
                }
            }
        }
    }
}

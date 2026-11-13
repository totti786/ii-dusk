pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MusicFormat.js" as Fmt

/**
 * An artist: the picture, who they are, play / shuffle / radio / follow, their popular songs,
 * a short bio, albums, singles and similar artists. Follow is a list kept on this machine.
 */
Rectangle {
    id: root

    property bool compact: false
    signal collectionRequested(string kind, string id)

    readonly property var page: MusicService.artist
    readonly property var head: root.page.head ?? ({})
    readonly property var songs: root.page.songs ?? []
    readonly property bool followed: MusicService.isFollowing(root.head.id ?? "")
    property bool allSongs: false
    property bool bioOpen: false
    readonly property var shownSongs: root.allSongs ? root.songs : root.songs.slice(0, 5)
    readonly property string meta: [
        root.head.subscribers ? Translation.tr("%1 subscribers").arg(root.head.subscribers) : "",
        root.head.monthly ? Translation.tr("%1 monthly listeners").arg(root.head.monthly) : ""
    ].filter(s => s.length > 0).join("  ·  ")

    color: "transparent"

    function shuffled(list: var): var {
        const out = list.slice();
        for (let i = out.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [out[i], out[j]] = [out[j], out[i]];
        }
        return out;
    }

    StyledText {
        visible: MusicService.artistLoading
        anchors.centerIn: parent
        text: Translation.tr("Loading…")
        color: ClockStyle.colSubtext
    }
    StyledText {
        visible: !MusicService.artistLoading && MusicService.artistError !== ""
        anchors.centerIn: parent
        text: MusicService.artistError
        color: ClockStyle.colError
    }

    /// A row of covers with a heading: albums, singles, similar artists
    component Shelf: ColumnLayout {
        id: shelf
        property string title: ""
        property var items: []
        property bool round: false
        signal picked(var item)

        Layout.fillWidth: true
        visible: shelf.items.length > 0
        spacing: 10

        StyledText {
            text: shelf.title
            color: ClockStyle.colOnBackground
            font.pixelSize: ClockStyle.textLarge
            font.weight: Font.DemiBold
        }
        ListView {
            WheelScroll {}
            Layout.fillWidth: true
            Layout.preferredHeight: 214
            orientation: ListView.Horizontal
            spacing: 16
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: shelf.items
            delegate: Card {
                required property var modelData
                round: shelf.round
                path: modelData.thumb ?? ""
                title: modelData.title
                subtitle: modelData.year ?? ""
                onActivated: shelf.picked(modelData)
            }
        }
    }

    Flickable {
        id: flick
        WheelScroll {}
        anchors.fill: parent
        visible: !MusicService.artistLoading && MusicService.artistError === ""
        contentWidth: width
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 22

            // ── the picture and the name ──
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.compact ? 190 : 260
                radius: ClockStyle.radiusCard
                color: ClockStyle.colSurfaceHigh
                clip: true

                Image {
                    id: banner
                    anchors.fill: parent
                    source: Fmt.fileUrl(root.head.banner ?? "")
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    opacity: status === Image.Ready ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Appearance.dur(260) } }
                }
                MaterialSymbol {
                    visible: banner.status !== Image.Ready
                    anchors.centerIn: parent
                    text: "person"
                    iconSize: 96
                    color: ClockStyle.colSubtext
                    opacity: 0.4
                }
                // Dark toward the bottom, so the name reads on any picture
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#00000000" }
                        GradientStop { position: 0.5; color: "#33000000" }
                        GradientStop { position: 1.0; color: "#D9000000" }
                    }
                }
                RowLayout {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: root.compact ? 14 : 22
                    spacing: 16
                    RoundedCover {
                        visible: (root.head.avatar ?? "") !== "" && !root.compact
                        Layout.preferredWidth: 84
                        Layout.preferredHeight: 84
                        radius: Layout.preferredWidth / 2
                        symbol: "person"
                        path: root.head.avatar ?? ""
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            Layout.fillWidth: true
                            text: root.head.name ?? ""
                            color: "white"
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: root.compact ? 28 : 40
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            visible: root.meta.length > 0
                            text: root.meta
                            color: "#D9FFFFFF"
                            elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── what to do ──
            Flow {
                Layout.fillWidth: true
                spacing: 10
                ClockButton {
                    variant: "filled"
                    symbol: "play_arrow"
                    label: Translation.tr("Play")
                    enabled: root.songs.length > 0
                    onClicked: MusicService.play(root.songs, 0)
                }
                ClockButton {
                    symbol: "shuffle"
                    label: Translation.tr("Shuffle")
                    enabled: root.songs.length > 0
                    onClicked: MusicService.play(root.shuffled(root.songs), 0)
                }
                ClockButton {
                    visible: (root.head.radioId ?? "") !== ""
                    symbol: "sensors"
                    label: Translation.tr("Radio")
                    onClicked: MusicService.playArtistRadio(root.head.radioId)
                }
                ClockButton {
                    variant: root.followed ? "filled" : "tonal"
                    symbol: root.followed ? "check" : "person_add"
                    label: root.followed ? Translation.tr("Following") : Translation.tr("Follow")
                    onClicked: MusicService.toggleFollow(root.head.id ?? "", root.head.name ?? "", root.head.art ?? "")
                }
            }

            // ── popular songs ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: root.songs.length > 0
                spacing: 6
                StyledText {
                    text: Translation.tr("Popular")
                    color: ClockStyle.colOnBackground
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }
                Repeater {
                    model: root.shownSongs
                    delegate: TrackRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        track: modelData
                        rowIndex: index
                        showIndex: true
                        onActivated: MusicService.play(root.songs, index)
                    }
                }
                ClockButton {
                    visible: root.songs.length > 5
                    variant: "text"
                    symbol: root.allSongs ? "expand_less" : "expand_more"
                    label: root.allSongs ? Translation.tr("Show fewer") : Translation.tr("Show all %1 songs").arg(root.songs.length)
                    onClicked: root.allSongs = !root.allSongs
                }
            }

            Shelf {
                title: Translation.tr("Albums")
                items: root.page.albums ?? []
                onPicked: item => root.collectionRequested("album", item.id)
            }
            Shelf {
                title: Translation.tr("Singles & EPs")
                items: root.page.singles ?? []
                onPicked: item => root.collectionRequested("album", item.id)
            }

            // ── about ──
            ColumnLayout {
                Layout.fillWidth: true
                visible: (root.head.description ?? "") !== ""
                spacing: 6
                StyledText {
                    text: Translation.tr("About")
                    color: ClockStyle.colOnBackground
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.head.description ?? ""
                    color: ClockStyle.colOnSurfaceVariant
                    wrapMode: Text.Wrap
                    maximumLineCount: root.bioOpen ? 40 : 3
                    elide: Text.ElideRight
                }
                ClockButton {
                    variant: "text"
                    symbol: root.bioOpen ? "expand_less" : "expand_more"
                    label: root.bioOpen ? Translation.tr("Less") : Translation.tr("More")
                    onClicked: root.bioOpen = !root.bioOpen
                }
            }

            Shelf {
                title: Translation.tr("Fans also like")
                round: true
                items: root.page.related ?? []
                onPicked: item => MusicService.requestArtist(item.id, item.title, item.art ?? "")
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** An album or a playlist: the cover and title, play and shuffle, and the songs. */
Rectangle {
    id: root

    property bool compact: false
    readonly property var head: MusicService.collection.head ?? ({})
    readonly property var tracks: MusicService.collection.tracks ?? []

    color: "transparent"

    StyledText {
        visible: MusicService.collectionLoading
        anchors.centerIn: parent
        text: Translation.tr("Loading…")
        color: ClockStyle.colSubtext
    }
    StyledText {
        visible: MusicService.collectionError !== ""
        anchors.centerIn: parent
        text: MusicService.collectionError
        color: ClockStyle.colError
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14
        visible: !MusicService.collectionLoading && MusicService.collectionError === ""

        RowLayout {
            Layout.fillWidth: true
            spacing: 18
            RoundedCover {
                Layout.preferredWidth: root.compact ? 110 : 160
                Layout.preferredHeight: Layout.preferredWidth
                radius: ClockStyle.radiusNormal
                path: root.head.thumb ?? ""
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 4
                StyledText {
                    Layout.fillWidth: true
                    text: root.head.title ?? ""
                    color: ClockStyle.colOnBackground
                    font.pixelSize: ClockStyle.textTitle
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }
                ArtistLink {
                    Layout.fillWidth: true
                    track: ({ artist: root.head.artist ?? "", artistRefs: root.head.artistRefs ?? [] })
                    linked: (root.head.artistRefs ?? []).length > 0
                    suffix: " · " + [root.head.year, Translation.tr("%1 songs").arg(root.tracks.length)]
                        .filter(s => s && String(s).length > 0).join(" · ")
                    pixelSize: Appearance.font.pixelSize.small
                }
                RowLayout {
                    Layout.topMargin: 10
                    spacing: 10
                    ClockButton {
                        variant: "filled"
                        symbol: "play_arrow"
                        label: Translation.tr("Play")
                        enabled: root.tracks.length > 0
                        onClicked: MusicService.play(root.tracks, 0)
                    }
                    ClockButton {
                        symbol: "shuffle"
                        label: Translation.tr("Shuffle")
                        enabled: root.tracks.length > 0
                        onClicked: {
                            const shuffled = root.tracks.slice();
                            for (let i = shuffled.length - 1; i > 0; i--) {
                                const j = Math.floor(Math.random() * (i + 1));
                                [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
                            }
                            MusicService.play(shuffled, 0);
                        }
                    }
                }
            }
        }

        TrackList {
            Layout.fillWidth: true
            Layout.fillHeight: true
            tracks: root.tracks
            asQueue: true
            showIndex: true
        }
    }
}

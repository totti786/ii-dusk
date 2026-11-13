pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Favourites, downloads, play history and what the player has learned, all kept on this machine. */
Rectangle {
    id: root

    property bool compact: false
    property string section: "favorites"
    readonly property bool isTaste: root.section === "taste"
    readonly property bool isArtists: root.section === "artists"
    // The shuffle button over the page reads this: no songs in the artists list
    readonly property var tracks: root.isArtists ? [] : root.section === "favorites" ? MusicService.favorites
        : root.section === "downloads" ? MusicService.downloads : MusicService.history

    color: "transparent"
    Component.onCompleted: {
        MusicService.loadLibrary();
        MusicService.loadDownloads();
        MusicService.loadTaste();
        MusicService.loadFollowing();
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            spacing: 8
            ClockChip {
                symbol: "favorite"
                label: Translation.tr("Favourites")
                selected: root.section === "favorites"
                onClicked: root.section = "favorites"
            }
            ClockChip {
                symbol: "person"
                label: Translation.tr("Artists")
                selected: root.isArtists
                onClicked: root.section = "artists"
            }
            ClockChip {
                symbol: "download_done"
                label: Translation.tr("Downloads")
                selected: root.section === "downloads"
                onClicked: root.section = "downloads"
            }
            ClockChip {
                symbol: "history"
                label: Translation.tr("History")
                selected: root.section === "history"
                onClicked: root.section = "history"
            }
            ClockChip {
                symbol: "insights"
                label: Translation.tr("Your taste")
                selected: root.isTaste
                onClicked: root.section = "taste"
            }
            Item { Layout.fillWidth: true }
            ClockButton {
                visible: root.section === "favorites" && root.tracks.length > 0
                variant: "text"
                symbol: "download"
                label: Translation.tr("Download all")
                onClicked: MusicService.downloadLikes()
            }
            ClockButton {
                visible: !root.isTaste && !root.isArtists && root.tracks.length > 0
                variant: "tonal"
                symbol: "play_arrow"
                label: Translation.tr("Play all")
                onClicked: MusicService.play(root.tracks, 0)
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            ClockEmptyState {
                visible: !root.isTaste && !root.isArtists && root.tracks.length === 0
                anchors.centerIn: parent
                symbol: root.section === "favorites" ? "favorite" : root.section === "downloads" ? "download" : "history"
                title: root.section === "favorites" ? Translation.tr("No favourites yet")
                    : root.section === "downloads" ? Translation.tr("No downloads yet") : Translation.tr("Nothing played yet")
                subtitle: root.section === "favorites" ? Translation.tr("Tap the heart on a song to keep it here")
                    : root.section === "downloads" ? Translation.tr("Tap the download arrow on a song to keep it for offline")
                    : Translation.tr("What you play will be listed here")
            }

            TastePage {
                visible: root.isTaste
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
            }

            ClockEmptyState {
                visible: root.isArtists && MusicService.following.length === 0
                anchors.centerIn: parent
                symbol: "person_add"
                title: Translation.tr("Not following anyone yet")
                subtitle: Translation.tr("Open an artist and press Follow to keep them here")
            }

            GridView {
                id: followGrid
                WheelScroll {}
                visible: root.isArtists && MusicService.following.length > 0
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                readonly property int perRow: Math.max(1, Math.floor(width / 176))
                cellWidth: Math.floor(width / perRow)
                cellHeight: 214
                model: visible ? MusicService.following : []
                delegate: Item {
                    required property var modelData
                    width: followGrid.cellWidth
                    height: followGrid.cellHeight
                    Card {
                        anchors.horizontalCenter: parent.horizontalCenter
                        round: true
                        path: parent.modelData.thumb ?? ""
                        title: parent.modelData.title
                        subtitle: Translation.tr("Artist")
                        onActivated: MusicService.requestArtist(parent.modelData.id, parent.modelData.title, parent.modelData.art ?? "")
                    }
                }
            }

            TrackList {
                visible: !root.isTaste && !root.isArtists
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                tracks: root.tracks
                asQueue: true
            }
        }
    }
}

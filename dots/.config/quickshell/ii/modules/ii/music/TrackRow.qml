pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MusicFormat.js" as Fmt

/** One song: cover, title and artist, and what can be done with it. */
Rectangle {
    id: root

    required property var track
    property int rowIndex: 0
    property bool current: MusicService.hasTrack && MusicService.track.id === root.track.id
    property bool removable: false
    property bool showIndex: false

    signal activated()
    signal removeRequested()

    // A handler, not the areas' hover: a button over the row takes the hover from the row's
    // area, which hid the buttons and made the row flicker.
    readonly property bool hovered: rowHover.hovered

    HoverHandler {
        id: rowHover
    }
    implicitHeight: 60
    radius: ClockStyle.radiusNormal
    color: root.current ? ClockStyle.colSecondaryContainer
         : root.hovered ? ClockStyle.colSurfaceHigh : "transparent"
    Behavior on color { ColorAnimation { duration: Appearance.dur(120) } }

    MouseArea {
        id: rowArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 12
        spacing: 12

        StyledText {
            visible: root.showIndex
            Layout.preferredWidth: 26
            horizontalAlignment: Text.AlignRight
            text: root.current ? "" : String(root.rowIndex + 1)
            color: ClockStyle.colSubtext
        }

        RoundedCover {
            Layout.preferredWidth: 44
            Layout.preferredHeight: 44
            radius: ClockStyle.radiusSmall - 4
            path: root.track.thumb ?? ""

            Rectangle {
                anchors.fill: parent
                radius: ClockStyle.radiusSmall - 4
                color: Qt.alpha(ClockStyle.colScrim, 0.4)
                visible: root.current || root.hovered
                Rectangle {
                    anchors.centerIn: parent
                    width: 30
                    height: 30
                    radius: width / 2
                    color: ClockStyle.colPrimaryContainer
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: root.current && MusicService.playing ? "equalizer" : "play_arrow"
                        fill: 1
                        iconSize: 20
                        color: ClockStyle.colOnPrimaryContainer
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1
            StyledText {
                Layout.fillWidth: true
                text: root.track.title ?? ""
                color: root.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnBackground
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            ArtistLink {
                Layout.fillWidth: true
                track: root.track
                suffix: root.track.album ? " · " + root.track.album : ""
                color: root.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                hoverColor: root.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colPrimary
            }
        }

        MaterialSymbol {
            visible: (root.track.cached ?? false) && !MusicService.isDownloaded(root.track.id)
                && !MusicService.isDownloading(root.track.id)
            text: "offline_pin"
            iconSize: 18
            color: ClockStyle.colSubtext
            opacity: 0.8
        }

        ClockIconButton {
            visible: root.hovered && !root.removable
            symbol: "queue_music"
            tooltip: Translation.tr("Play next")
            onClicked: MusicService.enqueue(root.track, true)
        }
        ClockIconButton {
            visible: root.hovered && !root.removable
            symbol: "playlist_add"
            tooltip: Translation.tr("Add to queue")
            onClicked: MusicService.enqueue(root.track, false)
        }
        ClockIconButton {
            visible: root.removable && root.hovered && !root.current
            symbol: "close"
            tooltip: Translation.tr("Remove from the queue")
            onClicked: root.removeRequested()
        }

        ClockIconButton {
            id: dl
            readonly property bool done: MusicService.isDownloaded(root.track.id)
            readonly property bool busy: MusicService.isDownloading(root.track.id)
            visible: done || busy || root.hovered
            size: 36
            iconSize: 20
            symbol: done ? "download_done" : busy ? "downloading" : "download"
            colIcon: done ? ClockStyle.colPrimary : ClockStyle.colOnSurfaceVariant
            tooltip: done ? Translation.tr("Remove the download") : Translation.tr("Download for offline")
            onClicked: MusicService.toggleDownload(root.track)
        }

        ClockIconButton {
            id: heart
            readonly property bool on: MusicService.isFav(root.track.id)
            visible: on || root.hovered
            size: 36
            iconSize: 20
            symbol: "favorite"
            filled: on
            colIcon: on ? ClockStyle.colError : ClockStyle.colOnSurfaceVariant
            tooltip: on ? Translation.tr("Remove from favourites") : Translation.tr("Favourite")
            onClicked: MusicService.toggleFav(root.track)
        }

        StyledText {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            text: Fmt.time(root.track.duration)
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
        }
    }
}

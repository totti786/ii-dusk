pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** What plays next, in order. */
Rectangle {
    id: root

    property bool compact: false
    color: "transparent"

    ColumnLayout {
        anchors.fill: parent
        spacing: 12

        RowLayout {
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 in the queue").arg(MusicService.queue.length)
                color: ClockStyle.colSubtext
            }
            ClockButton {
                visible: MusicService.queue.length > 1
                variant: "text"
                symbol: "delete_sweep"
                label: Translation.tr("Clear")
                onClicked: MusicService.clearQueue()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            ClockEmptyState {
                visible: MusicService.queue.length === 0
                anchors.centerIn: parent
                symbol: "queue_music"
                title: Translation.tr("The queue is empty")
                subtitle: Translation.tr("Play something, or add songs with the + button on a song")
            }

            ListView {
                WheelScroll {}
                id: list
                anchors.fill: parent
                anchors.margins: ClockStyle.gap
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                spacing: 2
                model: MusicService.queue
                currentIndex: MusicService.queueIndex
                ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }
                Component.onCompleted: positionViewAtIndex(Math.max(0, MusicService.queueIndex), ListView.Beginning)
                delegate: TrackRow {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    track: modelData
                    rowIndex: index
                    removable: true
                    showIndex: true
                    current: index === MusicService.queueIndex
                    onActivated: MusicService.jump(index)
                    onRemoveRequested: MusicService.removeFromQueue(index)
                }
            }
        }
    }
}

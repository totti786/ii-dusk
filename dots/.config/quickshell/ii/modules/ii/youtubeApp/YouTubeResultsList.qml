pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A pane-sized list with a shared loading, empty and retry state. */
FocusScope {
    id: root

    required property var service
    property var entries: []
    property bool loading: false
    property string error: ""
    property string emptyTitle: Translation.tr("No videos yet")
    property string emptySubtitle: ""
    property string emptySymbol: "video_library"

    signal retry()

    Rectangle {
        anchors.fill: parent
        radius: ClockStyle.radiusCard
        color: ClockStyle.colPane
        clip: true
        Accessible.role: Accessible.List
        Accessible.name: Translation.tr("YouTube videos")

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: ClockStyle.gapSmall
            clip: true
            spacing: ClockStyle.gapTiny
            model: root.entries
            boundsBehavior: Flickable.StopAtBounds
            WheelScroll {}

            delegate: YouTubeVideoRow {
                width: list.width
                service: root.service
            }
        }

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(480, parent.width - ClockStyle.gapHuge * 2)
            spacing: ClockStyle.gap
            visible: root.entries.length === 0

            ClockEmptyState {
                Layout.alignment: Qt.AlignHCenter
                symbol: root.loading ? "hourglass_top" : (root.error.length > 0 ? "cloud_off" : root.emptySymbol)
                title: root.loading ? Translation.tr("Loading videos…")
                    : root.error.length > 0 ? Translation.tr("Could not load videos") : root.emptyTitle
                subtitle: root.loading ? Translation.tr("Finding public videos for this view.")
                    : root.error.length > 0 ? root.error : root.emptySubtitle
                shapeSize: ClockStyle.emptyShapeSmall
            }

            ClockButton {
                Layout.alignment: Qt.AlignHCenter
                visible: root.error.length > 0 && !root.loading
                symbol: "refresh"
                label: Translation.tr("Try again")
                variant: "tonal"
                scaleBehaviorEnabled: false
                Accessible.name: Translation.tr("Try loading videos again")
                onClicked: root.retry()
            }
        }
    }
}

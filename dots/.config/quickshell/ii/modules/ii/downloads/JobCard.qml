pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "DownloadsFormat.js" as Fmt

/** One download: thumbnail, title, a line of progress, and what can be done with it. */
Rectangle {
    id: root

    required property var job
    readonly property bool active: ["queued", "running", "processing"].includes(job.status)
    readonly property bool failed: job.status === "error"

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusLarge
    color: ClockStyle.colSurfaceHigh

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        Rectangle {
            Layout.preferredWidth: 120
            Layout.preferredHeight: 68
            radius: ClockStyle.radiusNormal
            color: ClockStyle.colSurfaceHigh
            clip: true

            Image {
                anchors.fill: parent
                source: root.job.thumbnail ?? ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
            MaterialSymbol {
                visible: (root.job.thumbnail ?? "") === ""
                anchors.centerIn: parent
                text: ["mp3", "opus"].includes(root.job.preset) ? "music_note" : "movie"
                iconSize: 28
                color: ClockStyle.colSubtext
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4

            StyledText {
                Layout.fillWidth: true
                text: root.job.current && root.job.playlist ? `${root.job.title} — ${root.job.current}` : root.job.title
                color: ClockStyle.colOnBackground
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: Fmt.jobLine(root.job)
                color: root.failed ? ClockStyle.colError : ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
            Rectangle {
                visible: root.active
                Layout.fillWidth: true
                Layout.preferredHeight: 6
                radius: 3
                color: ClockStyle.colSurfaceHighest
                Rectangle {
                    width: parent.width * (root.job.status === "processing" ? 1 : Math.max(0, Math.min(100, root.job.percent)) / 100)
                    height: parent.height
                    radius: 3
                    color: ClockStyle.colPrimary
                    opacity: root.job.status === "queued" ? 0.3 : 1
                    Behavior on width {
                        enabled: !ClockStyle.reducedMotion
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                }
            }
        }

        ClockIconButton {
            visible: root.job.status === "done"
            symbol: "play_arrow"
            tooltip: Translation.tr("Open the file")
            onClicked: DownloadsService.openFile(root.job)
        }
        ClockIconButton {
            visible: root.job.status === "done"
            symbol: "folder_open"
            tooltip: Translation.tr("Show in folder")
            onClicked: DownloadsService.openFolder(root.job.dir)
        }
        ClockIconButton {
            visible: root.active
            symbol: "close"
            tooltip: Translation.tr("Cancel")
            onClicked: DownloadsService.cancel(root.job.id)
        }
        ClockIconButton {
            visible: !root.active
            symbol: "delete"
            tooltip: Translation.tr("Remove from the list")
            onClicked: DownloadsService.remove(root.job.id)
        }
    }
}

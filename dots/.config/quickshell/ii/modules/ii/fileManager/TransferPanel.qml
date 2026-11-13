pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Running and just-finished operations, bottom right, each with progress and a cancel button.
Item {
    id: root

    property var jobs: []

    signal cancelRequested(int id)
    signal dismissRequested(int id)

    implicitWidth: 360
    implicitHeight: col.implicitHeight

    function bytes(s: real): string {
        if (s < 1024 * 1024)
            return Math.round(s / 1024) + " KiB";
        if (s < 1024 * 1024 * 1024)
            return (s / 1048576).toFixed(1) + " MiB";
        return (s / 1073741824).toFixed(2) + " GiB";
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Repeater {
            model: root.jobs
            delegate: Rectangle {
                id: job
                required property var modelData
                readonly property real frac: modelData.total > 0 ? Math.min(1, modelData.done / modelData.total) : 0
                readonly property bool finished: modelData.state !== "running"
                width: col.width
                height: 78
                radius: Appearance.rounding.large
                color: ClockStyle.colSheet

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 14
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialSymbol {
                            text: job.modelData.state === "error" ? "error" : job.finished ? "check_circle" : (job.modelData.icon ?? "sync")
                            iconSize: 20
                            fill: 1
                            color: job.modelData.state === "error" ? ClockStyle.colError : ClockStyle.colPrimary
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: job.modelData.title
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: ClockStyle.colOnSurface
                            elide: Text.ElideRight
                        }
                        FmIconButton {
                            size: 26
                            iconSize: 17
                            symbol: "close"
                            tip: job.finished ? qsTr("Dismiss") : qsTr("Cancel")
                            onClicked: job.finished ? root.dismissRequested(job.modelData.id) : root.cancelRequested(job.modelData.id)
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: ClockStyle.colSecondaryContainer
                        Rectangle {
                            width: parent.width * (job.finished ? 1 : job.frac)
                            height: parent.height
                            radius: 3
                            color: job.modelData.state === "error" ? ClockStyle.colError : ClockStyle.colPrimary
                            Behavior on width { NumberAnimation { duration: Appearance.dur(120) } }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: job.modelData.state === "error" ? job.modelData.message
                            : job.finished ? job.modelData.message
                            : (job.modelData.total > 1 ? root.bytes(job.modelData.done) + " / " + root.bytes(job.modelData.total) + (job.modelData.speed > 0 ? "  ·  " + root.bytes(job.modelData.speed) + "/s" : "") : job.modelData.current)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ClockStyle.colSubtext
                        elide: Text.ElideMiddle
                    }
                }
            }
        }
    }
}

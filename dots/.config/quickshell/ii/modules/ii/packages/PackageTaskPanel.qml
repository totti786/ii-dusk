pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The change that is running, or the one that just ended: its title, state and pacman's output. */
Rectangle {
    id: root

    readonly property bool running: PackagesService.taskRunning
    readonly property int exitCode: PackagesService.taskExit
    readonly property bool ok: root.exitCode === 0

    visible: PackagesService.taskShown
    z: 10
    radius: ClockStyle.radiusExtraLarge
    color: ClockStyle.colSheet
    border.width: 1
    border.color: ClockStyle.colOutline
    implicitHeight: Math.min(parent.height * 0.6, 120 + Math.min(log.count, 12) * 18)

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.gapLarge
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            MaterialSymbol {
                text: root.running ? "hourglass_top" : (root.ok ? "check_circle" : "error")
                fill: 1
                iconSize: 26
                color: root.running ? ClockStyle.colPrimary : (root.ok ? ClockStyle.colPrimary : ClockStyle.colError)
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: PackagesService.taskTitle
                    color: ClockStyle.colOnBackground
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.running ? Translation.tr("Working. Enter your password if asked.")
                        : root.ok ? Translation.tr("Done")
                        : root.exitCode === 126 || root.exitCode === 127 ? Translation.tr("Not allowed, or the password prompt was dismissed")
                        : Translation.tr("Failed (exit code %1). The output below says why.").arg(root.exitCode)
                    color: root.running || root.ok ? ClockStyle.colSubtext : ClockStyle.colError
                    font.pixelSize: ClockStyle.textSmall
                }
            }
            ClockButton {
                visible: !root.running
                variant: "tonal"
                label: Translation.tr("Close")
                onClicked: PackagesService.dismissTask()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusNormal
            color: ClockStyle.colBackground
            clip: true

            ListView {
                WheelScroll {}
                id: log
                anchors.fill: parent
                anchors.margins: ClockStyle.gapSmall
                model: PackagesService.taskLog
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                onCountChanged: Qt.callLater(() => log.positionViewAtEnd())
                delegate: StyledText {
                    required property string modelData
                    width: log.width
                    text: modelData
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }
}

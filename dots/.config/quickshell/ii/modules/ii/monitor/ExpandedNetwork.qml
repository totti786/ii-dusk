pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/// The network card expanded: speeds, peaks, totals and every interface to pick from.
Item {
    id: root
    readonly property var nic: MonitorService.mainNet
    readonly property real peakRx: MonitorService.rxHistory.reduce((a, b) => Math.max(a, b), 0)
    readonly property real peakTx: MonitorService.txHistory.reduce((a, b) => Math.max(a, b), 0)

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StatTile { label: Translation.tr("Download"); value: Fmt.rate(MonitorService.rx); valueColor: ClockStyle.colPrimary }
            StatTile { label: Translation.tr("Upload"); value: Fmt.rate(MonitorService.tx); valueColor: ClockStyle.colTertiary }
            StatTile { label: Translation.tr("Peak down"); value: Fmt.rate(root.peakRx) }
            StatTile { label: Translation.tr("Peak up"); value: Fmt.rate(root.peakTx) }
            StatTile { label: Translation.tr("Received in total"); value: root.nic ? Fmt.bytes(root.nic.rx_total) : "-" }
            StatTile { label: Translation.tr("Sent in total"); value: root.nic ? Fmt.bytes(root.nic.tx_total) : "-" }
        }

        NetworkGraph {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            Layout.minimumHeight: 140
            down: MonitorService.rxHistory
            up: MonitorService.txHistory
        }

        StyledText { text: Translation.tr("Interfaces"); color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
        Repeater {
            model: MonitorService.net.filter(n => n.name !== "lo")
            delegate: Rectangle {
                id: nrow
                required property var modelData
                readonly property bool current: root.nic !== null && nrow.modelData.name === root.nic.name
                Layout.fillWidth: true
                implicitHeight: 34
                radius: ClockStyle.radiusNormal
                color: nrow.current ? ClockStyle.colSecondaryContainer : ClockStyle.colSurfaceHighest
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 12
                    StyledText { Layout.preferredWidth: 120; text: nrow.modelData.name; color: ClockStyle.colOnBackground; font.weight: Font.Medium; elide: Text.ElideRight }
                    StyledText { Layout.fillWidth: true; text: nrow.modelData.ip ?? ""; color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall; elide: Text.ElideRight }
                    StyledText { text: `↓ ${Fmt.rate(nrow.modelData.rx)}   ↑ ${Fmt.rate(nrow.modelData.tx)}`; color: ClockStyle.colOnBackground; font.pixelSize: ClockStyle.textSmall }
                    StyledText { text: nrow.modelData.up ? Translation.tr("up") : Translation.tr("down"); color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: MonitorService.selectedNic = nrow.modelData.name
                }
            }
        }
    }
}

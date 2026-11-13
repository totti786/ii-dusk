pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/// The processor card expanded: big history, every core with its own sparkline, sensors and load.
Item {
    id: root

    readonly property var perCore: MonitorService.cores
    readonly property real avgGhz: MonitorService.freq.length > 0 ? MonitorService.freq.reduce((a, b) => a + b, 0) / MonitorService.freq.length / 1000 : 0
    property var coreHistory: []
    onPerCoreChanged: {
        const next = root.coreHistory.slice();
        for (let i = 0; i < root.perCore.length; i++) {
            const h = (next[i] ?? []).concat([root.perCore[i]]);
            next[i] = h.length > 60 ? h.slice(h.length - 60) : h;
        }
        root.coreHistory = next;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StatTile { label: Translation.tr("Load"); value: Fmt.percent(MonitorService.cpu); valueColor: MonitorService.cpu >= 90 ? ClockStyle.colError : ClockStyle.colOnBackground }
            StatTile { label: Translation.tr("Average clock"); value: root.avgGhz > 0 ? `${root.avgGhz.toFixed(2)} GHz` : "-" }
            StatTile { label: Translation.tr("Temperature"); value: MonitorService.temps.cpu > 0 ? `${Math.round(MonitorService.temps.cpu)} °C` : "-" }
            StatTile { label: Translation.tr("Load average"); value: `${MonitorService.load[0]}  ${MonitorService.load[1]}  ${MonitorService.load[2]}` }
            StatTile { label: Translation.tr("Tasks"); value: Translation.tr("%1 · %2 threads").arg(MonitorService.tasks).arg(MonitorService.threads) }
            StatTile { label: Translation.tr("Uptime"); value: Fmt.duration(MonitorService.uptime) }
        }

        MonitorGraph {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            values: MonitorService.cpuHistory
            floorMax: 25
        }

        // Every core with the last minute of its own load
        GridLayout {
            Layout.fillWidth: true
            columns: Math.max(2, Math.min(4, Math.ceil(MonitorService.cores.length / 3)))
            columnSpacing: 10
            rowSpacing: 10

            Repeater {
                model: MonitorService.cores.length
                delegate: Rectangle {
                    id: core
                    required property int index
                    readonly property real pct: MonitorService.cores[index] ?? 0
                    readonly property real ghz: (MonitorService.freq[index] ?? 0) / 1000
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: 58
                    radius: ClockStyle.radiusNormal
                    color: ClockStyle.colSurfaceHighest

                    MonitorGraph {
                        anchors.fill: parent
                        anchors.margins: 4
                        grid: false
                        lineWidth: 1.5
                        length: 60
                        values: root.coreHistory[core.index] ?? []
                        floorMax: 20
                        lineColor: core.pct >= 90 ? ClockStyle.colError : ClockStyle.colPrimary
                    }
                    StyledText {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 8
                        text: Translation.tr("Core %1").arg(core.index)
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    StyledText {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        text: `${Math.round(core.pct)}%${core.ghz > 0 ? "  " + core.ghz.toFixed(1) + " GHz" : ""}`
                        color: ClockStyle.colOnBackground
                        font.weight: Font.Medium
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }
        }

        // The other sensors the kernel reports
        Flow {
            Layout.fillWidth: true
            visible: MonitorService.temps.sensors.length > 1
            spacing: 8
            Repeater {
                model: MonitorService.temps.sensors
                delegate: Rectangle {
                    id: sensor
                    required property var modelData
                    width: sensorRow.implicitWidth + 20
                    height: 28
                    radius: 14
                    color: ClockStyle.colSurfaceHighest
                    Row {
                        id: sensorRow
                        anchors.centerIn: parent
                        spacing: 8
                        StyledText { text: sensor.modelData.name; color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                        StyledText { text: `${Math.round(sensor.modelData.temp)} °C`; color: ClockStyle.colOnBackground; font.pixelSize: ClockStyle.textSmall; font.weight: Font.Medium }
                    }
                }
            }
        }
    }
}

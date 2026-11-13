pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/// Memory and storage expanded: where the memory goes, its history, disk traffic and every mount.
Item {
    id: root
    readonly property var m: MonitorService.mem
    readonly property real other: Math.max(0, root.m.total - root.m.used - root.m.cached - root.m.buffers - root.m.free)

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            StatTile { label: Translation.tr("Used"); value: `${Fmt.bytes(root.m.used)} · ${Math.round(100 * root.m.used / Math.max(1, root.m.total))}%` }
            StatTile { label: Translation.tr("Cached"); value: Fmt.bytes(root.m.cached) }
            StatTile { label: Translation.tr("Buffers"); value: Fmt.bytes(root.m.buffers) }
            StatTile { label: Translation.tr("Free"); value: Fmt.bytes(root.m.free) }
            StatTile { label: Translation.tr("Swap"); value: root.m.swap_total > 0 ? `${Fmt.bytes(root.m.swap_used)} of ${Fmt.bytes(root.m.swap_total)}` : Translation.tr("none") }
        }

        // One bar split into used, cached and buffers
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 14
            radius: 7
            color: ClockStyle.colSurfaceHighest
            clip: true
            Row {
                anchors.fill: parent
                Rectangle { width: parent.width * root.m.used / Math.max(1, root.m.total); height: parent.height; color: ClockStyle.colTertiary }
                Rectangle { width: parent.width * root.m.cached / Math.max(1, root.m.total); height: parent.height; color: ClockStyle.colPrimary; opacity: 0.7 }
                Rectangle { width: parent.width * root.m.buffers / Math.max(1, root.m.total); height: parent.height; color: ClockStyle.colSubtext; opacity: 0.6 }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            spacing: 14

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 6
                StyledText { text: Translation.tr("Memory use"); color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                MonitorGraph {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 80
                    values: MonitorService.memHistory
                    maxValue: 100
                    lineColor: ClockStyle.colTertiary
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                spacing: 6
                RowLayout {
                    Layout.fillWidth: true
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Disk traffic"); color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                    StyledText { text: `${Translation.tr("read")} ${Fmt.rate(MonitorService.io.read)}   ${Translation.tr("write")} ${Fmt.rate(MonitorService.io.write)}`; color: ClockStyle.colOnBackground; font.pixelSize: ClockStyle.textSmall }
                }
                MonitorGraph {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 80
                    values: MonitorService.ioReadHistory
                    secondary: MonitorService.ioWriteHistory
                    floorMax: 1024 * 1024
                }
            }
        }

        // Every mount, with its device and filesystem
        Repeater {
            model: MonitorService.disks.length
            delegate: RowLayout {
                id: disk
                required property int index
                readonly property var d: MonitorService.disks[index] ?? { mount: "", dev: "", fs: "", used: 0, total: 1 }
                Layout.fillWidth: true
                spacing: 12
                StyledText { Layout.preferredWidth: 150; text: disk.d.mount; color: ClockStyle.colOnBackground; elide: Text.ElideMiddle; font.pixelSize: ClockStyle.textSmall }
                StyledText { Layout.preferredWidth: 150; text: `${disk.d.dev} · ${disk.d.fs}`; color: ClockStyle.colSubtext; elide: Text.ElideMiddle; font.pixelSize: ClockStyle.textSmall }
                MeterBar { Layout.fillWidth: true; implicitHeight: 8; percent: 100 * disk.d.used / Math.max(1, disk.d.total); barColor: ClockStyle.colTertiary }
                StyledText { Layout.preferredWidth: 170; horizontalAlignment: Text.AlignRight; text: `${Fmt.bytes(disk.d.used)} of ${Fmt.bytes(disk.d.total)}`; color: ClockStyle.colOnBackground; font.pixelSize: ClockStyle.textSmall }
            }
        }
    }
}

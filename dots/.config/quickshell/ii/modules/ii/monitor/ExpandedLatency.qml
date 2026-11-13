pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/// Internet latency expanded: the big graph and every target's numbers.
Item {
    id: root
    readonly property var seriesColors: [ClockStyle.colPrimary, ClockStyle.colTertiary, Appearance.colors.colSecondary, ClockStyle.colError, ClockStyle.colSubtext, ClockStyle.colOnBackground]
    readonly property var series: {
        MonitorService.pingHistory;
        return MonitorService.ping.map((p, i) => ({ name: p.name, color: root.seriesColors[i % root.seriesColors.length], values: MonitorService.pingHistory[p.name] ?? [] }));
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 14

        LatencyGraph {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1
            Layout.minimumHeight: 160
            series: root.series
        }

        Repeater {
            model: MonitorService.ping.length
            delegate: Rectangle {
                id: target
                required property int index
                readonly property var p: MonitorService.ping[index]
                readonly property var s: { MonitorService.pingHistory; return MonitorService.pingStats(target.p.name); }
                Layout.fillWidth: true
                implicitHeight: 40
                radius: ClockStyle.radiusNormal
                color: ClockStyle.colSurfaceHighest
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 14
                    Rectangle { Layout.preferredWidth: 10; Layout.preferredHeight: 10; radius: 5; color: root.seriesColors[target.index % root.seriesColors.length] }
                    StyledText { Layout.fillWidth: true; text: target.p.name; color: ClockStyle.colOnBackground; font.weight: Font.Medium; elide: Text.ElideRight }
                    StyledText { text: `${Translation.tr("now")} ${Fmt.ms(target.s.current)}`; color: ClockStyle.colOnBackground; font.pixelSize: ClockStyle.textSmall }
                    StyledText { text: `${Translation.tr("avg")} ${Fmt.ms(target.s.avg)}`; color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                    StyledText { text: `${Fmt.ms(target.s.min)} - ${Fmt.ms(target.s.max)}`; color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                    StyledText { text: `${Translation.tr("jitter")} ${Fmt.ms(target.s.jitter)}`; color: ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                    StyledText { text: `${Translation.tr("lost")} ${Math.round(target.s.loss)}%`; color: target.s.loss >= 5 ? ClockStyle.colError : ClockStyle.colSubtext; font.pixelSize: ClockStyle.textSmall }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/** Internet latency to each target, with jitter and loss over the last two minutes, and per-interface traffic. */
Flickable {
    WheelScroll {}
    id: root

    property bool compact: false

    // One verdict from the worst of the targets
    readonly property var verdict: {
        const stats = MonitorService.ping.map(p => MonitorService.pingStats(p.name)).filter(s => s.samples >= 3);
        if (stats.length === 0)
            return { text: Translation.tr("Measuring…"), level: 0 };
        const reachable = stats.filter(s => s.loss < 100);
        if (reachable.length === 0)
            return { text: Translation.tr("No answer from any target. The connection may be down."), level: 2 };
        const worstLoss = Math.max(...reachable.map(s => s.loss));
        const worstJitter = Math.max(...reachable.map(s => s.jitter));
        const best = Math.min(...reachable.map(s => s.avg));
        if (worstLoss >= 5 || worstJitter > 80)
            return { text: Translation.tr("Unstable: packets are being lost or the delay jumps around."), level: 2 };
        if (best > 150)
            return { text: Translation.tr("Slow: even the nearest reachable target takes %1.").arg(Fmt.ms(best)), level: 1 };
        if (worstLoss > 0 || worstJitter > 30)
            return { text: Translation.tr("Mostly fine, with some jitter."), level: 1 };
        return { text: Translation.tr("The connection looks healthy."), level: 0 };
    }

    contentWidth: width
    contentHeight: column.implicitHeight + 8
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    ColumnLayout {
        id: column
        width: root.width
        spacing: ClockStyle.paneGap

        Rectangle {
            Layout.fillWidth: true
            radius: ClockStyle.radiusLarge
            color: root.verdict.level === 0 ? ClockStyle.colPrimaryContainer
                : root.verdict.level === 1 ? ClockStyle.colTertiaryContainer : ClockStyle.colErrorContainer
            implicitHeight: verdictRow.implicitHeight + 24

            RowLayout {
                id: verdictRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12
                MaterialSymbol {
                    text: root.verdict.level === 0 ? "check_circle" : root.verdict.level === 1 ? "warning" : "error"
                    iconSize: 26
                    color: root.verdict.level === 0 ? ClockStyle.colOnPrimaryContainer
                        : root.verdict.level === 1 ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnErrorContainer
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.verdict.text
                    color: root.verdict.level === 0 ? ClockStyle.colOnPrimaryContainer
                        : root.verdict.level === 1 ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnErrorContainer
                    font.pixelSize: ClockStyle.textLarge
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: root.compact ? 1 : Math.min(3, Math.max(1, MonitorService.ping.length))
            columnSpacing: ClockStyle.paneGap
            rowSpacing: ClockStyle.paneGap

            Repeater {
                model: MonitorService.ping
                delegate: Panel {
                    id: card
                    required property var modelData
                    readonly property var st: { MonitorService.pingHistory; return MonitorService.pingStats(modelData.name); }
                    readonly property int q: Fmt.quality(modelData.ms)
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    title: `${modelData.name} · ${modelData.host}`
                    symbol: "network_ping"

                    StyledText {
                        text: card.q < 0 ? Translation.tr("lost") : Fmt.ms(card.modelData.ms)
                        color: card.q < 0 ? ClockStyle.colError : card.q === 0 ? ClockStyle.colPrimary
                            : card.q === 1 ? ClockStyle.colTertiary : ClockStyle.colError
                        font.pixelSize: 34
                        font.weight: Font.DemiBold
                    }
                    MonitorGraph {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 90
                        values: MonitorService.pingHistory[card.modelData.name] ?? []
                        floorMax: 50
                        lineColor: card.q <= 0 ? ClockStyle.colPrimary : card.q === 1 ? ClockStyle.colTertiary : ClockStyle.colError
                    }
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 5
                        columnSpacing: 12
                        Repeater {
                            model: [
                                { k: Translation.tr("Avg"), v: Fmt.ms(card.st.avg) },
                                { k: Translation.tr("Best"), v: Fmt.ms(card.st.min) },
                                { k: Translation.tr("Worst"), v: Fmt.ms(card.st.max) },
                                { k: Translation.tr("Jitter"), v: Fmt.ms(card.st.jitter) },
                                { k: Translation.tr("Loss"), v: Fmt.percent(card.st.loss) }
                            ]
                            delegate: ColumnLayout {
                                id: stat
                                required property var modelData
                                spacing: 0
                                StyledText {
                                    text: stat.modelData.v
                                    color: ClockStyle.colOnBackground
                                    font.pixelSize: ClockStyle.textSmall
                                    font.weight: Font.Medium
                                }
                                StyledText {
                                    text: stat.modelData.k
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textSmall - 1
                                }
                            }
                        }
                    }
                }
            }
        }

        Panel {
            Layout.fillWidth: true
            title: Translation.tr("Interfaces")
            symbol: "lan"

            Repeater {
                model: MonitorService.net
                delegate: RowLayout {
                    id: nic
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    Rectangle {
                        implicitWidth: 10
                        implicitHeight: 10
                        radius: 5
                        color: nic.modelData.up === "up" || nic.modelData.up === "unknown" ? ClockStyle.colPrimary : ClockStyle.colSubtext
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: nic.modelData.name
                        color: ClockStyle.colOnBackground
                    }
                    StyledText {
                        text: `↓ ${Fmt.rate(nic.modelData.rx)}   ↑ ${Fmt.rate(nic.modelData.tx)}`
                        color: ClockStyle.colOnBackground
                    }
                    StyledText {
                        Layout.preferredWidth: 220
                        horizontalAlignment: Text.AlignRight
                        text: Translation.tr("Total ↓ %1  ↑ %2").arg(Fmt.bytes(nic.modelData.rx_total)).arg(Fmt.bytes(nic.modelData.tx_total))
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }
        }
    }
}

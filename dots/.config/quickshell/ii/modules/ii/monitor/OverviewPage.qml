pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/**
 * The system overview, five cards and nothing said twice:
 *
 *   processor + cores  |  internet latency
 *   network over memory and storage  |  busiest processes (three columns)
 *
 * Two rows that share the height. Four columns when there is room, two or one when there is not.
 * Every list is a fixed-size model whose rows read their values by position, so the one-second
 * updates change text and bars in place instead of rebuilding anything.
 */
Flickable {
    WheelScroll {}
    id: root

    property bool compact: false
    /// The full-screen overlay has room to breathe and fills its height
    property bool spacious: false

    readonly property int cols: root.width >= 1240 ? 4 : root.width >= 720 ? 2 : 1
    readonly property real gap: root.spacious ? 20 : 14
    readonly property real pad: root.spacious ? 20 : 14
    // The top row is the shorter one: the bottom row holds the stacked cards and the process list
    readonly property real topHeight: root.spacious ? Math.max(330, (root.height - root.gap) * 0.42) : 360
    readonly property real bottomHeight: root.spacious ? Math.max(480, root.height - root.gap - root.topHeight) : 520
    readonly property var m: MonitorService.mem

    readonly property var seriesColors: [ClockStyle.colPrimary, ClockStyle.colTertiary, Appearance.colors.colSecondary, ClockStyle.colError, ClockStyle.colSubtext, ClockStyle.colOnBackground]
    readonly property var latencySeries: {
        MonitorService.pingHistory;
        return MonitorService.ping.map((p, i) => ({
            name: p.name,
            color: root.seriesColors[i % root.seriesColors.length],
            values: MonitorService.pingHistory[p.name] ?? []
        }));
    }

    // One verdict from the worst of the targets (the same reading the Network tab gives)
    readonly property var verdict: {
        MonitorService.pingHistory;
        const stats = MonitorService.ping.map(p => MonitorService.pingStats(p.name)).filter(s => s.samples >= 5);
        if (stats.length === 0)
            return { text: Translation.tr("Measuring…"), level: 0 };
        const reachable = stats.filter(s => s.loss < 100);
        if (reachable.length === 0)
            return { text: Translation.tr("No answer from any target. The connection may be down."), level: 2 };
        const worstLoss = Math.max(...reachable.map(s => s.loss));
        const worstJitter = Math.max(...reachable.map(s => s.jitter));
        const best = Math.min(...reachable.map(s => s.avg));
        if (worstLoss >= 5 || worstJitter > 80)
            return { text: worstLoss >= 5
                ? Translation.tr("Unstable: %1% of packets are being lost").arg(Math.round(worstLoss))
                : Translation.tr("Unstable: the delay jumps around by up to %1 ms").arg(Math.round(worstJitter)), level: 2 };
        if (best > 150)
            return { text: Translation.tr("Slow: even the nearest target takes %1").arg(Fmt.ms(best)), level: 1 };
        if (worstLoss > 0 || worstJitter > 30)
            return { text: Translation.tr("Mostly fine, with some jitter"), level: 1 };
        return { text: Translation.tr("The connection looks healthy"), level: 0 };
    }

    readonly property real peakRx: MonitorService.rxHistory.reduce((a, b) => Math.max(a, b), 0)
    readonly property real peakTx: MonitorService.txHistory.reduce((a, b) => Math.max(a, b), 0)

    // The one other interface that moved data in the last second, a VPN tunnel say (container bridges are left out)
    readonly property var otherNics: MonitorService.net.filter(n => n !== MonitorService.mainNet && n.rx + n.tx > 0 && !/^(lo|docker|br-|veth)/.test(n.name)).slice(0, 1)

    // Mean clock across the cores, in GHz; 0 when the kernel does not report it
    readonly property real avgGhz: MonitorService.freq.length > 0 ? MonitorService.freq.reduce((a, b) => a + b, 0) / MonitorService.freq.length / 1000 : 0

    function qualityColor(ms: real): color {
        const q = Fmt.quality(ms);
        return q < 0 || q === 2 ? ClockStyle.colError : q === 1 ? ClockStyle.colTertiary : ClockStyle.colPrimary;
    }

    // A card the user expanded fills the page and the others step aside
    readonly property string expandedId: MonitorService.expandedCard
    readonly property real expandedHeight: Math.max(360, root.height - (root.spacious ? 0 : 8))
    function shows(id: string): bool {
        return root.expandedId === "" || root.expandedId === id;
    }
    function isExpanded(id: string): bool {
        return root.expandedId === id;
    }
    function toggleCard(id: string): void {
        MonitorService.expandedCard = root.expandedId === id ? "" : id;
    }
    Component.onDestruction: MonitorService.expandedCard = ""
    onColsChanged: contentY = 0

    function span(n: int): int {
        return Math.min(n, root.cols);
    }

    signal openTab(string tabId)

    contentWidth: width
    contentHeight: grid.implicitHeight + (root.spacious ? 0 : 8)
    clip: true
    boundsBehavior: Flickable.StopAtBounds

    GridLayout {
        id: grid
        width: root.width
        columns: root.cols
        columnSpacing: root.gap
        rowSpacing: root.gap

        // The overlay shows the battery in its header; the window shows it here
        BatteryChip {
            visible: !root.spacious && MonitorService.battery !== null
            Layout.columnSpan: root.cols
            Layout.alignment: Qt.AlignLeft
        }

        // ── processor and its cores ──
        MonitorCard {
            Layout.fillWidth: true
            visible: root.shows("cpu")
            expandable: true
            expanded: root.isExpanded("cpu")
            onExpandToggled: root.toggleCard("cpu")
            expandedContent: Component { ExpandedCpu {} }
            Layout.columnSpan: root.isExpanded("cpu") ? root.cols : root.span(2)
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.isExpanded("cpu") ? root.expandedHeight : root.topHeight
            padding: root.pad
            symbol: "memory"
            title: MonitorService.cpuModel !== "" ? MonitorService.cpuModel : Translation.tr("Processor")
            value: [MonitorService.freqMax > 0 ? Translation.tr("max %1 GHz").arg((MonitorService.freqMax / 1000).toFixed(1)) : "", MonitorService.temps.cpu > 0 ? `${Math.round(MonitorService.temps.cpu)} °C` : ""].filter(t => t !== "").join("   ")

            RowLayout {
                anchors.fill: parent
                spacing: 24

                // The total on a gauge, with the load under it
                ColumnLayout {
                    Layout.fillHeight: true
                    Layout.fillWidth: false
                    Layout.preferredWidth: 220
                    Layout.maximumWidth: 220
                    spacing: 10

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        RingGauge {
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height)
                            height: width
                            value: MonitorService.cpu
                            text: Fmt.percent(MonitorService.cpu)
                            caption: root.avgGhz > 0 ? `${root.avgGhz.toFixed(2)} GHz` : Translation.tr("%1 cores").arg(MonitorService.coreCount)
                            color: MonitorService.cpu >= 90 ? ClockStyle.colError : ClockStyle.colPrimary
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("Load %1  %2  %3").arg(MonitorService.load[0]).arg(MonitorService.load[1]).arg(MonitorService.load[2])
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: Translation.tr("%1 tasks · %2 threads").arg(MonitorService.tasks).arg(MonitorService.threads)
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    spacing: 14

                    MonitorGraph {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 80
                        values: MonitorService.cpuHistory
                        maxValue: 100
                    }

                    // Every core as a tile that warms up with its load
                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.ceil(MonitorService.cores.length / 2))
                        columnSpacing: 8
                        rowSpacing: 8

                        Repeater {
                            model: MonitorService.cores.length
                            delegate: Rectangle {
                                id: core
                                required property int index
                                readonly property real pct: MonitorService.cores[index] ?? 0
                                readonly property real ghz: (MonitorService.freq[index] ?? 0) / 1000
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                implicitHeight: 46
                                radius: ClockStyle.radiusNormal
                                color: core.pct >= 90 ? Qt.rgba(ClockStyle.colError.r, ClockStyle.colError.g, ClockStyle.colError.b, 0.85)
                                    : Qt.rgba(ClockStyle.colPrimary.r, ClockStyle.colPrimary.g, ClockStyle.colPrimary.b, 0.1 + 0.75 * Math.min(1, core.pct / 100))
                                Behavior on color {
                                    enabled: !ClockStyle.reducedMotion
                                    ColorAnimation { duration: 500 }
                                }

                                readonly property bool light: core.pct >= 55
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 0
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: Math.round(core.pct) + "%"
                                        color: core.light ? ClockStyle.colOnPrimary : ClockStyle.colOnBackground
                                        font.weight: Font.Medium
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: core.ghz > 0 ? `${core.index} · ${core.ghz.toFixed(1)} GHz` : core.index
                                        color: core.light ? ClockStyle.colOnPrimary : ClockStyle.colSubtext
                                        font.pixelSize: ClockStyle.textSmall - 1
                                        opacity: 0.8
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        text: Translation.tr("up %1").arg(Fmt.duration(MonitorService.uptime))
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }
        }

        // ── internet latency ──
        MonitorCard {
            Layout.fillWidth: true
            visible: root.shows("latency")
            expandable: true
            expanded: root.isExpanded("latency")
            onExpandToggled: root.toggleCard("latency")
            expandedContent: Component { ExpandedLatency {} }
            Layout.columnSpan: root.isExpanded("latency") ? root.cols : root.span(2)
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.isExpanded("latency") ? root.expandedHeight : root.topHeight
            padding: root.pad
            symbol: "network_ping"
            title: Translation.tr("Internet latency")
            value: Translation.tr("last %1 s").arg(MonitorService.historyLength)

            ColumnLayout {
                anchors.fill: parent
                spacing: 12

                Rectangle {
                    Layout.fillWidth: true
                    radius: ClockStyle.radiusNormal
                    implicitHeight: verdictRow.implicitHeight + 8
                    color: root.verdict.level === 0 ? ClockStyle.colPrimaryContainer
                        : root.verdict.level === 1 ? ClockStyle.colTertiaryContainer : ClockStyle.colErrorContainer
                    RowLayout {
                        id: verdictRow
                        anchors.fill: parent
                        anchors.margins: 4
                        anchors.leftMargin: 12
                        spacing: 10
                        MaterialSymbol {
                            text: root.verdict.level === 0 ? "check_circle" : root.verdict.level === 1 ? "warning" : "error"
                            iconSize: 20
                            color: root.verdict.level === 0 ? ClockStyle.colOnPrimaryContainer
                                : root.verdict.level === 1 ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnErrorContainer
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.verdict.text
                            elide: Text.ElideRight
                            color: root.verdict.level === 0 ? ClockStyle.colOnPrimaryContainer
                                : root.verdict.level === 1 ? ClockStyle.colOnTertiaryContainer : ClockStyle.colOnErrorContainer
                        }
                    }
                }

                LatencyGraph {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 100
                    series: root.latencySeries
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    Repeater {
                        model: MonitorService.ping.length
                        delegate: Rectangle {
                            id: target
                            required property int index
                            readonly property var p: MonitorService.ping[index] ?? { name: "", host: "", ms: null }
                            readonly property var st: { MonitorService.pingHistory; return MonitorService.pingStats(p.name); }
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: targetColumn.implicitHeight + 24
                            radius: ClockStyle.radiusNormal
                            color: ClockStyle.colSurfaceHigh

                            ColumnLayout {
                                id: targetColumn
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 2

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Rectangle {
                                        implicitWidth: 10
                                        implicitHeight: 10
                                        radius: 5
                                        color: root.seriesColors[target.index % root.seriesColors.length]
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: target.p.name
                                        color: ClockStyle.colOnBackground
                                        font.weight: Font.Medium
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        text: Fmt.quality(target.p.ms) < 0 ? Translation.tr("lost") : Fmt.ms(target.p.ms)
                                        color: root.qualityColor(target.p.ms ?? -1)
                                        font.pixelSize: ClockStyle.textLarge
                                        font.weight: Font.DemiBold
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: Translation.tr("avg %1 · ±%2 · %3").arg(Math.round(target.st.avg)).arg(Math.round(target.st.jitter)).arg(Fmt.percent(target.st.loss))
                                    color: target.st.loss > 5 ? ClockStyle.colError : ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textSmall
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }
            }
        }

        // ── network over memory and storage ──
        ColumnLayout {
            visible: root.shows("net") || root.shows("mem")
            Layout.fillWidth: true
            Layout.columnSpan: root.expandedId === "net" || root.expandedId === "mem" ? root.cols : 1
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.expandedId === "net" || root.expandedId === "mem" ? root.expandedHeight : root.bottomHeight
            spacing: root.gap

            MonitorCard {
                visible: root.shows("net")
                expandable: true
                expanded: root.isExpanded("net")
                onExpandToggled: root.toggleCard("net")
                expandedContent: Component { ExpandedNetwork {} }
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: 1
                Layout.minimumHeight: 200
                padding: root.pad
                symbol: "swap_vert"
                title: Translation.tr("Network")
                value: MonitorService.mainNet ? MonitorService.mainNet.ip ?? "" : ""

                // btop's b and n: step through the interfaces; Auto follows the busiest
                headerExtras: [
                    Item { Layout.fillWidth: true },
                    RowLayout {
                        spacing: 0

                        ClockIconButton {
                            size: 28
                            iconSize: 18
                            symbol: "chevron_left"
                            focusPolicy: Qt.NoFocus
                            visible: MonitorService.nicChoices.length > 1
                            tooltip: Translation.tr("Previous interface")
                            onClicked: MonitorService.cycleNic(-1)
                        }
                        StyledText {
                            text: MonitorService.selectedNic === "" ? Translation.tr("Auto · %1").arg(MonitorService.mainNet?.name ?? "") : MonitorService.mainNet?.name ?? MonitorService.selectedNic
                            color: ClockStyle.colOnBackground
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Medium
                            horizontalAlignment: Text.AlignHCenter
                            Layout.minimumWidth: 70
                        }
                        ClockIconButton {
                            size: 28
                            iconSize: 18
                            symbol: "chevron_right"
                            focusPolicy: Qt.NoFocus
                            visible: MonitorService.nicChoices.length > 1
                            tooltip: Translation.tr("Next interface")
                            onClicked: MonitorService.cycleNic(1)
                        }
                    }
                ]

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 10

                    // Download and upload now, side by side, each with its own peak and total
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 14

                        Repeater {
                            model: [
                                { down: true, color: ClockStyle.colPrimary },
                                { down: false, color: ClockStyle.colTertiary }
                            ]
                            delegate: ColumnLayout {
                                id: nrow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                spacing: 0
                                RowLayout {
                                    spacing: 6
                                    MaterialSymbol {
                                        text: nrow.modelData.down ? "arrow_downward" : "arrow_upward"
                                        iconSize: 18
                                        color: nrow.modelData.color
                                    }
                                    StyledText {
                                        text: Fmt.rate(nrow.modelData.down ? MonitorService.rx : MonitorService.tx)
                                        color: ClockStyle.colOnBackground
                                        font.pixelSize: ClockStyle.textLarge + 2
                                        font.weight: Font.DemiBold
                                    }
                                }
                                StyledText {
                                    text: Translation.tr("peak %1 · %2 total").arg(Fmt.rate(nrow.modelData.down ? root.peakRx : root.peakTx))
                                        .arg(Fmt.bytes(nrow.modelData.down ? (MonitorService.mainNet?.rx_total ?? 0) : (MonitorService.mainNet?.tx_total ?? 0)))
                                    color: ClockStyle.colSubtext
                                    font.pixelSize: ClockStyle.textSmall - 1
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }

                    // Download above the line, upload below it, one scale
                    NetworkGraph {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 90
                        down: MonitorService.rxHistory
                        up: MonitorService.txHistory
                    }

                    // Everything else that is moving data, the VPN tunnel for one
                    Repeater {
                        model: 1
                        delegate: RowLayout {
                            id: other
                            required property int index
                            readonly property var nic: root.otherNics[index] ?? null
                            visible: nic !== null
                            Layout.fillWidth: true
                            spacing: 8
                            Rectangle {
                                implicitWidth: 8
                                implicitHeight: 8
                                radius: 4
                                color: ClockStyle.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: other.nic ? [other.nic.name, other.nic.ip].filter(t => t).join("  ·  ") : ""
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                                elide: Text.ElideRight
                            }
                            StyledText {
                                text: other.nic ? `↓ ${Fmt.rate(other.nic.rx)}   ↑ ${Fmt.rate(other.nic.tx)}` : ""
                                color: ClockStyle.colOnBackground
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }
                }
            }

            MonitorCard {
                visible: root.shows("mem")
                expandable: true
                expanded: root.isExpanded("mem")
                onExpandToggled: root.toggleCard("mem")
                expandedContent: Component { ExpandedMemory {} }
                Layout.fillWidth: true
                Layout.fillHeight: root.isExpanded("mem")
                Layout.preferredHeight: root.isExpanded("mem") ? 1 : 192
                padding: root.pad
                symbol: "developer_board"
                title: Translation.tr("Memory and storage")
                accent: ClockStyle.colTertiary
                value: Translation.tr("%1 of %2").arg(Fmt.bytes(root.m.used)).arg(Fmt.bytes(root.m.total))

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 6

                    // Each line: name, meter, amount
                    Repeater {
                        model: ["used", "swap"]
                        delegate: RowLayout {
                            id: memRow
                            required property string modelData
                            readonly property bool swap: modelData === "swap"
                            readonly property real total: swap ? root.m.swap_total : root.m.total
                            readonly property real amount: modelData === "used" ? root.m.used
                                : modelData === "cached" ? root.m.cached : root.m.swap_used
                            visible: !swap || total > 0
                            Layout.fillWidth: true
                            spacing: 10
                            StyledText {
                                Layout.preferredWidth: 56
                                text: memRow.modelData === "used" ? Translation.tr("Used")
                                    : memRow.modelData === "cached" ? Translation.tr("Cached") : Translation.tr("Swap")
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                            MeterBar {
                                Layout.fillWidth: true
                                implicitHeight: 8
                                percent: 100 * memRow.amount / Math.max(1, memRow.total)
                                barColor: ClockStyle.colTertiary
                                warn: memRow.modelData === "used" || memRow.swap
                            }
                            StyledText {
                                Layout.preferredWidth: 96
                                horizontalAlignment: Text.AlignRight
                                text: `${Fmt.bytes(memRow.amount)} · ${Math.round(100 * memRow.amount / Math.max(1, memRow.total))}%`
                                color: ClockStyle.colOnBackground
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: ClockStyle.colSurfaceHighest
                    }

                    Repeater {
                        model: MonitorService.disks.length
                        delegate: RowLayout {
                            id: disk
                            required property int index
                            readonly property var d: MonitorService.disks[index] ?? { mount: "", used: 0, total: 1 }
                            Layout.fillWidth: true
                            spacing: 10
                            StyledText {
                                Layout.preferredWidth: 56
                                text: disk.d.mount
                                color: ClockStyle.colOnBackground
                                font.pixelSize: ClockStyle.textSmall
                                elide: Text.ElideMiddle
                            }
                            MeterBar {
                                Layout.fillWidth: true
                                implicitHeight: 8
                                percent: 100 * disk.d.used / Math.max(1, disk.d.total)
                            }
                            StyledText {
                                Layout.preferredWidth: 96
                                horizontalAlignment: Text.AlignRight
                                text: `${Fmt.bytes(disk.d.used)} / ${Fmt.bytes(disk.d.total)}`
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // ── processes ──
        MonitorCard {
            id: procCard
            Layout.fillWidth: true
            visible: root.shows("procs")
            expandable: true
            expanded: root.isExpanded("procs")
            onExpandToggled: root.toggleCard("procs")
            Layout.columnSpan: root.isExpanded("procs") ? root.cols : root.span(3)
            Layout.preferredWidth: 1
            Layout.preferredHeight: root.isExpanded("procs") ? root.expandedHeight : root.bottomHeight
            padding: root.pad
            symbol: "list"
            title: Translation.tr("Processes")
            value: Translation.tr("%1 tasks · %2 threads").arg(MonitorService.tasks).arg(MonitorService.threads)

            headerExtras: ProcessTools {
                id: procTools
            }

            ProcessTable {
                anchors.fill: parent
                ofTotal: procTools.ofTotal
                filterText: procTools.filterText
            }
        }
    }
}

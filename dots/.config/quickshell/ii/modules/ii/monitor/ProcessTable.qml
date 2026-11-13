pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/**
 * Every process: sort by any column, filter, pick one to see what it is, how its processor and
 * memory use have moved and to end it. The rows are a count and read their process by position,
 * so the once-a-second refresh changes text in place instead of rebuilding the list.
 */
Item {
    id: root

    property string sortKey: "cpu"
    property bool descending: true
    /// Show processor use as a share of the whole processor (true) or of one core, as top does
    property bool ofTotal: true
    /// What the search in the card's header has typed; a search that is closed does not filter
    property string filterText: ""

    readonly property real divisor: root.ofTotal ? Math.max(1, MonitorService.coreCount) : 1
    readonly property bool picked: MonitorService.selectedPid > 0
    readonly property var selected: MonitorService.procs.find(p => p[0] === MonitorService.selectedPid) ?? null
    readonly property var parentProc: root.selected ? (MonitorService.procs.find(p => p[0] === root.selected[8]) ?? null) : null
    readonly property bool wide: root.width >= 760

    // The sampler sends the whole table only while a page that lists it exists
    Component.onCompleted: MonitorService.fullProcsHolders++
    Component.onDestruction: {
        MonitorService.fullProcsHolders = Math.max(0, MonitorService.fullProcsHolders - 1);
        MonitorService.selectedPid = -1;
        MonitorService.procSearchOpen = false;
    }

    // The list's order for the arrow keys, and the selected row kept in view
    Binding {
        target: MonitorService
        property: "shownPids"
        value: root.rows.map(p => p[0])
    }
    Connections {
        target: MonitorService
        function onSelectedPidChanged() {
            const i = root.rows.findIndex(p => p[0] === MonitorService.selectedPid);
            if (i >= 0)
                list.positionViewAtIndex(i, ListView.Contain);
        }
    }

    // Column order of a process row from the sampler
    readonly property var columns: [
        { key: "pid", label: "PID", index: 0, width: 58, align: Text.AlignRight, detail: true },
        { key: "name", label: Translation.tr("Program"), index: 1, width: -2, align: Text.AlignLeft, detail: true },
        { key: "cmd", label: Translation.tr("Command"), index: 7, width: -3, align: Text.AlignLeft, detail: false },
        { key: "user", label: Translation.tr("User"), index: 2, width: 64, align: Text.AlignLeft, detail: false },
        { key: "threads", label: Translation.tr("Thr"), index: 6, width: 34, align: Text.AlignRight, detail: false },
        { key: "mem", label: Translation.tr("Memory"), index: 4, width: 72, align: Text.AlignRight, detail: true },
        { key: "cpu", label: Translation.tr("CPU"), index: 3, width: 150, align: Text.AlignRight, detail: true }
    ]
    // The command goes to the details pane when one is open, to leave the list its room
    readonly property var shownColumns: root.columns.filter(c => !root.picked || c.detail)

    readonly property var rows: {
        const q = root.filterText.trim().toLowerCase();
        const col = root.columns.find(c => c.key === root.sortKey);
        const i = col ? col.index : 3;
        const dir = root.descending ? -1 : 1;
        let list = MonitorService.procs;
        if (q !== "")
            list = list.filter(p => p[1].toLowerCase().includes(q) || String(p[7]).toLowerCase().includes(q) || String(p[0]) === q);
        else
            list = list.slice();
        list.sort((a, b) => {
            const x = a[i], y = b[i];
            return (typeof x === "string" ? x.localeCompare(y) : x - y) * dir || a[0] - b[0];
        });
        return list.slice(0, 400);
    }
    // Never below one core's worth, so a quiet system does not stretch tiny loads to full bars
    readonly property real cpuMax: Math.max(100, root.rows.reduce((a, p) => Math.max(a, p[3]), 0))

    function sortBy(key: string): void {
        if (root.sortKey === key) {
            root.descending = !root.descending;
        } else {
            root.sortKey = key;
            root.descending = !["pid", "name", "cmd", "user"].includes(key);
        }
    }

    function stateText(code: string): string {
        return ({ R: Translation.tr("Running"), S: Translation.tr("Sleeping"), D: Translation.tr("Waiting on disk"),
                  T: Translation.tr("Frozen"), Z: Translation.tr("Zombie"), I: Translation.tr("Idle") })[code] ?? code;
    }

    RowLayout {
        anchors.fill: parent
        spacing: 16

        // ── the list ──
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            Layout.minimumWidth: 0
            spacing: 6

            // Header: click a column to sort by it
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                spacing: 10
                Repeater {
                    model: root.shownColumns
                    delegate: Item {
                        id: head
                        required property var modelData
                        Layout.fillWidth: modelData.width < 0
                        Layout.preferredWidth: modelData.width < 0 ? -modelData.width : modelData.width
                        implicitHeight: 24
                        StyledText {
                            anchors.fill: parent
                            verticalAlignment: Text.AlignVCenter
                            horizontalAlignment: head.modelData.align
                            text: head.modelData.label + (root.sortKey === head.modelData.key ? (root.descending ? " ▾" : " ▴") : "")
                            color: root.sortKey === head.modelData.key ? ClockStyle.colPrimary : ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.sortBy(head.modelData.key)
                        }
                    }
                }
            }

            ListView {
                WheelScroll {}
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.rows.length

                delegate: Rectangle {
                    id: row
                    required property int index
                    readonly property var p: root.rows[index] ?? null
                    readonly property bool isSelected: p !== null && p[0] === MonitorService.selectedPid
                    width: ListView.view.width
                    height: 30
                    radius: ClockStyle.radiusSmall
                    color: row.isSelected ? ClockStyle.colSecondaryContainer : area.containsMouse ? ClockStyle.colSurfaceHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 10

                        Repeater {
                            model: root.shownColumns
                            delegate: Item {
                                id: cell
                                required property var modelData
                                readonly property var raw: row.p ? row.p[modelData.index] : undefined
                                Layout.fillWidth: modelData.width < 0
                                Layout.preferredWidth: modelData.width < 0 ? -modelData.width : modelData.width
                                Layout.fillHeight: true

                                StyledText {
                                    anchors.fill: parent
                                    visible: cell.modelData.key !== "cpu"
                                    verticalAlignment: Text.AlignVCenter
                                    horizontalAlignment: cell.modelData.align
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    wrapMode: Text.NoWrap
                                    text: cell.raw === undefined ? ""
                                        : cell.modelData.key === "mem" ? Fmt.bytes(cell.raw)
                                        : cell.modelData.key === "cmd" ? String(cell.raw).replace(/\s+/g, " ")
                                        : String(cell.raw)
                                    color: cell.modelData.key === "name" ? ClockStyle.colOnBackground
                                        : cell.modelData.key === "mem" ? ClockStyle.colOnBackground
                                        : ClockStyle.colSubtext
                                    font.pixelSize: cell.modelData.key === "name" || cell.modelData.key === "mem" ? ClockStyle.textNormal : ClockStyle.textSmall
                                    font.italic: cell.modelData.key === "name" && row.p !== null && row.p[5] === "T"
                                }

                                // The processor column is a bar and a number
                                RowLayout {
                                    anchors.fill: parent
                                    visible: cell.modelData.key === "cpu"
                                    spacing: 8
                                    MeterBar {
                                        Layout.fillWidth: true
                                        implicitHeight: 6
                                        percent: row.p ? 100 * row.p[3] / root.cpuMax : 0
                                        warn: false
                                        // Rows are read by position: a bar that slid between two processes would lag the sample
                                        animated: false
                                    }
                                    StyledText {
                                        Layout.preferredWidth: 46
                                        horizontalAlignment: Text.AlignRight
                                        text: row.p ? (row.p[3] / root.divisor).toFixed(1) + "%" : ""
                                        color: row.p && row.p[3] / root.divisor >= 50 ? ClockStyle.colError : ClockStyle.colOnBackground
                                        font.weight: Font.Medium
                                    }
                                }
                            }
                        }
                    }
                    MouseArea {
                        id: area
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: MonitorService.selectedPid = row.isSelected ? -1 : row.p[0]
                    }
                }
            }
        }

        // ── the picked process ──
        Rectangle {
            visible: root.picked
            Layout.fillHeight: true
            Layout.preferredWidth: root.wide ? 340 : Math.max(240, root.width * 0.45)
            Layout.maximumWidth: root.width * 0.55
            radius: ClockStyle.radiusNormal
            color: ClockStyle.colSurfaceHigh

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: root.selected ? root.selected[1] : Translation.tr("Process ended")
                            color: ClockStyle.colOnBackground
                            font.pixelSize: ClockStyle.textLarge
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: root.selected
                                ? `PID ${root.selected[0]}  ·  ${root.selected[2]}  ·  ${root.stateText(root.selected[5])}`
                                : `PID ${MonitorService.selectedPid}`
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            elide: Text.ElideRight
                        }
                    }
                    ClockButton {
                        variant: "text"
                        iconOnly: true
                        label: Translation.tr("Close details")
                        symbol: "close"
                        onClicked: MonitorService.selectedPid = -1
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.selected !== null
                    text: root.selected ? String(root.selected[7]).replace(/\s+/g, " ") : ""
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    wrapMode: Text.WrapAnywhere
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.selected !== null
                    text: Translation.tr("%1 threads%2").arg(root.selected ? root.selected[6] : 0)
                        .arg(root.parentProc ? Translation.tr("  ·  started by %1 (%2)").arg(root.parentProc[1]).arg(root.parentProc[0]) : "")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }

                // Processor
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Processor")
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                        }
                        StyledText {
                            text: root.selected ? (root.selected[3] / root.divisor).toFixed(1) + "%" : "–"
                            color: ClockStyle.colPrimary
                            font.weight: Font.Medium
                        }
                    }
                    MonitorGraph {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        values: MonitorService.selectedCpuHistory.map(v => v < 0 ? v : v / root.divisor)
                        floorMax: root.ofTotal ? 2 : 10
                    }
                }

                // Memory
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 60
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: Translation.tr("Memory")
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                        }
                        StyledText {
                            text: root.selected ? Fmt.bytes(root.selected[4]) : "–"
                            color: ClockStyle.colTertiary
                            font.weight: Font.Medium
                        }
                    }
                    MonitorGraph {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        values: MonitorService.selectedMemHistory
                        floorMax: 1024 * 1024
                        lineColor: ClockStyle.colTertiary
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: MonitorService.error !== ""
                    text: MonitorService.error
                    color: ClockStyle.colError
                    font.pixelSize: ClockStyle.textSmall
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    visible: root.selected !== null
                    ClockButton {
                        variant: "text"
                        iconOnly: true
                        symbol: root.selected && root.selected[5] === "T" ? "play_arrow" : "pause"
                        label: root.selected && root.selected[5] === "T" ? Translation.tr("Continue") : Translation.tr("Freeze")
                        onClicked: MonitorService.signalProcess(MonitorService.selectedPid, root.selected[5] === "T" ? "CONT" : "STOP")
                    }
                    Item { Layout.fillWidth: true }
                    ClockButton {
                        variant: "tonal"
                        symbol: "close"
                        label: Translation.tr("End")
                        onClicked: MonitorService.signalProcess(MonitorService.selectedPid, "TERM")
                    }
                    ClockButton {
                        variant: "filled"
                        danger: true
                        symbol: "dangerous"
                        label: Translation.tr("Kill")
                        onClicked: MonitorService.signalProcess(MonitorService.selectedPid, "KILL")
                    }
                }
            }
        }
    }
}

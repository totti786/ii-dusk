pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/** Every process: sort by a column, filter by text, pick one and end it. Space pauses the numbers. */
Item {
    id: root

    property bool compact: false
    property string sortKey: "cpu"
    property bool descending: true
    readonly property alias filterText: filterField.text

    // The sampler sends the whole table only while this page exists
    Component.onCompleted: MonitorService.fullProcsHolders++
    Component.onDestruction: MonitorService.fullProcsHolders = Math.max(0, MonitorService.fullProcsHolders - 1)

    // "/" puts the cursor in the filter
    Connections {
        target: MonitorService
        function onProcSearchFocusChanged() {
            Qt.callLater(() => filterField.input.forceActiveFocus());
        }
    }

    // Column order of a process row from the sampler
    readonly property var columns: [
        { key: "pid", label: "PID", index: 0, width: 70, align: Text.AlignRight },
        { key: "name", label: Translation.tr("Name"), index: 1, width: 0, align: Text.AlignLeft },
        { key: "user", label: Translation.tr("User"), index: 2, width: 90, align: Text.AlignLeft },
        { key: "threads", label: Translation.tr("Thr"), index: 6, width: 44, align: Text.AlignRight },
        { key: "mem", label: Translation.tr("Memory"), index: 4, width: 84, align: Text.AlignRight },
        { key: "cpu", label: "CPU", index: 3, width: 64, align: Text.AlignRight }
    ]

    readonly property var rows: {
        const q = root.filterText.trim().toLowerCase();
        const col = root.columns.find(c => c.key === root.sortKey);
        const i = col ? col.index : 3;
        const dir = root.descending ? -1 : 1;
        let list = MonitorService.procs;
        if (q !== "")
            list = list.filter(p => p[1].toLowerCase().includes(q) || p[7].toLowerCase().includes(q) || String(p[0]) === q);
        else
            list = list.slice();
        list.sort((a, b) => {
            const x = a[i], y = b[i];
            return (typeof x === "string" ? x.localeCompare(y) : x - y) * dir || a[0] - b[0];
        });
        return list.slice(0, 300);
    }
    readonly property var selected: MonitorService.procs.find(p => p[0] === MonitorService.selectedPid) ?? null

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

    function sortBy(key: string): void {
        if (root.sortKey === key) {
            root.descending = !root.descending;
        } else {
            root.sortKey = key;
            root.descending = !["pid", "name", "user"].includes(key);
        }
    }

    // The model is replaced every second; keep the scroll position and the selection
    onRowsChanged: {
        const y = list.contentY;
        list.model = root.rows;
        list.contentY = y;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            ClockFormField {
                id: filterField
                Layout.fillWidth: true
                symbol: "search"
                placeholder: Translation.tr("Filter by name, command or PID")
            }
            ClockButton {
                variant: MonitorService.paused ? "filled" : "tonal"
                symbol: MonitorService.paused ? "play_arrow" : "pause"
                label: MonitorService.paused ? Translation.tr("Resume") : Translation.tr("Pause")
                onClicked: MonitorService.paused = !MonitorService.paused
            }
        }

        // Header: click a column to sort
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 12
            Layout.rightMargin: 12
            spacing: 10
            Repeater {
                model: root.columns
                delegate: Item {
                    id: head
                    required property var modelData
                    Layout.fillWidth: modelData.width === 0
                    Layout.preferredWidth: modelData.width
                    implicitHeight: 28
                    StyledText {
                        anchors.fill: parent
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: head.modelData.align
                        text: head.modelData.label + (root.sortKey === head.modelData.key ? (root.descending ? " ▾" : " ▴") : "")
                        color: root.sortKey === head.modelData.key ? ClockStyle.colPrimary : ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Medium
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
            model: root.rows
            spacing: 2

            delegate: Rectangle {
                id: row
                required property var modelData
                readonly property bool isSelected: modelData[0] === MonitorService.selectedPid
                width: ListView.view.width
                height: 34
                radius: ClockStyle.radiusSmall
                color: row.isSelected ? ClockStyle.colSecondaryContainer : area.containsMouse ? ClockStyle.colSurfaceHover : "transparent"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    StyledText {
                        Layout.preferredWidth: 70
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData[0]
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData[1]
                        color: row.modelData[5] === "T" ? ClockStyle.colSubtext : ClockStyle.colOnBackground
                        font.italic: row.modelData[5] === "T"
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.preferredWidth: 90
                        text: row.modelData[2]
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.preferredWidth: 44
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData[6]
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    StyledText {
                        Layout.preferredWidth: 84
                        horizontalAlignment: Text.AlignRight
                        text: Fmt.bytes(row.modelData[4])
                        color: ClockStyle.colOnBackground
                    }
                    StyledText {
                        Layout.preferredWidth: 64
                        horizontalAlignment: Text.AlignRight
                        text: row.modelData[3].toFixed(1) + "%"
                        color: row.modelData[3] >= 50 ? ClockStyle.colPrimary : ClockStyle.colOnBackground
                        font.weight: row.modelData[3] >= 50 ? Font.Medium : Font.Normal
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: MonitorService.selectedPid = row.isSelected ? -1 : row.modelData[0]
                }
            }
        }

        // The picked process: what it is and what can be done to it
        Rectangle {
            Layout.fillWidth: true
            visible: root.selected !== null
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colSurface
            implicitHeight: pickRow.implicitHeight + 20

            RowLayout {
                id: pickRow
                anchors.fill: parent
                anchors.margins: 10
                spacing: 12
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selected ? `${root.selected[1]} · PID ${root.selected[0]}` : ""
                        color: ClockStyle.colOnBackground
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: MonitorService.error !== "" ? MonitorService.error : (root.selected ? root.selected[7] : "")
                        color: MonitorService.error !== "" ? ClockStyle.colError : ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }
                }
                ClockButton {
                    variant: "text"
                    symbol: root.selected && root.selected[5] === "T" ? "play_arrow" : "pause"
                    label: root.selected && root.selected[5] === "T" ? Translation.tr("Continue") : Translation.tr("Freeze")
                    onClicked: MonitorService.signalProcess(MonitorService.selectedPid, root.selected[5] === "T" ? "CONT" : "STOP")
                }
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

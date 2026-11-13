pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Files with identical content under a folder. In each group the oldest is kept and the rest are
/// ticked for the Trash; untick any to keep it too.
FmDialog {
    id: root

    property var backend: null
    property string path: ""
    property var groups: []
    property var marked: ({})
    property bool busy: true
    property bool hidden: false
    property string status: ""
    property int jobId: -1
    property real wasted: 0
    readonly property var markedPaths: Object.keys(root.marked).filter(k => root.marked[k])
    readonly property real markedBytes: {
        let t = 0;
        for (const g of root.groups)
            for (const p of g.paths)
                if (root.marked[p])
                    t += g.size;
        return t;
    }

    signal trashRequested(var paths)
    signal revealRequested(string path)

    title: qsTr("Duplicate files")
    cardWidth: 680

    function bytes(s: real): string {
        if (s < 1024)
            return Math.round(s) + " B";
        const u = ["KiB", "MiB", "GiB", "TiB"];
        let v = s / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(v < 10 ? 1 : 0) + " " + u[i];
    }

    function scan(): void {
        if (root.jobId >= 0 && root.busy)
            root.backend.cancel(root.jobId);
        root.busy = true;
        root.groups = [];
        root.marked = ({});
        root.status = qsTr("Looking for files…");
        let jid = -1;
        jid = root.backend.request("dupes", { path: root.path, hidden: root.hidden }, {
            progress: m => {
                if (jid !== root.jobId)
                    return;
                root.status = m.stage === "scan" ? qsTr("Looking at %1 files…").arg(m.files)
                    : qsTr("Comparing… %1 of %2").arg(root.bytes(m.done)).arg(root.bytes(m.total));
            },
            done: m => {
                if (jid !== root.jobId || m.cancelled)
                    return;
                root.busy = false;
                root.groups = m.groups;
                root.wasted = m.wasted;
                const mk = ({});
                for (const g of m.groups)
                    for (let i = 1; i < g.paths.length; i++)
                        mk[g.paths[i]] = true;
                root.marked = mk;
                root.status = m.groups.length === 0 ? qsTr("No duplicates among %1 files").arg(m.scanned) : "";
            },
            error: e => { if (jid === root.jobId) { root.busy = false; root.status = e; } }
        });
        root.jobId = jid;
    }

    function toggle(p: string): void {
        const mk = Object.assign({}, root.marked);
        mk[p] = !mk[p];
        root.marked = mk;
    }

    Component.onCompleted: {
        opacity = 1;
        root.scan();
    }
    onClosed: if (root.busy) root.backend.cancel(root.jobId)

    RowLayout {
        Layout.fillWidth: true
        spacing: 10
        StyledText {
            Layout.fillWidth: true
            text: root.path
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: ClockStyle.colOnSurfaceVariant
            elide: Text.ElideMiddle
        }
        FmChip {
            text: qsTr("Hidden files")
            checked: root.hidden
            onClicked: { root.hidden = !root.hidden; root.scan(); }
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.busy || root.groups.length > 0 || root.status.length > 0
        text: root.busy || root.groups.length === 0 ? root.status
            : qsTr("%1 groups, %2 could be freed").arg(root.groups.length).arg(root.bytes(root.wasted))
        font.pixelSize: Appearance.font.pixelSize.smallie
        font.weight: Font.DemiBold
        color: ClockStyle.colOnSurface
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: 340
        visible: root.groups.length > 0
        clip: true
        model: root.groups
        spacing: 8
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}

        delegate: Rectangle {
            id: card
            required property var modelData
            width: list.width
            height: head.implicitHeight + files.implicitHeight + 16
            radius: Appearance.rounding.small
            color: ClockStyle.colSurfaceHigh
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2
                RowLayout {
                    id: head
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: qsTr("%1 copies · %2 each").arg(card.modelData.paths.length).arg(root.bytes(card.modelData.size))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.DemiBold
                        color: ClockStyle.colSubtext
                    }
                }
                ColumnLayout {
                    id: files
                    Layout.fillWidth: true
                    spacing: 0
                    Repeater {
                        model: card.modelData.paths
                        delegate: Item {
                            id: frow
                            required property string modelData
                            readonly property bool on: root.marked[frow.modelData] === true
                            Layout.fillWidth: true
                            Layout.preferredHeight: 34
                            Rectangle {
                                anchors.fill: parent
                                radius: Appearance.rounding.verysmall
                                color: rowArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                spacing: 10
                                Rectangle {
                                    Layout.preferredWidth: 20
                                    Layout.preferredHeight: 20
                                    radius: 6
                                    color: frow.on ? ClockStyle.colError : "transparent"
                                    border.width: frow.on ? 0 : 2
                                    border.color: ClockStyle.colOutline
                                    MaterialSymbol {
                                        anchors.centerIn: parent
                                        visible: frow.on
                                        text: "delete"
                                        iconSize: 14
                                        color: ClockStyle.colOnError
                                    }
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: frow.modelData.startsWith(root.path + "/") ? frow.modelData.slice(root.path.length + 1) : frow.modelData
                                    font.pixelSize: Appearance.font.pixelSize.smallie
                                    color: frow.on ? ClockStyle.colOnSurface : ClockStyle.colPrimary
                                    elide: Text.ElideMiddle
                                }
                                StyledText {
                                    visible: !frow.on
                                    text: qsTr("keep")
                                    font.pixelSize: 11
                                    color: ClockStyle.colSubtext
                                }
                                FmIconButton {
                                    size: 28
                                    iconSize: 16
                                    symbol: "folder_open"
                                    tip: qsTr("Show in folder")
                                    onClicked: root.revealRequested(frow.modelData)
                                }
                            }
                            MouseArea {
                                id: rowArea
                                anchors.fill: parent
                                anchors.rightMargin: 40
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggle(frow.modelData)
                            }
                        }
                    }
                }
            }
        }
    }

    actions: [
        FmButton { text: qsTr("Close"); onClicked: root.close() },
        FmButton {
            text: root.markedPaths.length > 0 ? qsTr("Move %1 to Trash (%2)").arg(root.markedPaths.length).arg(root.bytes(root.markedBytes)) : qsTr("Move to Trash")
            kind: "danger"
            enabled2: root.markedPaths.length > 0 && !root.busy
            onClicked: root.trashRequested(root.markedPaths)
        }
    ]
}

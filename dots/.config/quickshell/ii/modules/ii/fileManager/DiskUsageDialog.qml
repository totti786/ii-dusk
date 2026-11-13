pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// What takes the space in a folder: each child with its share of the folder, largest first.
/// Click a folder to look inside it. Sizes are blocks in use, one filesystem, links not followed.
FmDialog {
    id: root

    property var backend: null
    property string path: ""
    property string start: ""
    property var items: []
    property real total: 0
    property real free: 0
    property real fsTotal: 0
    property bool busy: false
    property int jobId: -1
    readonly property real biggest: root.items.length > 0 ? Math.max(1, root.items[0].size) : 1

    signal openFolder(string path)

    title: qsTr("Disk usage")
    cardWidth: 640

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

    function scan(p: string): void {
        if (root.busy)
            root.backend.cancel(root.jobId);
        root.path = p;
        root.items = [];
        root.total = 0;
        root.busy = true;
        let jid = -1;
        jid = root.backend.request("du", { path: p }, {
            progress: m => { if (jid === root.jobId) root.items = m.items; },
            done: m => {
                if (jid !== root.jobId)
                    return;
                root.items = m.items;
                root.total = m.total;
                root.free = m.free;
                root.fsTotal = m.fsTotal;
                root.busy = false;
            },
            error: e => { if (jid === root.jobId) root.busy = false; }
        });
        root.jobId = jid;
    }

    Component.onCompleted: {
        root.start = root.path;
        root.scan(root.path);
    }
    onClosed: if (root.busy) root.backend.cancel(root.jobId)

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        FmIconButton {
            size: 32
            iconSize: 18
            symbol: "arrow_upward"
            enabled: root.path !== "/" && root.path !== root.start
            opacity: enabled ? 1 : 0.38
            onClicked: root.scan(root.path.replace(/\/[^/]*$/, "") || "/")
        }
        StyledText {
            Layout.fillWidth: true
            text: root.path
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: ClockStyle.colOnSurfaceVariant
            elide: Text.ElideMiddle
        }
        StyledText {
            text: root.busy ? qsTr("Counting… %1").arg(root.bytes(root.items.reduce((s, i) => s + i.size, 0))) : qsTr("%1 in use").arg(root.bytes(root.total))
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSurface
        }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: 360
        clip: true
        model: root.items
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}

        delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: 40
            Rectangle {
                anchors.fill: parent
                anchors.margins: 1
                radius: Appearance.rounding.small
                color: rowArea.containsMouse && row.modelData.isDir ? ClockStyle.colSurfaceHover : "transparent"
            }
            Rectangle {
                x: 6
                anchors.verticalCenter: parent.verticalCenter
                height: 26
                width: Math.max(4, (parent.width - 12) * row.modelData.size / root.biggest)
                radius: Appearance.rounding.verysmall
                color: row.modelData.isDir ? ClockStyle.colPrimaryContainer : ClockStyle.colSecondaryContainer
                opacity: 0.55
                Behavior on width { NumberAnimation { duration: Appearance.dur(160); easing.type: Easing.OutCubic } }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10
                MaterialSymbol {
                    text: row.modelData.isDir ? "folder" : "draft"
                    iconSize: 18
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    text: row.modelData.name
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colOnSurface
                    elide: Text.ElideMiddle
                }
                StyledText {
                    text: root.total > 0 ? Math.round(100 * row.modelData.size / root.total) + "%" : ""
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colSubtext
                }
                StyledText {
                    Layout.preferredWidth: 72
                    horizontalAlignment: Text.AlignRight
                    text: root.bytes(row.modelData.size)
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                }
            }
            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: row.modelData.isDir ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: if (row.modelData.isDir) root.scan(row.modelData.path)
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: !root.busy && root.items.length === 0
            text: qsTr("Empty")
            color: ClockStyle.colSubtext
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.fsTotal > 0
        text: qsTr("%1 free of %2 on this drive").arg(root.bytes(root.free)).arg(root.bytes(root.fsTotal))
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
    }

    actions: [
        FmButton { text: qsTr("Open this folder"); onClicked: { root.openFolder(root.path); root.close(); } },
        FmButton { text: qsTr("Close"); kind: "tonal"; onClicked: root.close() }
    ]
}

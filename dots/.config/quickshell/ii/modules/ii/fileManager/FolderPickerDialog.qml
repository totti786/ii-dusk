pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Pick a destination folder for Copy to… / Move to…: type a path, click through the folders, or
/// jump to a place or bookmark. Folders can be made on the spot.
FmDialog {
    id: root

    property var backend: null
    property string mode: "copy"
    property var srcs: []
    property string path: ""
    property var places: []
    property var folders: []
    property bool busy: false
    property string error: ""
    property int jobId: -1

    signal destinationPicked(string dest)

    title: root.mode === "copy" ? qsTr("Copy to…") : qsTr("Move to…")
    cardWidth: 580

    function parentOf(p: string): string {
        return p.replace(/\/[^/]*$/, "") || "/";
    }

    function go(p: string): void {
        if (root.busy)
            root.backend.cancel(root.jobId);
        const target = p.length === 0 ? "/" : p;
        root.busy = true;
        root.error = "";
        let parts = [];
        const natural = (a, b) => {
            const ax = a.name.toLowerCase().split(/(\d+)/), bx = b.name.toLowerCase().split(/(\d+)/);
            for (let i = 0; i < Math.min(ax.length, bx.length); ++i) {
                if (ax[i] === bx[i])
                    continue;
                if (i % 2 === 1) {
                    const d = parseInt(ax[i]) - parseInt(bx[i]);
                    if (d !== 0)
                        return d;
                }
                return ax[i] < bx[i] ? -1 : 1;
            }
            return ax.length - bx.length;
        };
        let jid = -1;
        jid = root.backend.request("list", { path: target }, {
            partial: m => { parts = parts.concat(m.entries); },
            done: m => {
                if (jid !== root.jobId)
                    return;
                root.busy = false;
                root.path = m.path;
                pathField.text = m.path;
                root.folders = parts.concat(m.entries).filter(e => e.isDir && !e.name.startsWith(".")).sort(natural);
                list.positionViewAtBeginning();
            },
            error: e => {
                if (jid !== root.jobId)
                    return;
                root.busy = false;
                root.error = e;
            }
        });
        root.jobId = jid;
    }

    function makeFolder(): void {
        const n = newName.text.trim();
        if (n.length === 0 || n.includes("/"))
            return;
        root.backend.request("mkdir", { dir: root.path, name: n }, {
            done: m => { newName.text = ""; root.go(m.dst); },
            error: e => { root.error = e; }
        });
    }

    Component.onCompleted: {
        opacity = 1;
        root.go(root.path);
        pathField.input.forceActiveFocus();
    }
    onClosed: if (root.busy) root.backend.cancel(root.jobId)

    StyledText {
        Layout.fillWidth: true
        text: root.srcs.length === 1 ? qsTr("“%1”").arg(root.srcs[0].replace(/^.*\//, "")) : qsTr("%1 items").arg(root.srcs.length)
        font.pixelSize: Appearance.font.pixelSize.smallie
        color: ClockStyle.colOnSurfaceVariant
        elide: Text.ElideMiddle
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Repeater {
            model: root.places
            delegate: FmChip {
                required property var modelData
                text: modelData.name
                icon: modelData.icon ?? ""
                checked: root.path === modelData.path
                onClicked: root.go(modelData.path)
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        FmIconButton {
            size: 36
            iconSize: 20
            symbol: "arrow_upward"
            tip: qsTr("Up")
            enabled2: root.path !== "/"
            onClicked: root.go(root.parentOf(root.path))
        }
        FmField {
            id: pathField
            Layout.fillWidth: true
            mono: true
            onAccepted: root.go(text.trim().replace(/^~(?=\/|$)/, root.backend.home))
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 280
        radius: Appearance.rounding.normal
        color: ClockStyle.colField
        clip: true

        ListView {
            id: list
            anchors.fill: parent
            anchors.margins: 4
            model: root.folders
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            WheelScroll {}
            delegate: Item {
                id: row
                required property var modelData
                width: list.width
                height: 38
                Rectangle {
                    anchors.fill: parent
                    radius: Appearance.rounding.small
                    color: area.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    MaterialSymbol { text: "folder"; iconSize: 20; color: ClockStyle.colPrimary }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.name
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ClockStyle.colOnSurface
                        elide: Text.ElideRight
                    }
                    MaterialSymbol { text: "chevron_right"; iconSize: 18; color: ClockStyle.colSubtext }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.go(row.modelData.path)
                }
            }
            StyledText {
                anchors.centerIn: parent
                visible: !root.busy && root.folders.length === 0
                text: root.error.length > 0 ? root.error : qsTr("No folders here")
                color: root.error.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smallie
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        FmField {
            id: newName
            Layout.fillWidth: true
            placeholder: qsTr("New folder here")
            onAccepted: root.makeFolder()
        }
        FmIconButton {
            size: 36
            iconSize: 20
            symbol: "create_new_folder"
            tip: qsTr("Create")
            enabled2: newName.text.trim().length > 0
            onClicked: root.makeFolder()
        }
    }

    actions: [
        FmButton { text: qsTr("Cancel"); onClicked: root.close() },
        FmButton {
            text: root.mode === "copy" ? qsTr("Copy here") : qsTr("Move here")
            kind: "filled"
            enabled2: root.path.length > 0 && !root.busy
            onClicked: root.destinationPicked(root.path)
        }
    ]
}

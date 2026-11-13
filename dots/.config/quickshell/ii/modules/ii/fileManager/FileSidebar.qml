pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Places, bookmarks, devices and the trash. Rows accept dropped files.
Rectangle {
    id: root

    property var places: []
    property var bookmarks: []
    property var devices: []
    property var phones: []
    property var netMounts: []
    property int trashCount: 0
    property string currentPath: ""
    property string dropHighlight: ""
    property string home: ""

    signal navigate(string path)
    signal contextRequested(var item, real x, real y)
    signal mountRequested(var dev)
    signal unmountRequested(var dev)
    signal phoneRequested(var dev)
    signal connectRequested()
    signal tabRequested(string path)
    signal netMountRequested(string uri)
    signal phoneDropped(var urls, var dev)
    signal dropped(var urls, string folder, int action)

    color: "transparent"

    readonly property var rows: {
        const out = [];
        out.push({ kind: "place", name: qsTr("Recent"), path: "recent:///", icon: "schedule" });
        out.push({ kind: "place", name: qsTr("Starred"), path: "starred:///", icon: "star" });
        for (const p of root.places)
            out.push({ kind: "place", name: p.name, path: p.path, icon: p.icon });
        // The standard folders are already in Places; bookmarks only add what is not there
        const have = new Set(root.places.map(p => p.path));
        const marks = root.bookmarks.filter(b => !have.has(b.path));
        if (marks.length > 0) {
            out.push({ kind: "header", name: qsTr("Bookmarks") });
            for (const b of marks)
                out.push({ kind: "bookmark", name: b.name, path: b.path, icon: "bookmark" });
        }
        // /home is its own partition on some setups but is the Home place; other system mounts stay hidden
        const devs = root.devices.filter(d => d.mount !== "/home" && (!d.system || d.mount === "/"));
        // A phone or camera on a cable is a device like a flash drive; only shares are "network"
        const usbScheme = n => n.scheme === "mtp" || n.scheme === "gphoto2" || n.scheme === "afc";
        const cabled = root.netMounts.filter(usbScheme);
        const shares = root.netMounts.filter(n => !usbScheme(n));
        const netRow = n => ({ kind: "net", name: n.name, path: n.path, icon: usbScheme(n) ? "smartphone" : "lan", mount: n,
            detail: n.mounted === false ? qsTr("Click to connect") : (usbScheme(n) ? qsTr("USB") : n.scheme.toUpperCase()) });
        if (devs.length > 0 || cabled.length > 0) {
            out.push({ kind: "header", name: qsTr("Devices") });
            for (const d of devs)
                out.push({ kind: "device", name: d.name, path: d.mount, icon: d.removable ? "usb" : (d.mount === "/" ? "computer" : "hard_drive"), dev: d, detail: d.detail ?? "", usage: d.mount.length > 0 && d.size > 0 ? d.used / d.size : -1 });
            for (const n of cabled)
                out.push(netRow(n));
        }
        // The Network section only exists while something is connected; "Connect to server…" is in the ⋮ menu
        if (shares.length > 0)
            out.push({ kind: "header", name: qsTr("Network"), action: "connect" });
        for (const n of shares)
            out.push(netRow(n));
        if (root.phones.length > 0) {
            out.push({ kind: "header", name: qsTr("Phone") });
            for (const ph of root.phones)
                out.push({ kind: "phone", name: ph.name, path: "kdc:" + ph.id, icon: ph.type === "tablet" ? "tablet_android" : "smartphone", phone: ph,
                    detail: ph.battery >= 0 ? (ph.charging ? qsTr("Charging · %1%") : qsTr("Battery %1%")).arg(ph.battery) : qsTr("Connected") });
        }
        out.push({ kind: "header", name: "" });
        out.push({ kind: "trash", name: qsTr("Trash"), path: "trash:///", icon: root.trashCount > 0 ? "delete" : "delete_outline" });
        return out;
    }

    ListView {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 6
        clip: true
        WheelScroll {}
        header: Item {
            width: ListView.view.width
            height: 68
            Rectangle {
                id: badge
                x: 4
                anchors.verticalCenter: parent.verticalCenter
                width: 40
                height: 40
                radius: Appearance.rounding.small
                color: ClockStyle.colPrimaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "folder_open"
                    iconSize: 22
                    fill: 1
                    color: ClockStyle.colOnPrimaryContainer
                }
            }
            Column {
                anchors.left: badge.right
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                StyledText {
                    width: parent.width
                    text: qsTr("Files")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: ClockStyle.colOnSurface
                }
            }
        }
        model: root.rows
        spacing: 1
        boundsBehavior: Flickable.StopAtBounds

        delegate: Item {
            id: row
            required property var modelData
            readonly property bool header: modelData.kind === "header"
            readonly property bool current: !header && (modelData.path ?? "").length > 0 && root.currentPath === modelData.path
            width: ListView.view.width
            height: header ? (modelData.name.length > 0 ? 30 : 10) : (modelData.kind === "device" ? 50 : ((modelData.kind === "phone" || modelData.kind === "net") ? 46 : 36))

            // A small add button at the end of the Network header
            Rectangle {
                visible: row.header && (row.modelData.action ?? "") === "connect"
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 24
                height: 24
                radius: Appearance.rounding.full
                color: addArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "add"
                    iconSize: 18
                    color: ClockStyle.colSubtext
                }
                MouseArea {
                    id: addArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.connectRequested()
                }
            }
            StyledText {
                visible: row.header && row.modelData.name.length > 0
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                text: row.modelData.name
                font.pixelSize: 11
                font.weight: Font.DemiBold
                color: ClockStyle.colSubtext
            }
            Rectangle {
                visible: row.header && row.modelData.name.length === 0
                anchors.verticalCenter: parent.verticalCenter
                x: 12
                width: parent.width - 24
                height: 1
                color: ClockStyle.colOutline
                opacity: 0.6
            }

            Rectangle {
                visible: !row.header
                anchors.fill: parent
                radius: 18
                color: root.dropHighlight !== "" && root.dropHighlight === row.modelData.path ? ClockStyle.colPrimaryContainer
                    : row.current ? ClockStyle.colSecondaryContainer
                    : (area.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                Behavior on color { ColorAnimation { duration: Appearance.dur(90) } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 10
                    spacing: 10
                    MaterialSymbol {
                        text: row.modelData.icon ?? ""
                        iconSize: 20
                        fill: row.current ? 1 : 0
                        color: row.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 1
                        StyledText {
                            Layout.fillWidth: true
                            text: row.modelData.name
                            font.pixelSize: Appearance.font.pixelSize.smallie
                            font.weight: row.current ? Font.DemiBold : Font.Normal
                            color: row.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
                            elide: Text.ElideRight
                        }
                        StyledText {
                            visible: row.modelData.kind === "device" || row.modelData.kind === "phone" || row.modelData.kind === "net"
                            Layout.fillWidth: true
                            text: row.modelData.detail ?? ""
                            font.pixelSize: 11
                            color: row.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                            opacity: 0.85
                            elide: Text.ElideRight
                        }
                        // How full a mounted drive is
                        Rectangle {
                            visible: row.modelData.kind === "device" && (row.modelData.usage ?? -1) >= 0
                            Layout.fillWidth: true
                            Layout.preferredHeight: 4
                            radius: 2
                            color: ClockStyle.colSurfaceHighest
                            Rectangle {
                                width: parent.width * Math.min(1, Math.max(0, row.modelData.usage ?? 0))
                                height: parent.height
                                radius: 2
                                color: (row.modelData.usage ?? 0) > 0.9 ? ClockStyle.colError : ClockStyle.colPrimary
                            }
                        }
                    }
                    StyledText {
                        visible: row.modelData.kind === "trash" && root.trashCount > 0
                        text: root.trashCount
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ClockStyle.colSubtext
                    }
                    // Mount state of a device
                    // The system drive (/ and /home) is always in use, so it has nothing to eject
                    MaterialSymbol {
                        visible: row.modelData.kind === "device" && !(row.modelData.dev?.system ?? false)
                        text: (row.modelData.path ?? "").length > 0 ? "eject" : "play_circle"
                        iconSize: 18
                        color: ClockStyle.colSubtext
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -8
                            cursorShape: Qt.PointingHandCursor
                            onClicked: (row.modelData.path ?? "").length > 0 ? root.unmountRequested(row.modelData.dev) : root.mountRequested(row.modelData.dev)
                        }
                    }
                }
                MouseArea {
                    id: area
                    anchors.fill: parent
                    z: -1
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: m => {
                        if (m.button === Qt.MiddleButton) {
                            const mp = row.modelData.path ?? "";
                            if (mp.length > 0 && row.modelData.kind !== "header" && row.modelData.kind !== "phone")
                                root.tabRequested(mp);
                        } else if (m.button === Qt.RightButton) {
                            const p = area.mapToItem(root, m.x, m.y);
                            root.contextRequested(row.modelData, p.x, p.y);
                        } else if (row.modelData.kind === "connect") {
                            root.connectRequested();
                        } else if (row.modelData.kind === "net" && row.modelData.mount.mounted === false) {
                            root.netMountRequested(row.modelData.mount.uri);
                        } else if (row.modelData.kind === "phone") {
                            root.phoneRequested(row.modelData.phone);
                        } else if (row.modelData.kind === "device" && (row.modelData.path ?? "").length === 0) {
                            root.mountRequested(row.modelData.dev);
                        } else {
                            root.navigate(row.modelData.path);
                        }
                    }
                }
                DropArea {
                    anchors.fill: parent
                    enabled: (row.modelData.path ?? "").length > 0 && row.modelData.kind !== "trash" && !(row.modelData.path ?? "").endsWith(":///")
                    keys: ["text/uri-list"]
                    onEntered: root.dropHighlight = row.modelData.path
                    onExited: root.dropHighlight = ""
                    onDropped: drop => {
                        root.dropHighlight = "";
                        if (row.modelData.kind === "phone") {
                            root.phoneDropped(drop.urls, row.modelData.phone);
                            drop.acceptProposedAction();
                            return;
                        }
                        root.dropped(drop.urls, row.modelData.path, drop.proposedAction);
                        drop.acceptProposedAction();
                    }
                }
            }
        }
    }
}

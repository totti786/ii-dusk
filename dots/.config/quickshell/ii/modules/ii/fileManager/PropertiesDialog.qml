pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Details of the selection: type, size (counted in the background), dates, owner and permissions.
FmDialog {
    id: root

    property var backend: null
    property var paths: []
    property var info: ({})
    property bool counting: true
    property int jobId: -1
    property string perms: ""
    property bool recursive: false

    signal changed()

    title: root.paths.length > 1 ? qsTr("%1 items").arg(root.paths.length) : (root.info.name ?? "")
    cardWidth: 480

    function bytes(s: real): string {
        if (s < 1024)
            return qsTr("%1 bytes").arg(Math.round(s));
        const u = ["KiB", "MiB", "GiB", "TiB"];
        let v = s / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(v < 10 ? 2 : 1) + " " + u[i] + "  (" + Math.round(s).toLocaleString(Qt.locale(), "f", 0) + " B)";
    }

    function when(t: real): string {
        return t ? Qt.formatDateTime(new Date(t * 1000), "d MMMM yyyy, HH:mm") : "—";
    }

    Component.onCompleted: {
        opacity = 1;
        root.jobId = root.backend.request("props", { paths: root.paths }, {
            progress: m => {
                root.info = Object.assign({}, root.info, { size: m.size, files: m.files, folders: m.folders });
            },
            done: m => {
                root.info = m;
                root.counting = false;
                root.perms = m.perms ?? "";
            },
            error: e => root.counting = false
        });
    }
    onClosed: if (root.counting) root.backend.cancel(root.jobId)

    function setBit(role: int, bit: int, on: bool): void {
        const digits = root.perms.padStart(3, "0").split("").map(Number);
        digits[role] = on ? (digits[role] | bit) : (digits[role] & ~bit);
        const next = digits.join("");
        root.backend.request("chmod", { paths: root.paths, mode: next, recursive: root.recursive }, {
            done: () => { root.perms = next; root.changed(); },
            error: e => {}
        });
    }

    component Row2: RowLayout {
        id: r
        property string k: ""
        property string v: ""
        Layout.fillWidth: true
        spacing: 12
        StyledText { Layout.preferredWidth: 110; text: r.k; font.pixelSize: Appearance.font.pixelSize.smallie; color: ClockStyle.colSubtext; verticalAlignment: Text.AlignTop }
        StyledText {
            Layout.fillWidth: true
            text: r.v
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: ClockStyle.colOnSurface
            wrapMode: Text.WrapAnywhere
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 14
        FileIcon {
            Layout.preferredWidth: 64
            Layout.preferredHeight: 64
            entry: root.info
            thumbSize: 128
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.info.mime ?? ""
                font.pixelSize: Appearance.font.pixelSize.smallie
                color: ClockStyle.colSubtext
                elide: Text.ElideRight
            }
            StyledText {
                text: root.counting ? qsTr("Counting…") : root.bytes(root.info.size ?? 0)
                font.pixelSize: 18
                font.weight: Font.DemiBold
                color: ClockStyle.colOnSurface
            }
        }
    }

    Row2 { visible: !root.info.multiple; k: qsTr("Location"); v: (root.info.path ?? "").replace(/\/[^/]*$/, "") || "/" }
    Row2 {
        visible: (root.info.isDir ?? false) || root.info.multiple === true
        k: qsTr("Contents")
        v: qsTr("%1 files, %2 folders").arg(root.info.files ?? 0).arg(Math.max(0, (root.info.folders ?? 0) - (root.info.multiple ? 0 : 1)))
    }
    Row2 { visible: (root.info.isLink ?? false); k: qsTr("Links to"); v: root.info.target ?? "" }
    Row2 { visible: !root.info.multiple; k: qsTr("Modified"); v: root.when(root.info.mtime) }
    Row2 { visible: !root.info.multiple; k: qsTr("Accessed"); v: root.when(root.info.atime) }
    Row2 { visible: !root.info.multiple; k: qsTr("Owner"); v: (root.info.owner ?? "") + " : " + (root.info.group ?? "") }
    Row2 { k: qsTr("Free space"); v: root.info.free ? root.bytes(root.info.free) : "—"; visible: !root.info.multiple }

    // Permissions
    ColumnLayout {
        visible: root.perms.length > 0
        Layout.fillWidth: true
        spacing: 4

        StyledText {
            text: qsTr("Permissions")
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSurface
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 0
            Item { Layout.fillWidth: true }
            Repeater {
                model: [qsTr("Read"), qsTr("Write"), qsTr("Execute")]
                delegate: StyledText {
                    required property string modelData
                    Layout.preferredWidth: 72
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colSubtext
                }
            }
        }
        Repeater {
            model: [qsTr("Owner"), qsTr("Group"), qsTr("Others")]
            delegate: RowLayout {
                id: prow
                required property string modelData
                required property int index
                readonly property int digit: Number(root.perms.padStart(3, "0")[prow.index] ?? 0)
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: prow.modelData
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: ClockStyle.colOnSurface
                }
                Repeater {
                    model: [4, 2, 1]
                    delegate: Item {
                        id: bit
                        required property int modelData
                        Layout.preferredWidth: 72
                        Layout.preferredHeight: 34
                        readonly property bool on: (prow.digit & bit.modelData) !== 0
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22
                            height: 22
                            radius: 7
                            color: bit.on ? ClockStyle.colPrimary : "transparent"
                            border.width: bit.on ? 0 : 2
                            border.color: ClockStyle.colOutline
                            MaterialSymbol {
                                anchors.centerIn: parent
                                visible: bit.on
                                text: "check"
                                iconSize: 16
                                color: ClockStyle.colOnPrimary
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setBit(prow.index, bit.modelData, !bit.on)
                        }
                    }
                }
            }
        }
    }

    FmChip {
        visible: root.perms.length > 0 && (root.info.folders ?? 0) > 0
        text: qsTr("Apply to everything inside")
        checked: root.recursive
        onClicked: root.recursive = !root.recursive
    }

    actions: [FmButton { text: qsTr("Close"); kind: "tonal"; onClicked: root.close() }]
}

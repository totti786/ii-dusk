import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// "A file with this name already exists": replace, skip, keep both, or stop.
FmDialog {
    id: root

    property var src: ({})
    property var dst: ({})
    property bool all: false
    /// A folder against a file: replacing would delete one for the other, so it is not offered.
    property bool mismatch: false

    signal resolved(string action, bool all)

    title: root.mismatch ? qsTr("“%1” is already taken").arg(root.dst.name ?? "") : qsTr("Replace “%1”?").arg(root.dst.name ?? "")
    cardWidth: 560
    dismissOnScrim: false

    function sizeText(e: var): string {
        if (e.isDir)
            return qsTr("Folder");
        const s = e.size ?? 0;
        if (s < 1024)
            return s + " B";
        const u = ["KiB", "MiB", "GiB", "TiB"];
        let v = s / 1024, i = 0;
        while (v >= 1024 && i < u.length - 1) {
            v /= 1024;
            i++;
        }
        return v.toFixed(1) + " " + u[i];
    }

    component Side: Rectangle {
        id: side
        property string heading: ""
        property var entry: ({})
        Layout.fillWidth: true
        implicitHeight: 100
        radius: Appearance.rounding.normal
        color: ClockStyle.colSurface
        RowLayout {
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12
            FileIcon {
                Layout.preferredWidth: 52
                Layout.preferredHeight: 52
                entry: side.entry
                thumbSize: 96
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText { text: side.heading; font.pixelSize: Appearance.font.pixelSize.smaller; color: ClockStyle.colPrimary; font.weight: Font.DemiBold }
                StyledText { text: root.sizeText(side.entry); font.pixelSize: Appearance.font.pixelSize.smallie; color: ClockStyle.colOnSurface }
                StyledText {
                    text: Qt.formatDateTime(new Date((side.entry.mtime ?? 0) * 1000), "d MMM yyyy, HH:mm")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colSubtext
                }
            }
        }
    }

    StyledText {
        Layout.fillWidth: true
        text: root.mismatch
            ? (root.dst.isDir ? qsTr("A folder with this name is already here, and the incoming item is a file. They cannot replace each other; keep both or skip.")
                              : qsTr("A file with this name is already here, and the incoming item is a folder. They cannot replace each other; keep both or skip."))
            : (root.dst.isDir ? qsTr("A folder with the same name is already in this folder.") : qsTr("A file with the same name is already in this folder."))
        font.pixelSize: Appearance.font.pixelSize.small
        color: ClockStyle.colOnSurfaceVariant
        wrapMode: Text.WordWrap
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        Side { heading: qsTr("Already here"); entry: root.dst }
        Side { heading: qsTr("Incoming"); entry: root.src }
    }
    FmChip {
        text: qsTr("Do this for all conflicts")
        checked: root.all
        onClicked: root.all = !root.all
    }

    actions: [
        FmButton { text: qsTr("Stop"); onClicked: root.resolved("cancel", false) },
        FmButton { text: qsTr("Skip"); onClicked: root.resolved("skip", root.all) },
        FmButton { text: qsTr("Keep both"); kind: root.mismatch ? "filled" : "tonal"; onClicked: root.resolved("rename", root.all) },
        FmButton { visible: !root.mismatch; text: qsTr("Replace"); kind: "filled"; onClicked: root.resolved("replace", root.all) }
    ]
}

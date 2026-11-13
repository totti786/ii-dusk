pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// MD5, SHA-1, SHA-256 and SHA-512 of one file, read once, with a field to paste the published hash into.
FmDialog {
    id: root

    property var backend: null
    property string path: ""
    property var hashes: ({})
    property real done: 0
    property real total: 1
    property bool busy: true
    property string failure: ""
    property int jobId: -1

    readonly property var algos: [["md5", "MD5"], ["sha1", "SHA-1"], ["sha256", "SHA-256"], ["sha512", "SHA-512"]]
    // "hash  filename" lines from a .sha256 file paste as they are
    readonly property string typed: verify.text.trim().split(/\s+/)[0].toLowerCase()
    readonly property string verdict: {
        if (root.busy || root.typed.length === 0)
            return "";
        for (const a of root.algos)
            if (root.hashes[a[0]] === root.typed)
                return a[1];
        return [32, 40, 64, 128].includes(root.typed.length) ? "no" : "";
    }

    title: qsTr("Checksums")
    cardWidth: 620

    Component.onCompleted: {
        root.jobId = root.backend.request("hash", { path: root.path, algos: root.algos.map(a => a[0]) }, {
            progress: m => {
                root.done = m.done;
                root.total = Math.max(1, m.total);
            },
            done: m => {
                root.hashes = m.hashes;
                root.busy = false;
            },
            error: e => {
                root.failure = e;
                root.busy = false;
            }
        });
    }
    onClosed: if (root.busy) root.backend.cancel(root.jobId)

    StyledText {
        Layout.fillWidth: true
        text: root.path.split("/").pop()
        font.pixelSize: Appearance.font.pixelSize.small
        color: ClockStyle.colOnSurfaceVariant
        elide: Text.ElideMiddle
    }

    Rectangle {
        Layout.fillWidth: true
        visible: root.busy
        implicitHeight: 6
        radius: 3
        color: ClockStyle.colSurfaceHighest
        Rectangle {
            width: parent.width * Math.min(1, root.done / root.total)
            height: parent.height
            radius: 3
            color: ClockStyle.colPrimary
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.failure.length > 0
        text: root.failure
        color: ClockStyle.colError
        font.pixelSize: Appearance.font.pixelSize.smallie
        wrapMode: Text.WordWrap
    }

    Repeater {
        model: root.algos
        delegate: ColumnLayout {
            id: line
            required property var modelData
            readonly property string value: root.hashes[line.modelData[0]] ?? ""
            Layout.fillWidth: true
            spacing: 2
            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    text: line.modelData[1]
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.weight: Font.DemiBold
                    color: root.verdict === line.modelData[1] ? ClockStyle.colPrimary : ClockStyle.colSubtext
                }
                Item { Layout.fillWidth: true }
                FmIconButton {
                    visible: line.value.length > 0
                    size: 28
                    iconSize: 16
                    symbol: "content_copy"
                    onClicked: Quickshell.execDetached(["wl-copy", "--", line.value])
                }
            }
            StyledText {
                Layout.fillWidth: true
                text: line.value.length > 0 ? line.value : (root.busy ? qsTr("Reading…") : "—")
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: "monospace"
                color: ClockStyle.colOnSurface
                wrapMode: Text.WrapAnywhere
            }
        }
    }

    FmField {
        id: verify
        Layout.fillWidth: true
        label: qsTr("Compare with a published checksum")
        placeholder: qsTr("Paste it here")
        mono: true
    }
    RowLayout {
        Layout.fillWidth: true
        visible: root.verdict.length > 0
        spacing: 8
        MaterialSymbol {
            text: root.verdict === "no" ? "error" : "check_circle"
            iconSize: 20
            color: root.verdict === "no" ? ClockStyle.colError : ClockStyle.colPrimary
        }
        StyledText {
            Layout.fillWidth: true
            text: root.verdict === "no" ? qsTr("It does not match this file") : qsTr("Matches the %1 checksum").arg(root.verdict)
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.verdict === "no" ? ClockStyle.colError : ClockStyle.colPrimary
        }
    }

    actions: [FmButton { text: qsTr("Close"); kind: "tonal"; onClicked: root.close() }]
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// What differs between two folders, by relative path: only on one side, or on both with another
/// size or content. Copying fills in what is missing; changed files are left for you to decide.
FmDialog {
    id: root

    property var backend: null
    property string a: ""
    property string b: ""
    property var result: null
    property bool busy: true
    property string failure: ""
    property string filter: "all"
    property int jobId: -1

    signal transferRequested(var srcs, string dest)

    title: qsTr("Compare folders")
    cardWidth: 700

    readonly property var rows: {
        const r = root.result;
        if (!r)
            return [];
        const out = [];
        if (root.filter === "all" || root.filter === "a")
            for (const e of r.onlyA)
                out.push(Object.assign({ side: "a" }, e));
        if (root.filter === "all" || root.filter === "b")
            for (const e of r.onlyB)
                out.push(Object.assign({ side: "b" }, e));
        if (root.filter === "all" || root.filter === "d")
            for (const e of r.differ)
                out.push(Object.assign({ side: "d" }, e));
        return out;
    }

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

    function detail(e: var): string {
        if (e.side !== "d")
            return e.isDir ? qsTr("folder") : root.bytes(e.size);
        if (e.why === "type")
            return qsTr("file on one side, folder on the other");
        const newer = Math.abs(e.mtimeA - e.mtimeB) <= 2 ? "" : (e.mtimeA > e.mtimeB ? qsTr("  ·  A is newer") : qsTr("  ·  B is newer"));
        return qsTr("A %1  ·  B %2").arg(root.bytes(e.sizeA)).arg(root.bytes(e.sizeB)) + newer;
    }

    /// Copy what one side lacks into the same place on the other side, one transfer per target folder
    function copyMissing(from: string): void {
        const list = from === "a" ? root.result.onlyA : root.result.onlyB;
        const srcRoot = from === "a" ? root.a : root.b;
        const dstRoot = from === "a" ? root.b : root.a;
        const groups = ({});
        for (const e of list) {
            const slash = e.rel.lastIndexOf("/");
            const parent = slash >= 0 ? e.rel.slice(0, slash) : "";
            (groups[parent] = groups[parent] ?? []).push(srcRoot + "/" + e.rel);
        }
        for (const parent of Object.keys(groups))
            root.transferRequested(groups[parent], parent.length > 0 ? dstRoot + "/" + parent : dstRoot);
        root.close();
    }

    Component.onCompleted: {
        root.jobId = root.backend.request("compare", { a: root.a, b: root.b }, {
            done: m => {
                root.result = m;
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
        text: qsTr("A  %1").arg(root.a)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
        elide: Text.ElideMiddle
    }
    StyledText {
        Layout.fillWidth: true
        text: qsTr("B  %1").arg(root.b)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
        elide: Text.ElideMiddle
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.busy || root.failure.length > 0
        text: root.failure.length > 0 ? root.failure : qsTr("Comparing…")
        color: root.failure.length > 0 ? ClockStyle.colError : ClockStyle.colSubtext
        font.pixelSize: Appearance.font.pixelSize.small
    }

    Flow {
        Layout.fillWidth: true
        visible: root.result !== null
        spacing: 8
        FmChip { text: qsTr("All"); checked: root.filter === "all"; onClicked: root.filter = "all" }
        FmChip { text: qsTr("Only in A  (%1)").arg(root.result?.onlyA.length ?? 0); checked: root.filter === "a"; onClicked: root.filter = "a" }
        FmChip { text: qsTr("Only in B  (%1)").arg(root.result?.onlyB.length ?? 0); checked: root.filter === "b"; onClicked: root.filter = "b" }
        FmChip { text: qsTr("Different  (%1)").arg(root.result?.differ.length ?? 0); checked: root.filter === "d"; onClicked: root.filter = "d" }
    }

    ListView {
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: 320
        visible: root.result !== null
        clip: true
        model: root.rows
        boundsBehavior: Flickable.StopAtBounds
        WheelScroll {}

        delegate: Item {
            id: row
            required property var modelData
            width: list.width
            height: 46
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 10
                MaterialSymbol {
                    text: row.modelData.side === "a" ? "keyboard_double_arrow_left" : (row.modelData.side === "b" ? "keyboard_double_arrow_right" : "compare_arrows")
                    iconSize: 20
                    color: row.modelData.side === "d" ? ClockStyle.colError : ClockStyle.colPrimary
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.rel + (row.modelData.isDir ? "/" : "")
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: ClockStyle.colOnSurface
                        elide: Text.ElideMiddle
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: row.modelData.side === "a" ? qsTr("Only in A  ·  %1").arg(root.detail(row.modelData))
                            : (row.modelData.side === "b" ? qsTr("Only in B  ·  %1").arg(root.detail(row.modelData)) : root.detail(row.modelData))
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: ClockStyle.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }
        }

        StyledText {
            anchors.centerIn: parent
            visible: root.result !== null && root.rows.length === 0
            text: root.result && root.result.onlyA.length + root.result.onlyB.length + root.result.differ.length === 0
                ? qsTr("The folders are identical") : qsTr("Nothing in this list")
            color: ClockStyle.colSubtext
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.result !== null
        text: qsTr("%1 files and folders are the same on both sides").arg(root.result?.same ?? 0)
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colSubtext
    }

    actions: [
        FmButton { text: qsTr("Copy A's extras to B"); visible: (root.result?.onlyA.length ?? 0) > 0; onClicked: root.copyMissing("a") },
        FmButton { text: qsTr("Copy B's extras to A"); visible: (root.result?.onlyB.length ?? 0) > 0; onClicked: root.copyMissing("b") },
        FmButton { text: qsTr("Close"); kind: "tonal"; onClicked: root.close() }
    ]
}

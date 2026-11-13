pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// Renames several files at once: find/replace, case, prefix/suffix and numbering, with a live preview.
FmDialog {
    id: root

    property var entries: []
    property string caseMode: "keep"   // keep, lower, upper, title
    property bool numbering: false
    property bool keepExt: true

    signal accepted(var pairs)

    title: qsTr("Rename %1 items").arg(root.entries.length)
    cardWidth: 620

    function transform(name: string, i: int): string {
        let dot = root.keepExt ? name.lastIndexOf(".") : -1;
        if (dot <= 0)
            dot = name.length;
        let stem = name.slice(0, dot);
        const ext = name.slice(dot);
        if (find.text.length > 0)
            stem = stem.split(find.text).join(repl.text);
        if (root.caseMode === "lower")
            stem = stem.toLowerCase();
        else if (root.caseMode === "upper")
            stem = stem.toUpperCase();
        else if (root.caseMode === "title")
            stem = stem.replace(/\w\S*/g, w => w[0].toUpperCase() + w.slice(1).toLowerCase());
        stem = prefix.text + stem + suffix.text;
        if (root.numbering) {
            const n = String((parseInt(start.text) || 1) + i).padStart(parseInt(digits.text) || 1, "0");
            stem = stem + " " + n;
        }
        return stem + ext;
    }

    readonly property var pairs: root.entries.map((e, i) => ({ path: e.path, from: e.name, to: root.transform(e.name, i) }))
    readonly property bool valid: {
        const names = root.pairs.map(p => p.to);
        return new Set(names).size === names.length && names.every(n => n.length > 0 && !n.includes("/"));
    }
    readonly property bool changes: root.pairs.some(p => p.from !== p.to)

    Component.onCompleted: {
        opacity = 1;
        find.input.forceActiveFocus();
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        columnSpacing: 12
        rowSpacing: 8
        FmField { id: find; Layout.fillWidth: true; label: qsTr("Find"); placeholder: qsTr("text to replace") }
        FmField { id: repl; Layout.fillWidth: true; label: qsTr("Replace with") }
        FmField { id: prefix; Layout.fillWidth: true; label: qsTr("Add before") }
        FmField { id: suffix; Layout.fillWidth: true; label: qsTr("Add after") }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        Repeater {
            model: [{ k: "keep", t: qsTr("Keep case") }, { k: "lower", t: "lowercase" }, { k: "upper", t: "UPPERCASE" }, { k: "title", t: "Title Case" }]
            delegate: FmChip {
                required property var modelData
                text: modelData.t
                checked: root.caseMode === modelData.k
                onClicked: root.caseMode = modelData.k
            }
        }
        Item { Layout.fillWidth: true }
        FmChip { text: qsTr("Keep extension"); checked: root.keepExt; onClicked: root.keepExt = !root.keepExt }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        FmChip { text: qsTr("Number them"); checked: root.numbering; onClicked: root.numbering = !root.numbering }
        FmField { id: start; visible: root.numbering; Layout.preferredWidth: 100; label: qsTr("Start at"); text: "1" }
        FmField { id: digits; visible: root.numbering; Layout.preferredWidth: 100; label: qsTr("Digits"); text: "2" }
        Item { Layout.fillWidth: true }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: 170
        radius: Appearance.rounding.small
        color: ClockStyle.colSurface
        ListView {
            anchors.fill: parent
            anchors.margins: 8
            clip: true
            model: root.pairs
            boundsBehavior: Flickable.StopAtBounds
            delegate: RowLayout {
                id: pr
                required property var modelData
                width: ListView.view.width
                height: 28
                spacing: 8
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: pr.modelData.from
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: ClockStyle.colSubtext
                    elide: Text.ElideMiddle
                }
                MaterialSymbol { text: "arrow_forward"; iconSize: 16; color: ClockStyle.colSubtext }
                StyledText {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: pr.modelData.to
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    font.weight: pr.modelData.from !== pr.modelData.to ? Font.DemiBold : Font.Normal
                    color: pr.modelData.from !== pr.modelData.to ? ClockStyle.colPrimary : ClockStyle.colOnSurface
                    elide: Text.ElideMiddle
                }
            }
        }
    }
    StyledText {
        visible: !root.valid
        text: qsTr("Some names would clash or be empty.")
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: ClockStyle.colError
    }

    actions: [
        FmButton { text: qsTr("Cancel"); onClicked: root.close() },
        FmButton {
            text: qsTr("Rename")
            kind: "filled"
            enabled2: root.valid && root.changes
            onClicked: root.accepted(root.pairs.filter(p => p.from !== p.to).map(p => [p.path, p.to]))
        }
    ]
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Manage custom actions. They live in Thunar's own ~/.config/Thunar/uca.xml, so the two file
 * managers share them; a backup of the file is kept the first time it is saved from here.
 */
FmDialog {
    id: root

    property var backend: null
    property var items: []
    property int current: -1
    property bool dirty: false

    signal saved()

    title: qsTr("Custom actions")
    cardWidth: 900

    readonly property var flagList: [
        { k: "directories", t: qsTr("Folders") }, { k: "image-files", t: qsTr("Images") },
        { k: "audio-files", t: qsTr("Audio") }, { k: "video-files", t: qsTr("Video") },
        { k: "text-files", t: qsTr("Text") }, { k: "other-files", t: qsTr("Other") }
    ]
    readonly property var cur: root.current >= 0 && root.current < root.items.length ? root.items[root.current] : null

    Component.onCompleted: {
        opacity = 1;
        root.backend.request("actionsAll", {}, { done: m => {
            root.items = m.actions;
            root.current = m.actions.length > 0 ? 0 : -1;
        } });
    }

    function patch(key: string, value: var): void {
        if (root.current < 0)
            return;
        const next = root.items.slice();
        next[root.current] = Object.assign({}, next[root.current], { [key]: value });
        root.items = next;
        root.dirty = true;
    }

    function toggleFlag(flag: string): void {
        const f = root.cur.flags.slice();
        const i = f.indexOf(flag);
        if (i >= 0)
            f.splice(i, 1);
        else
            f.push(flag);
        root.patch("flags", f);
    }

    function addAction(): void {
        const next = root.items.slice();
        next.push({ id: Date.now() + "-1", name: qsTr("New action"), submenu: "", icon: "", description: "", command: "",
            patterns: "*", range: "", flags: ["directories", "image-files", "audio-files", "video-files", "text-files", "other-files"],
            startupNotify: false, shortcut: "" });
        root.items = next;
        root.current = next.length - 1;
        root.dirty = true;
    }

    function removeAction(): void {
        if (root.current < 0)
            return;
        const next = root.items.slice();
        next.splice(root.current, 1);
        root.items = next;
        root.current = Math.min(root.current, next.length - 1);
        root.dirty = true;
    }

    function save(): void {
        root.backend.request("saveActions", { actions: root.items }, {
            done: () => { root.dirty = false; root.saved(); root.close(); },
            error: e => {}
        });
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 420
        spacing: 16

        // List
        ColumnLayout {
            Layout.preferredWidth: 260
            Layout.fillHeight: true
            spacing: 8
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Appearance.rounding.normal
                color: ClockStyle.colSurface
                ListView {
                    anchors.fill: parent
                    anchors.margins: 6
                    clip: true
                    model: root.items
                    boundsBehavior: Flickable.StopAtBounds
                    delegate: Rectangle {
                        id: item
                        required property var modelData
                        required property int index
                        width: ListView.view.width
                        height: 44
                        radius: Appearance.rounding.small
                        color: item.index === root.current ? ClockStyle.colSecondaryContainer : (ma.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 8
                            spacing: 0
                            Item { Layout.fillHeight: true }
                            StyledText {
                                Layout.fillWidth: true
                                text: item.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: ClockStyle.colOnSurface
                                elide: Text.ElideRight
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: item.modelData.submenu.length > 0 || item.modelData.shortcut.length > 0
                                text: [item.modelData.submenu, item.modelData.shortcut].filter(s => s.length > 0).join(" · ")
                                font.pixelSize: 11
                                color: ClockStyle.colSubtext
                                elide: Text.ElideRight
                            }
                            Item { Layout.fillHeight: true }
                        }
                        MouseArea {
                            id: ma
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.current = item.index
                        }
                    }
                }
            }
            RowLayout {
                Layout.fillWidth: true
                FmButton { text: qsTr("Add"); icon: "add"; kind: "tonal"; onClicked: root.addAction() }
                Item { Layout.fillWidth: true }
                FmButton { text: qsTr("Delete"); icon: "delete"; enabled2: root.cur !== null; onClicked: root.removeAction() }
            }
        }

        // Form
        ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            contentWidth: availableWidth
            ColumnLayout {
                visible: root.cur !== null
                width: parent.width - 12
                spacing: 10
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    FmField { Layout.fillWidth: true; label: qsTr("Name"); text: root.cur?.name ?? ""; onEdited: root.patch("name", text) }
                    FmField { Layout.fillWidth: true; label: qsTr("Submenu"); placeholder: qsTr("(none)"); text: root.cur?.submenu ?? ""; onEdited: root.patch("submenu", text) }
                }
                FmField {
                    Layout.fillWidth: true
                    label: qsTr("Command")
                    mono: true
                    text: root.cur?.command ?? ""
                    onEdited: root.patch("command", text)
                }
                StyledText {
                    Layout.fillWidth: true
                    text: qsTr("%f first file · %F all files · %n name · %N names · %d folder · %D folders · %u / %U as URIs. Runs in the file’s folder, through sh.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ClockStyle.colSubtext
                    wrapMode: Text.WordWrap
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 10
                    FmField { Layout.fillWidth: true; label: qsTr("File patterns"); placeholder: "*"; text: root.cur?.patterns ?? ""; onEdited: root.patch("patterns", text) }
                    FmField { Layout.preferredWidth: 130; label: qsTr("How many files"); placeholder: "*  or  1-1"; text: root.cur?.range ?? ""; onEdited: root.patch("range", text) }
                }
                FmField { Layout.fillWidth: true; label: qsTr("Description"); text: root.cur?.description ?? ""; onEdited: root.patch("description", text) }
                StyledText { text: qsTr("Shown for"); font.pixelSize: Appearance.font.pixelSize.smaller; color: ClockStyle.colSubtext }
                Flow {
                    Layout.fillWidth: true
                    spacing: 8
                    Repeater {
                        model: root.flagList
                        delegate: FmChip {
                            required property var modelData
                            text: modelData.t
                            checked: (root.cur?.flags ?? []).indexOf(modelData.k) >= 0
                            onClicked: root.toggleFlag(modelData.k)
                        }
                    }
                }
            }
        }
    }

    actions: [
        FmButton { text: qsTr("Cancel"); onClicked: root.close() },
        FmButton { text: qsTr("Save"); kind: "filled"; enabled2: root.dirty; onClicked: root.save() }
    ]
}

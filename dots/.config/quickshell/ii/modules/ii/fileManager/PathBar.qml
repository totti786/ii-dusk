pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Breadcrumbs for the current folder; clicking the empty end (or Ctrl+L) turns it into a text
 * field. Crumbs accept dropped files. When the path is too long the leading crumbs scroll away.
 */
Rectangle {
    id: root

    property string path: ""
    property string home: ""
    property bool editing: false

    signal navigate(string path)
    signal tabRequested(string path)
    signal dropped(var urls, string folder, int action)

    function beginEdit(): void {
        root.editing = true;
        input.text = root.path.startsWith("trash:") ? "trash:///" : root.path;
        input.forceActiveFocus();
        input.selectAll();
    }

    readonly property var crumbs: {
        if (root.path.startsWith("trash:"))
            return [{ name: qsTr("Trash"), path: "trash:///", icon: "delete" }];
        const out = [{ name: "/", path: "/", icon: "" }];
        let acc = "";
        const parts = root.path.split("/").filter(p => p.length > 0);
        let homeParts = root.home.split("/").filter(p => p.length > 0);
        const underHome = root.home.length > 0 && (root.path === root.home || root.path.startsWith(root.home + "/"));
        if (underHome) {
            out.length = 0;
            out.push({ name: qsTr("Home"), path: root.home, icon: "home" });
            acc = root.home;
            for (const p of parts.slice(homeParts.length)) {
                acc += "/" + p;
                out.push({ name: p, path: acc, icon: "" });
            }
            return out;
        }
        for (const p of parts) {
            acc += "/" + p;
            out.push({ name: p, path: acc, icon: "" });
        }
        return out;
    }

    implicitHeight: 38
    radius: Appearance.rounding.full
    color: ClockStyle.colSurfaceHigh
    border.width: root.editing ? 2 : 0
    border.color: ClockStyle.colPrimary

    Flickable {
        id: flick
        visible: !root.editing
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        contentWidth: crumbRow.width
        clip: true
        interactive: false
        flickableDirection: Flickable.HorizontalFlick
        onContentWidthChanged: contentX = Math.max(0, contentWidth - width)
        onWidthChanged: contentX = Math.max(0, contentWidth - width)

        Row {
            id: crumbRow
            height: flick.height
            spacing: 0
            Repeater {
                model: root.crumbs
                delegate: Row {
                    id: crumb
                    required property var modelData
                    required property int index
                    height: crumbRow.height
                    MaterialSymbol {
                        visible: crumb.index > 0 && !(crumb.index === 1 && root.crumbs[0].path === "/")
                        anchors.verticalCenter: parent.verticalCenter
                        text: "chevron_right"
                        iconSize: 18
                        color: ClockStyle.colSubtext
                    }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 26
                        width: label.implicitWidth + (crumb.modelData.icon ? 40 : 20)
                        radius: Appearance.rounding.full
                        color: dropArea.containsDrag ? ClockStyle.colPrimaryContainer
                            : (crumbArea.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                        Row {
                            anchors.centerIn: parent
                            spacing: 6
                            MaterialSymbol {
                                visible: crumb.modelData.icon.length > 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: crumb.modelData.icon
                                iconSize: 18
                                color: ClockStyle.colOnSurfaceVariant
                            }
                            StyledText {
                                id: label
                                anchors.verticalCenter: parent.verticalCenter
                                text: crumb.modelData.name
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: crumb.index === root.crumbs.length - 1 ? Font.DemiBold : Font.Normal
                                color: ClockStyle.colOnSurface
                            }
                        }
                        MouseArea {
                            id: crumbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                            onClicked: m => m.button === Qt.MiddleButton ? root.tabRequested(crumb.modelData.path) : root.navigate(crumb.modelData.path)
                        }
                        DropArea {
                            id: dropArea
                            anchors.fill: parent
                            keys: ["text/uri-list"]
                            onDropped: drop => {
                                root.dropped(drop.urls, crumb.modelData.path, drop.proposedAction);
                                drop.acceptProposedAction();
                            }
                        }
                    }
                }
            }
        }
    }

    // Click on the empty part edits the path
    MouseArea {
        visible: !root.editing
        anchors.fill: parent
        z: -1
        onClicked: root.beginEdit()
    }

    TextInput {
        id: input
        visible: root.editing
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        verticalAlignment: TextInput.AlignVCenter
        color: ClockStyle.colOnSurface
        font.pixelSize: Appearance.font.pixelSize.small
        font.family: Appearance.font.family.main
        selectByMouse: true
        clip: true
        onAccepted: {
            root.editing = false;
            root.navigate(text.trim());
        }
        Keys.onEscapePressed: root.editing = false
        onActiveFocusChanged: if (!activeFocus) root.editing = false
    }
}

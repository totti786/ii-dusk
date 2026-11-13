pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A popup menu for the file manager: `popup(items, x, y)` shows it at a point of the window.
 * Items: { id, text, icon, shortcut, danger, disabled, checked, separator, submenu: [items] }.
 * One level of submenu opens beside the row under the pointer.
 */
FocusScope {
    id: root

    property var items: []
    property real px: 0
    property real py: 0
    property var sub: []
    property real subY: 0
    property real subRowHeight: 0

    signal triggered(var item)
    signal closed()

    anchors.fill: parent
    visible: false
    z: 1000

    function popup(list: var, x: real, y: real): void {
        root.items = list;
        root.sub = [];
        root.px = x;
        root.py = y;
        root.visible = true;
        root.forceActiveFocus();
    }

    function close(): void {
        if (!root.visible)
            return;
        root.visible = false;
        root.sub = [];
        root.closed();
    }

    function pick(item: var): void {
        root.close();
        root.triggered(item);
    }

    Keys.onEscapePressed: root.close()

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onPressed: root.close()
    }

    component MenuCard: Rectangle {
        id: card

        property var model: []
        readonly property bool hasIcons: card.model.some(i => (i.icon ?? "").length > 0 || i.checked !== undefined)

        signal hoveredRow(var item, real y, real h)
        signal chosen(var item)

        width: 216
        height: list.implicitHeight + 10
        radius: Appearance.rounding.normal
        color: ClockStyle.colSheet

        // Pops in from the corner it opened at
        transformOrigin: Item.TopLeft
        opacity: root.visible ? 1 : 0
        scale: root.visible ? 1 : 0.94
        Behavior on opacity { NumberAnimation { duration: Appearance.dur(110) } }
        Behavior on scale { NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic } }

        StyledRectangularShadow { target: card; z: -1 }

        MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

        Column {
            id: list
            x: 5
            y: 5
            width: parent.width - 10
            spacing: 0

            Repeater {
                model: card.model
                delegate: Item {
                    id: row
                    required property var modelData
                    readonly property bool sep: Boolean(modelData.separator)
                    width: list.width
                    height: sep ? 7 : 30

                    Rectangle {
                        visible: row.sep
                        anchors.verticalCenter: parent.verticalCenter
                        x: 10
                        width: parent.width - 20
                        height: 1
                        radius: 1
                        color: ClockStyle.colOutline
                        opacity: 0.5
                    }

                    Rectangle {
                        visible: !row.sep
                        anchors.fill: parent
                        radius: rowArea.containsMouse && !row.modelData.disabled ? 14 : 12
                        Behavior on radius { NumberAnimation { duration: Appearance.dur(100) } }
                        color: rowArea.containsMouse && !row.modelData.disabled
                            ? (row.modelData.danger ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer) : "transparent"
                        opacity: row.modelData.disabled ? 0.4 : 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            spacing: 9
                            Item {
                                id: iconBox
                                visible: card.hasIcons
                                Layout.preferredWidth: 18
                                Layout.preferredHeight: 18
                                // A theme icon (a custom action's own) wins; one the theme lacks falls back to the symbol
                                readonly property string themed: row.modelData.checked === true || !row.modelData.themeIcon ? "" : Quickshell.iconPath(row.modelData.themeIcon, true)
                                Image {
                                    anchors.fill: parent
                                    visible: iconBox.themed.length > 0
                                    source: iconBox.themed
                                    sourceSize: Qt.size(36, 36)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    visible: iconBox.themed.length === 0
                                    text: row.modelData.checked === true ? "check" : (row.modelData.icon ?? "")
                                    iconSize: 17
                                    color: row.modelData.danger ? ClockStyle.colError
                                        : (rowArea.containsMouse ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant)
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.text ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smallie
                                color: row.modelData.danger ? ClockStyle.colError
                                    : (rowArea.containsMouse ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface)
                                elide: Text.ElideRight
                            }
                            StyledText {
                                visible: (row.modelData.shortcut ?? "").length > 0
                                text: row.modelData.shortcut ?? ""
                                font.pixelSize: 11
                                color: ClockStyle.colSubtext
                            }
                            MaterialSymbol {
                                visible: (row.modelData.submenu ?? []).length > 0
                                text: "chevron_right"
                                iconSize: 17
                                color: ClockStyle.colSubtext
                            }
                        }
                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: card.hoveredRow(row.modelData, row.y + list.y, row.height)
                            onClicked: {
                                if (row.modelData.disabled || (row.modelData.submenu ?? []).length > 0)
                                    return;
                                card.chosen(row.modelData);
                            }
                        }
                    }
                }
            }
        }
    }

    MenuCard {
        id: main
        model: root.items
        x: Math.max(8, Math.min(root.px, root.width - width - 8))
        y: Math.max(8, Math.min(root.py, root.height - height - 8))
        onHoveredRow: (item, y, h) => {
            root.sub = item.submenu ?? [];
            root.subY = y;
        }
        onChosen: item => root.pick(item)
    }

    MenuCard {
        id: subCard
        visible: root.sub.length > 0
        model: root.sub
        x: main.x + main.width + width + 8 < root.width ? main.x + main.width - 2 : main.x - width + 2
        y: Math.max(8, Math.min(main.y + root.subY - 6, root.height - height - 8))
        onChosen: item => root.pick(item)
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Widgets

/// Tray icons, left click activates, middle click is the secondary action, right click opens the menu.
Row {
    id: root

    property var barWindow: null

    spacing: 8

    Repeater {
        model: SystemTray.items
        delegate: MouseArea {
            id: slot
            required property SystemTrayItem modelData
            width: 20
            height: 20
            anchors.verticalCenter: parent.verticalCenter
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onClicked: mouse => {
                if (mouse.button === Qt.LeftButton && !slot.modelData.onlyMenu)
                    slot.modelData.activate();
                else if (mouse.button === Qt.MiddleButton)
                    slot.modelData.secondaryActivate();
                else if (slot.modelData.hasMenu)
                    menu.open();
            }

            IconImage {
                anchors.fill: parent
                source: slot.modelData.icon
                asynchronous: true
                mipmap: true
            }

            QsMenuAnchor {
                id: menu
                menu: slot.modelData.menu
                anchor.window: root.barWindow
                // Anchored to the item itself: a rect mapped once at binding time went stale
                // whenever the tray's icons moved, and sent the menu to the old spot.
                anchor.item: slot
                anchor.edges: Edges.Bottom | Edges.Left
                anchor.gravity: Edges.Bottom | Edges.Right
                anchor.margins.top: 6
            }
        }
    }
}

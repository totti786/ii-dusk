pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs.modules.common
import qs.modules.common.widgets

/**
 * A hover tooltip for the Lite bar: a small popup window under `target`, shown after a short
 * delay while `hovered` stays true and built only then. The bar window is as tall as its pills,
 * so the tip has to be a window of its own rather than an item.
 */
Item {
    id: root

    required property var barWindow
    property Item target: parent
    property bool hovered: false
    property string text: ""
    property int delay: 450

    property bool shown: false
    onHoveredChanged: if (!root.hovered) root.shown = false

    Timer {
        interval: root.delay
        running: root.hovered && root.text !== ""
        onTriggered: root.shown = true
    }

    LazyLoader {
        active: root.shown && root.text !== ""

        PopupWindow {
            anchor.window: root.barWindow
            anchor.item: root.target
            anchor.edges: Edges.Bottom
            anchor.gravity: Edges.Bottom
            anchor.margins.top: 4
            implicitWidth: label.implicitWidth + 24
            implicitHeight: label.implicitHeight + 14
            color: "transparent"
            visible: true

            Rectangle {
                anchors.fill: parent
                radius: 12
                color: Appearance.colors.colLayer0Base
                border.width: 1
                border.color: Appearance.colors.colLayer0Border
                StyledText {
                    id: label
                    anchors.centerIn: parent
                    text: root.text
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The usual unicode emoji, for reactions. */
Rectangle {
    id: root

    signal picked(string emoji)

    readonly property var emojis: ["👍", "👎", "❤️", "😂", "😮", "😢", "😡", "🎉", "🔥", "👀", "🙏", "✅", "❌", "💯", "🤔", "😍",
        "🥲", "😅", "🤣", "😭", "😊", "😎", "🤝", "👏", "💀", "😴", "🤯", "🫡", "💔", "⭐", "🚀", "👌"]

    implicitWidth: 8 * 34 + 16
    implicitHeight: Math.ceil(root.emojis.length / 8) * 34 + 16
    radius: ClockStyle.radiusNormal
    color: ClockStyle.colSheet
    border.width: 1
    border.color: ClockStyle.colOutline

    Grid {
        anchors.centerIn: parent
        columns: 8
        Repeater {
            model: root.emojis
            Rectangle {
                id: cell
                required property string modelData
                width: 34
                height: 34
                radius: 8
                color: hover.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                StyledText {
                    anchors.centerIn: parent
                    text: cell.modelData
                    font.pixelSize: 20
                }
                MouseArea {
                    id: hover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(cell.modelData)
                }
            }
        }
    }
}

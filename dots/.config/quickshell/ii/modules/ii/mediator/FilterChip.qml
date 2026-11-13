import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/** A small selectable pill for the Streaming filters (sort, genre, year). */
Rectangle {
    id: root

    property string label: ""
    property bool selected: false
    signal clicked

    implicitWidth: text.implicitWidth + 26
    implicitHeight: 32
    radius: height / 2
    color: root.selected ? Appearance.colors.colSecondaryContainer
         : area.containsMouse ? Appearance.colors.colLayer1 : "transparent"
    border.width: root.selected ? 0 : 1
    border.color: Appearance.colors.colOutlineVariant

    StyledText {
        id: text
        anchors.centerIn: parent
        text: root.label
        color: Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.small
        font.weight: root.selected ? Font.Medium : Font.Normal
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

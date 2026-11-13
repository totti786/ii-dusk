import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// A pill with an optional icon and a label: a tab, or a toggle in the top bar.
Rectangle {
    id: root

    property string icon: ""
    property string text: ""
    property bool active: false
    signal clicked()

    implicitHeight: 40
    implicitWidth: row.implicitWidth + 28
    radius: Appearance.rounding.full
    color: root.active ? Appearance.colors.colSecondaryContainer
        : area.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        MaterialSymbol {
            visible: root.icon !== ""
            text: root.icon
            iconSize: 20
            fill: root.active ? 1 : 0
            color: root.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
        }
        StyledText {
            visible: root.text !== ""
            text: root.text
            font.weight: Font.Medium
            color: root.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/// A small label for one fact about a poem; it opens a list when `clickable`.
Rectangle {
    id: root

    property string text: ""
    property bool clickable: false
    property bool active: false
    signal clicked()

    implicitHeight: 30
    implicitWidth: label.implicitWidth + 26
    radius: height / 2
    color: root.active ? Appearance.colors.colSecondaryContainer
        : root.clickable && area.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.small
        color: root.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colSubtext
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.clickable
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

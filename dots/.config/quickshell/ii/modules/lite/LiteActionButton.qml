import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/// A small pill button for the actions under a selected network or device.
Rectangle {
    id: root

    property string text: ""
    property bool primary: false
    property bool danger: false
    signal clicked()

    implicitWidth: label.implicitWidth + 28
    implicitHeight: 34
    radius: 17
    color: primary ? Appearance.colors.colPrimary
        : area.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

    StyledText {
        id: label
        anchors.centerIn: parent
        text: root.text
        font.pixelSize: Appearance.font.pixelSize.smaller
        font.weight: Font.Medium
        color: root.primary ? Appearance.colors.colOnPrimary
            : root.danger ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer0
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

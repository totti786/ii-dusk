import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/// A round icon button, in the Mediator's style: bare until hovered, filled when it is the
/// primary action, tinted when it is switched on.
Rectangle {
    id: root

    property string icon: ""
    property bool active: false
    property bool primary: false
    /// Moves the icon up (negative) to make room for a caption under it
    property real iconOffset: 0
    property real iconSize: primary ? 26 : 22
    signal clicked()

    implicitWidth: primary ? 44 : 40
    implicitHeight: implicitWidth
    radius: implicitWidth / 2
    opacity: enabled ? 1 : 0.4
    color: root.primary ? Appearance.colors.colPrimary
        : root.active ? Appearance.colors.colSecondaryContainer
        : area.containsMouse && root.enabled ? Appearance.colors.colLayer2 : "transparent"

    MaterialSymbol {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: root.iconOffset
        text: root.icon
        iconSize: root.iconSize
        fill: root.primary || root.active ? 1 : 0
        color: root.primary ? Appearance.colors.colOnPrimary
            : root.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

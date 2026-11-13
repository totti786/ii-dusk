import QtQuick

import qs.modules.common
import qs.modules.common.widgets

/// A round icon button: bare until hovered, tinted when switched on.
Rectangle {
    id: root

    property string icon: ""
    property bool active: false
    property string tip: ""
    signal clicked()

    implicitWidth: 40
    implicitHeight: 40
    radius: Appearance.rounding.full
    opacity: enabled ? 1 : 0.35
    color: root.active ? Appearance.colors.colSecondaryContainer
        : area.containsMouse && root.enabled ? Appearance.colors.colLayer2 : "transparent"

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.icon
        iconSize: 22
        fill: root.active ? 1 : 0
        color: root.active ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer0
    }
    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.enabled
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
        StyledToolTip {
            text: root.tip
            extraVisibleCondition: root.tip !== ""
            requireOverlay: false
        }
    }
}

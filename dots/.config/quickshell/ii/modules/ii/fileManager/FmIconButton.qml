import QtQuick
import QtQuick.Controls

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A round icon button with a tooltip.
Rectangle {
    id: root

    property string symbol: ""
    property string tip: ""
    property real size: 30
    property real iconSize: 19
    property bool active: false
    property bool filled: false
    property bool enabled2: true
    property color iconColor: root.active ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
    readonly property bool hovered: area.containsMouse

    signal clicked()
    signal rightClicked()

    implicitWidth: size
    implicitHeight: size
    radius: size / 2
    color: active ? ClockStyle.colSecondaryContainer
        : (area.containsMouse && enabled2 ? ClockStyle.colSurfaceHover : "transparent")
    opacity: enabled2 ? 1 : 0.38
    scale: area.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: Appearance.dur(80) } }
    Behavior on color { ColorAnimation { duration: Appearance.dur(100) } }

    MaterialSymbol {
        anchors.centerIn: parent
        text: root.symbol
        iconSize: root.iconSize
        fill: root.filled || root.active ? 1 : 0
        color: root.iconColor
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled2
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => mouse.button === Qt.RightButton ? root.rightClicked() : root.clicked()
    }
    ToolTip {
        visible: area.containsMouse && root.tip.length > 0
        delay: 600
        text: root.tip
        font.pixelSize: Appearance.font.pixelSize.smaller
        contentItem: StyledText {
            text: root.tip
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: ClockStyle.colOnSurface
        }
        background: Rectangle {
            radius: Appearance.rounding.verysmall
            color: ClockStyle.colSurfaceHighest
        }
    }
}

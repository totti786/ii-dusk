import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A selectable chip (filter, toggle or option).
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property bool checked: false

    signal clicked()

    implicitWidth: row.implicitWidth + 26
    implicitHeight: 34
    radius: Appearance.rounding.full
    color: checked ? ClockStyle.colSecondaryContainer : (area.containsMouse ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh)
    
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 6
        MaterialSymbol {
            visible: root.checked || root.icon.length > 0
            text: root.checked ? "check" : root.icon
            iconSize: 16
            color: root.checked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurfaceVariant
        }
        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.smallie
            color: root.checked ? ClockStyle.colOnSecondaryContainer : ClockStyle.colOnSurface
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

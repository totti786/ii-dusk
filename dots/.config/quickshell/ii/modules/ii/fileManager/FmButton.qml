import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// A pill button. `kind`: "filled", "tonal", "text" or "danger".
Rectangle {
    id: root

    property string text: ""
    property string icon: ""
    property string kind: "text"
    property bool enabled2: true
    // Set by a dialog while the keyboard has this button highlighted
    property bool kbFocus: false

    signal clicked()

    readonly property color fg: kind === "filled" ? ClockStyle.colOnPrimary
        : kind === "tonal" ? ClockStyle.colOnSecondaryContainer
        : kind === "danger" ? ClockStyle.colOnError : ClockStyle.colPrimary
    implicitWidth: row.implicitWidth + 36
    implicitHeight: 40
    radius: Appearance.rounding.full
    color: kind === "filled" ? ClockStyle.colPrimary
        : kind === "tonal" ? ClockStyle.colSecondaryContainer
        : kind === "danger" ? ClockStyle.colError
        : (area.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
    opacity: root.enabled2 ? 1 : 0.38
    scale: area.pressed ? 0.96 : 1
    Behavior on scale { NumberAnimation { duration: Appearance.dur(80) } }
    Behavior on color { ColorAnimation { duration: Appearance.dur(100) } }

    Rectangle {
        anchors.fill: parent
        anchors.margins: -4
        radius: root.radius + 4
        color: "transparent"
        border.width: 2
        border.color: ClockStyle.colPrimary
        opacity: root.kbFocus ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Appearance.dur(100) } }
    }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8
        MaterialSymbol {
            visible: root.icon.length > 0
            text: root.icon
            iconSize: 18
            color: root.fg
        }
        StyledText {
            text: root.text
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: root.fg
        }
    }
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        enabled: root.enabled2
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}

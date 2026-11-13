import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/** One row of the torrent menus: a glyph, a label, and an optional trailing check. */
MenuItem {
    id: item

    property string symbol: ""
    property bool destructive: false
    property bool current: false
    readonly property real innerRadius: Math.max(0, Appearance.rounding.windowRounding - 6)
    readonly property color fg: item.destructive ? Appearance.m3colors.m3error : Appearance.colors.colOnLayer0

    implicitWidth: 228
    implicitHeight: 34
    padding: 0
    leftPadding: 8
    rightPadding: 8
    topPadding: 0
    bottomPadding: 0

    background: Rectangle {
        radius: item.innerRadius
        color: item.down ? Appearance.colors.colLayer1Active
            : (item.hovered ? Appearance.colors.colLayer1Hover : "transparent")
        Behavior on color {
            ColorAnimation { duration: Appearance.dur(120) }
        }
    }

    contentItem: RowLayout {
        spacing: 10
        MaterialSymbol {
            Layout.alignment: Qt.AlignVCenter
            text: item.symbol
            iconSize: 18
            color: item.fg
        }
        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: item.text
            font.pixelSize: Appearance.font.pixelSize.small
            color: item.fg
            elide: Text.ElideRight
        }
        MaterialSymbol {
            visible: item.current
            Layout.alignment: Qt.AlignVCenter
            text: "check"
            iconSize: 18
            color: Appearance.colors.colPrimary
        }
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.PointingHandCursor
    }
}

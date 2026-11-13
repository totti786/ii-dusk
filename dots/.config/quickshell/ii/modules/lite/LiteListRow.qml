import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// One row of a device or network list: icon, two lines of text and an optional trailing icon.
Rectangle {
    id: root

    property string icon: ""
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property bool highlighted: false
    property bool busy: false
    signal clicked()

    implicitHeight: 52
    radius: 16
    color: highlighted ? Appearance.colors.colPrimaryContainer
        : area.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
    Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }

    readonly property color fg: highlighted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer0
    readonly property color fgSub: highlighted ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colSubtext

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 12
        MaterialSymbol {
            text: root.icon
            iconSize: 22
            fill: root.highlighted ? 1 : 0
            color: root.fg
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.title
                color: root.fg
                font.weight: Font.Medium
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                visible: text !== ""
                text: root.subtitle
                color: root.fgSub
                opacity: 0.85
                font.pixelSize: Appearance.font.pixelSize.smallest
                elide: Text.ElideRight
            }
        }
        MaterialSymbol {
            visible: root.trailing !== ""
            text: root.trailing
            iconSize: 18
            color: root.fgSub
            opacity: root.busy ? 0.5 : 1
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

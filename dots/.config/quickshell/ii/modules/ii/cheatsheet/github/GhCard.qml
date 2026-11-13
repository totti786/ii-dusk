import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/// A rounded surface with an icon, a title and a count in its header; the content fills the rest.
Rectangle {
    id: root

    property string title: ""
    property string symbol: ""
    property string badge: ""
    property color accent: Appearance.colors.colPrimary
    property real padding: 18
    default property alias content: body.data
    property alias headerExtras: extras.data

    radius: 26
    color: Appearance.colors.colSurfaceContainer
    implicitHeight: header.implicitHeight + body.childrenRect.height + root.padding * 2 + 12

    RowLayout {
        id: header
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: root.padding }
        spacing: 10
        Rectangle {
            visible: root.symbol !== ""
            implicitWidth: 32
            implicitHeight: 32
            radius: 12
            color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.16)
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 19
                fill: 1
                color: root.accent
            }
        }
        StyledText {
            Layout.fillWidth: true
            text: root.title
            font.pixelSize: Appearance.font.pixelSize.normal
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
            elide: Text.ElideRight
        }
        RowLayout { id: extras; spacing: 6 }
        Rectangle {
            visible: root.badge !== ""
            implicitWidth: badgeText.implicitWidth + 16
            implicitHeight: 24
            radius: 12
            color: Appearance.colors.colSecondaryContainer
            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.badge
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSecondaryContainer
            }
        }
    }

    Item {
        id: body
        anchors { left: parent.left; right: parent.right; top: header.bottom; margins: root.padding; topMargin: 12 }
        height: childrenRect.height
    }
}

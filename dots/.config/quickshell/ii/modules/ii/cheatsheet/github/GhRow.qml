import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/// One line of a list: a glyph, a title with a muted line under it, and a small trailing label.
Rectangle {
    id: root

    property string symbol: ""
    property color tone: Appearance.colors.colPrimary
    property string title: ""
    property string subtitle: ""
    property string trailing: ""
    property string url: ""
    property color trailingColor: Appearance.colors.colOnSurfaceVariant
    signal clicked()

    implicitHeight: 54
    radius: 16
    color: area.containsMouse ? Appearance.colors.colSurfaceContainerHigh : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    RowLayout {
        anchors { fill: parent; leftMargin: 8; rightMargin: 12 }
        spacing: 12
        Rectangle {
            implicitWidth: 34
            implicitHeight: 34
            radius: 17
            color: Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.15)
            MaterialSymbol {
                anchors.centerIn: parent
                text: root.symbol
                iconSize: 18
                fill: 1
                color: root.tone
            }
        }
        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle !== ""
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnSurfaceVariant
            }
        }
        StyledText {
            visible: root.trailing !== ""
            text: root.trailing
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.trailingColor
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.url !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.clicked();
            if (root.url !== "")
                GithubService.open(root.url);
        }
    }
}

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// Back arrow, title and an on/off switch: the top of the Wi-Fi and Bluetooth pages.
RowLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool checked: false
    property bool showSwitch: true
    signal back()
    signal switched()

    spacing: 10

    Rectangle {
        implicitWidth: 38
        implicitHeight: 38
        radius: 19
        color: backArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        MaterialSymbol {
            anchors.centerIn: parent
            text: "arrow_back"
            iconSize: 20
            color: Appearance.colors.colOnLayer0
        }
        MouseArea {
            id: backArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.back()
        }
    }
    ColumnLayout {
        Layout.fillWidth: true
        spacing: 0
        StyledText {
            Layout.fillWidth: true
            text: root.title
            color: Appearance.colors.colOnLayer0
            font.weight: Font.Medium
            elide: Text.ElideRight
        }
        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            text: root.subtitle
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.smaller
            elide: Text.ElideRight
        }
    }
    Rectangle {
        visible: root.showSwitch
        implicitWidth: 46
        implicitHeight: 26
        radius: 13
        color: root.checked ? Appearance.colors.colPrimary : Appearance.colors.colLayer2
        Behavior on color { enabled: !Appearance.reducedMotion; ColorAnimation { duration: Appearance.dur(120) } }
        Rectangle {
            width: 20
            height: 20
            radius: 10
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Appearance.colors.colOnPrimary : Appearance.colors.colSubtext
            Behavior on x { enabled: !Appearance.reducedMotion; NumberAnimation { duration: Appearance.dur(120); easing.type: Easing.OutCubic } }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.switched()
        }
    }
}

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/// One labelled figure of an expanded card.
Rectangle {
    id: root
    property string label: ""
    property string value: ""
    property color valueColor: ClockStyle.colOnBackground

    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: 54
    radius: ClockStyle.radiusNormal
    color: ClockStyle.colSurfaceHighest

    Column {
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 12
        spacing: 2
        StyledText {
            width: parent.width
            text: root.label
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            elide: Text.ElideRight
        }
        StyledText {
            width: parent.width
            text: root.value
            color: root.valueColor
            font.weight: Font.Medium
            font.pixelSize: ClockStyle.textNormal
            elide: Text.ElideRight
        }
    }
}

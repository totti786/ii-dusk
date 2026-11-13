pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets

/// People as pills with an initials badge (the catalog has names, not photos)
ColumnLayout {
    id: root

    property string heading: "Cast"
    property var names: []

    visible: root.names.length > 0
    spacing: 8

    StyledText {
        text: root.heading
        color: Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.larger
        font.weight: Font.DemiBold
    }

    Flow {
        Layout.fillWidth: true
        spacing: 8

        Repeater {
            model: root.names
            delegate: Rectangle {
                id: pill
                required property string modelData
                required property int index
                readonly property var parts: modelData.split(" ").filter(x => x)
                readonly property string initials: (parts[0]?.charAt(0) ?? "") + (parts.length > 1 ? parts[parts.length - 1].charAt(0) : "")
                // A stable tint per name, from the theme's three accent containers
                readonly property color tint: index % 3 === 0 ? Appearance.colors.colPrimaryContainer
                    : index % 3 === 1 ? Appearance.colors.colSecondaryContainer : Appearance.colors.colTertiaryContainer
                readonly property color tintOn: index % 3 === 0 ? Appearance.colors.colOnPrimaryContainer
                    : index % 3 === 1 ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnTertiaryContainer
                implicitWidth: pillRow.implicitWidth + 18
                implicitHeight: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colLayer1

                Row {
                    id: pillRow
                    anchors { verticalCenter: parent.verticalCenter; left: parent.left; leftMargin: 5 }
                    spacing: 9
                    Rectangle {
                        width: 30
                        height: 30
                        radius: Appearance.rounding.full
                        color: pill.tint
                        StyledText {
                            anchors.centerIn: parent
                            text: pill.initials.toUpperCase()
                            color: pill.tintOn
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.DemiBold
                        }
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: pill.modelData
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Header of a title page (movies, shows, anime): backdrop, cover, name, chips and a
 * description, with any action buttons dropped into it as children.
 */
RoundedBox {
    id: root

    property string name: ""
    property string poster: ""
    property string background: ""
    property string description: ""
    property var chips: []
    default property alias actions: actionRow.data

    signal backRequested()

    Layout.fillWidth: true
    Layout.preferredHeight: 230
    radius: Appearance.rounding.verylarge
    color: Appearance.colors.colLayer2
    clip: true

    Image {
        anchors.fill: parent
        source: MediatorService.cachedImage(root.background)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: 1100
        opacity: status === Image.Ready ? 0.55 : 0
        Behavior on opacity {
            NumberAnimation { duration: Appearance.dur(300) }
        }
    }
    Rectangle {
        anchors.fill: parent
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Qt.alpha(Appearance.colors.colLayer1, 0.96) }
            GradientStop { position: 0.7; color: Qt.alpha(Appearance.colors.colLayer1, 0.55) }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    RowLayout {
        anchors { fill: parent; margins: 18 }
        spacing: 18

        RoundedBox {
            Layout.fillHeight: true
            Layout.preferredWidth: height / 1.5
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2
            clip: true
            Image {
                anchors.fill: parent
                source: MediatorService.cachedImage(root.poster)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: 400
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 8

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.name
                color: Appearance.colors.colOnLayer0
                font.pixelSize: 30
                font.weight: Font.DemiBold
            }

            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.chips.filter(x => x)
                    Rectangle {
                        id: chip
                        required property string modelData
                        implicitWidth: chipText.implicitWidth + 18
                        implicitHeight: 26
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colSecondaryContainer
                        StyledText {
                            id: chipText
                            anchors.centerIn: parent
                            text: chip.modelData
                            color: Appearance.colors.colOnSecondaryContainer
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.fillHeight: true
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                text: root.description
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.small
            }

            RowLayout {
                id: actionRow
                spacing: 8
            }
        }
    }

    ClockButton {
        anchors { top: parent.top; right: parent.right; margins: 10 }
        iconOnly: true
        symbol: "arrow_back"
        label: "Back (Esc)"
        variant: "tonal"
        onClicked: root.backRequested()
    }
}

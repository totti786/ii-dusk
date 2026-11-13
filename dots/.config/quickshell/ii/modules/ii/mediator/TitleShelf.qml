pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/// A row of small posters ("More like this"); the keyboard cursor is `cursor`, -1 for none
ColumnLayout {
    id: root

    property string heading: "More like this"
    property var items: []
    property int cursor: -1

    signal activated(var item)

    visible: root.items.length > 0
    spacing: 10

    function show(index): void {
        list.positionViewAtIndex(index, ListView.Contain);
    }

    StyledText {
        text: root.heading
        color: Appearance.colors.colOnLayer0
        font.pixelSize: Appearance.font.pixelSize.larger
        font.weight: Font.DemiBold
    }

    ListView {
        id: list
        WheelScroll {}
        Layout.fillWidth: true
        Layout.preferredHeight: 250
        orientation: ListView.Horizontal
        spacing: 14
        clip: true
        topMargin: 6
        leftMargin: 4
        boundsBehavior: Flickable.StopAtBounds
        model: root.items

        delegate: Item {
            id: card
            required property var modelData
            required property int index
            readonly property bool on: root.cursor === index
            width: 128
            height: ListView.view.height - 6

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                scale: card.on || hover.hovered ? 1.04 : 1
                Behavior on scale {
                    NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic }
                }

                RoundedBox {
                    id: cover
                    width: parent.width
                    height: width * 1.5
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colLayer2
                    Image {
                        anchors.fill: parent
                        source: MediatorService.cachedImage(card.modelData.poster)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 260
                    }
                }
                Rectangle {
                    anchors.fill: cover
                    radius: Appearance.rounding.normal
                    color: "transparent"
                    border.width: card.on ? 3 : 0
                    border.color: Appearance.colors.colPrimary
                }
                StyledText {
                    anchors { left: parent.left; right: parent.right; top: cover.bottom; topMargin: 8 }
                    elide: Text.ElideRight
                    text: card.modelData.name ?? card.modelData.title ?? ""
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                }
                StyledText {
                    anchors { left: parent.left; right: parent.right; top: cover.bottom; topMargin: 28 }
                    elide: Text.ElideRight
                    text: [card.modelData.year, card.modelData.rating ? "★ " + card.modelData.rating : ""].filter(x => x).join(" · ")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
            }

            HoverHandler {
                id: hover
                cursorShape: Qt.PointingHandCursor
            }
            TapHandler {
                onTapped: root.activated(card.modelData)
            }
        }
    }
}

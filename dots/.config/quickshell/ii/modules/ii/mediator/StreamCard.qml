pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One streaming row: provider history or an AniList watching entry. The poster is
 * local data, the rest is plain text, so the card stays cheap in a horizontal list.
 */
Item {
    id: root

    property string poster: ""
    property string title: ""
    property string subtitle: ""
    property string meta: ""
    property string badge: ""
    property string actionIcon: "play_arrow"
    property real fraction: 0
    property bool selected: false

    signal activated()
    signal secondary()

    implicitWidth: 322
    implicitHeight: 126

    readonly property bool hasPoster: root.poster !== ""
    readonly property string posterSource: MediatorService.cachedImage(root.poster)

    RoundedBox {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: area.containsMouse || root.selected
            ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
        Behavior on color {
            ColorAnimation { duration: Appearance.dur(120) }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 12

            RoundedBox {
                Layout.fillHeight: true
                Layout.leftMargin: 10
                Layout.topMargin: 10
                Layout.bottomMargin: 10
                Layout.preferredWidth: 76
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2
                clip: true

                Image {
                    id: posterImage
                    anchors.fill: parent
                    source: root.posterSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 180
                    visible: root.hasPoster && status === Image.Ready
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !posterImage.visible
                    text: (root.title || "?").charAt(0).toUpperCase()
                    color: Appearance.colors.colSubtext
                    font.pixelSize: 28
                    font.weight: Font.DemiBold
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 13
                Layout.bottomMargin: 13
                Layout.rightMargin: 8
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.subtitle
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 4
                        radius: 2
                        visible: root.fraction > 0
                        color: Appearance.colors.colOutlineVariant
                        Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.fraction))
                            height: parent.height
                            radius: 2
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledText {
                        text: root.meta
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        elide: Text.ElideRight
                    }
                }
            }

            RoundedBox {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 12
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: area.containsMouse || root.selected ? 1 : 0.72
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.dur(120) }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.actionIcon
                    fill: 1
                    iconSize: 20
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        // Small state pill over the artwork: "WATCHED", "ANILIST", ...
        Rectangle {
            visible: root.badge !== ""
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.topMargin: 16
            width: badgeText.implicitWidth + 10
            height: 17
            radius: 8.5
            color: Qt.rgba(0, 0, 0, 0.66)
            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.badge
                color: "white"
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                font.letterSpacing: 0.5
            }
        }
    }

    Rectangle {
        anchors.fill: card
        radius: card.radius
        color: "transparent"
        border.width: root.selected ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => mouse.button === Qt.RightButton ? root.secondary() : root.activated()
    }
}

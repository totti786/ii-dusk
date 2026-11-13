pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One cover in a browsing grid (movies, shows, anime). Same shape language as the library's
 * PosterCard: large-radius cover, rating chip, hover lift and play button, name and a status
 * line beneath. `height` follows `width`, so a Flow of these lines up.
 */
Item {
    id: root

    property string poster: ""
    property string name: ""
    property string subtitle: ""
    property string rating: ""
    property real progress: 0
    property bool selected: false
    /// The library already has this title: a small badge says so
    property bool owned: false

    signal activated()

    readonly property real coverWidth: root.width - 16

    height: root.coverWidth * 1.5 + 16 + 10 + 40

    Rectangle {
        id: frame
        anchors.fill: parent
        anchors.margins: 8
        radius: Appearance.rounding.normal
        color: "transparent"
        scale: root.selected || hover.hovered ? 1.035 : 1
        Behavior on scale {
            NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic }
        }

        RoundedBox {
            id: coverBox
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: width * 1.5
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            Image {
                id: image
                anchors.fill: parent
                source: MediatorService.cachedImage(root.poster)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 360
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.dur(220) }
                }
            }

            StyledText {
                anchors.centerIn: parent
                visible: image.status !== Image.Ready
                text: root.name.charAt(0).toUpperCase()
                color: Appearance.colors.colSubtext
                font.pixelSize: 54
                font.weight: Font.DemiBold
            }

            Rectangle {
                visible: root.rating !== ""
                z: 4
                anchors { left: parent.left; top: parent.top; margins: 8 }
                implicitWidth: badge.implicitWidth + 14
                implicitHeight: 24
                radius: Appearance.rounding.full
                color: Qt.rgba(0, 0, 0, 0.62)
                Row {
                    id: badge
                    anchors.centerIn: parent
                    spacing: 3
                    MaterialSymbol {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "star"
                        fill: 1
                        iconSize: 14
                        color: "#ffd166"
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.rating
                        color: "white"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                    }
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 64
                visible: root.progress > 0 || hover.hovered
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 10 }
                height: 4
                radius: 2
                visible: root.progress > 0
                color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle {
                    width: parent.width * root.progress
                    height: parent.height
                    radius: 2
                    color: Appearance.colors.colPrimary
                }
            }

            Rectangle {
                anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                width: 40
                height: 40
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: hover.hovered || root.selected ? 1 : 0
                scale: opacity
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.dur(120) }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    iconSize: 24
                    fill: 1
                    color: Appearance.colors.colOnPrimary
                }
            }
        }

        Rectangle {
            visible: root.owned
            anchors { right: parent.right; top: parent.top; margins: 8 }
            z: 4
            width: 26
            height: 26
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimaryContainer
            MaterialSymbol {
                anchors.centerIn: parent
                text: "video_library"
                iconSize: 15
                fill: 1
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        Rectangle {
            anchors.fill: coverBox
            z: 5
            radius: coverBox.radius
            color: "transparent"
            border.width: root.selected ? 3 : 0
            border.color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            anchors { left: parent.left; right: parent.right; top: coverBox.bottom; topMargin: 10 }
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.name
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }
            StyledText {
                Layout.fillWidth: true
                text: root.subtitle
                elide: Text.ElideRight
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
            }
        }
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
    }
    TapHandler {
        onTapped: root.activated()
    }
}

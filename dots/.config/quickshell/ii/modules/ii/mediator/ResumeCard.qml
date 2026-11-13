pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** One in-progress title: poster, where you stopped, a progress bar and a play button. `title` is a row of `mediator list --json`. */
Item {
    id: root

    required property var title
    property bool selected: false
    property color surface: Appearance.colors.colLayer1
    property color surfaceHover: Appearance.colors.colLayer2

    signal activated()
    signal openRequested()

    readonly property var next: root.title.next ?? null
    // Where you stopped in the episode being resumed; otherwise how much of the title is watched.
    // (Episodes watched alone read 0 for a title you are only partway through its first.)
    readonly property real fraction: {
        const n = root.next;
        if (n?.reason === "resume" && (n.duration ?? 0) > 0)
            return Math.max(0, Math.min(1, n.position / n.duration));
        return root.title.total > 0 ? root.title.watched / root.title.total : 0;
    }
    readonly property string stoppedAt: root.next?.reason === "resume" && (root.next?.position ?? 0) > 0
        ? MediatorService.clock(root.next.position) : ""

    implicitWidth: 330
    implicitHeight: 120

    RoundedBox {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.normal
        color: area.containsMouse || root.selected ? root.surfaceHover : root.surface
        Behavior on color {
            ColorAnimation { duration: Appearance.dur(120) }
        }

        RowLayout {
            anchors.fill: parent
            spacing: 14

            Item {
                Layout.fillHeight: true
                Layout.preferredWidth: 80
                Image {
                    anchors.fill: parent
                    source: MediatorService.posterUrl(root.title.poster)
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 240
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 3

                StyledText {
                    Layout.fillWidth: true
                    text: root.title.display ?? root.title.name ?? ""
                    elide: Text.ElideRight
                    color: Appearance.colors.colOnLayer0
                    font.weight: Font.DemiBold
                    font.pixelSize: Appearance.font.pixelSize.normal
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.next ? root.next.label : ""
                    elide: Text.ElideRight
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 5
                        Layout.alignment: Qt.AlignVCenter
                        radius: 3
                        color: Appearance.colors.colOutlineVariant
                        Rectangle {
                            width: root.fraction > 0 ? Math.max(parent.height, parent.width * root.fraction) : 0
                            height: parent.height
                            radius: 3
                            color: Appearance.colors.colPrimary
                        }
                    }
                    StyledText {
                        // Reserves its width even when empty so every card's track ends at the same place
                        Layout.preferredWidth: 46
                        horizontalAlignment: Text.AlignRight
                        text: root.stoppedAt
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }
            }

            // Play button at the foot of the row, so it never covers the artwork
            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                Layout.rightMargin: 16
                Layout.preferredWidth: 38
                Layout.preferredHeight: 38
                radius: Appearance.rounding.full
                color: Appearance.colors.colPrimary
                opacity: area.containsMouse || root.selected ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.dur(120) }
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "play_arrow"
                    fill: 1
                    iconSize: 24
                    color: Appearance.colors.colOnPrimary
                }
            }
        }
    }

    // Selection ring: outside the clipped card, so the mask never trims it
    Rectangle {
        anchors.fill: card
        radius: Appearance.rounding.normal
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
        onClicked: mouse => mouse.button === Qt.RightButton ? root.openRequested() : root.activated()
    }
}

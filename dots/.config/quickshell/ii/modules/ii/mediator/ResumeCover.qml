pragma ComponentBehavior: Bound

import QtQuick

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/** An in-progress title as a full poster: progress and where you stopped along its foot. `title` is a row of `mediator list --json`. */
Item {
    id: root

    required property var title
    property bool selected: false
    property bool centred: false

    signal activated()
    signal openRequested()

    readonly property var next: root.title.next ?? null
    // Where you stopped in the episode being resumed; otherwise how much of the title is watched
    readonly property real fraction: {
        const n = root.next;
        if (n?.reason === "resume" && (n.duration ?? 0) > 0)
            return Math.max(0, Math.min(1, n.position / n.duration));
        return root.title.total > 0 ? root.title.watched / root.title.total : 0;
    }

    RoundedBox {
        id: card
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer2
        clip: true

        StyledText {
            anchors.centerIn: parent
            visible: image.status !== Image.Ready
            text: (root.title.name ?? "?").charAt(0).toUpperCase()
            color: Appearance.colors.colSubtext
            font.pixelSize: 54
            font.weight: Font.DemiBold
        }

        Image {
            id: image
            anchors.fill: parent
            source: MediatorService.posterUrl(root.title.poster)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
            sourceSize.width: 480
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity {
                NumberAnimation { duration: Appearance.dur(220) }
            }
        }

        SourceTag {
            z: 3
            anchors { right: parent.right; top: parent.top; margins: 8 }
            source: root.title.source ?? "local"
            compact: true
        }

        // Foot fade so the bar reads on any poster
        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: 70
            gradient: Gradient {
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.78) }
            }
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
            height: 5
            radius: 3
            color: Qt.rgba(1, 1, 1, 0.28)
            Rectangle {
                width: root.fraction > 0 ? Math.max(parent.height, parent.width * root.fraction) : 0
                height: parent.height
                radius: 3
                color: Appearance.colors.colPrimary
            }
        }

        Rectangle {
            anchors { right: parent.right; bottom: parent.bottom; rightMargin: 12; bottomMargin: 26 }
            width: 40
            height: 40
            radius: Appearance.rounding.full
            color: Appearance.colors.colPrimary
            opacity: root.centred && (area.containsMouse || root.selected) ? 1 : 0
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

    // Selection ring: outside the clipped card, so the mask never trims it
    Rectangle {
        anchors.fill: card
        radius: Appearance.rounding.large
        color: "transparent"
        border.width: root.selected ? 3 : 0
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

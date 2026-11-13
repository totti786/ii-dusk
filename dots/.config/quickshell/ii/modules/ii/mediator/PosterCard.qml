pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * One title in the grid: poster, progress along its foot, name and a status line beneath.
 * `title` is a row of `mediator list --json`.
 */
Item {
    id: root

    required property var title
    property bool selected: false

    signal activated()
    signal playRequested()

    // Finished episodes plus how far into the one in progress
    readonly property real fraction: {
        const n = root.title.next;
        const part = n?.reason === "resume" && (n.duration ?? 0) > 0 ? Math.min(1, n.position / n.duration) : 0;
        return root.title.total > 0 ? Math.min(1, (root.title.watched + part) / root.title.total) : part;
    }
    readonly property bool hasResume: root.title.next?.reason === "resume"
    readonly property string status: {
        const t = root.title;
        if (t.online)
            return String(t.statusText ?? "");
        if (t.lib === "movies" || t.episodes === 0) {
            if (t.next?.reason === "resume")
                return "Resume";
            return t.watched >= t.total && t.total > 0 ? "Watched" : "Movie";
        }
        if (t.watched >= t.total && t.total > 0)
            return "Watched";
        if (t.next?.reason === "resume")
            return `Resume ${t.next.code}`;
        if (t.watched > 0)
            return `Next ${t.next?.code ?? ""}`;
        return `${t.episodes} episode${t.episodes === 1 ? "" : "s"}`;
    }

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
            id: posterBox
            anchors { left: parent.left; right: parent.right; top: parent.top }
            height: width * 1.5
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer2

            Rectangle {
                visible: (root.title.rating ?? 0) > 0
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
                        text: (root.title.rating ?? 0).toFixed(1)
                        color: "white"
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: Font.Medium
                    }
                }
            }

            SourceTag {
                z: 4
                anchors { right: parent.right; top: parent.top; margins: 8 }
                source: root.title.source ?? "local"
            }

            Image {
                id: image
                anchors.fill: parent
                source: MediatorService.posterUrl(root.title.poster)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: 360
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: Appearance.dur(220) }
                }
            }

            // No artwork yet: the initial on a flat tile
            StyledText {
                anchors.centerIn: parent
                visible: image.status !== Image.Ready
                text: (root.title.name ?? "?").charAt(0).toUpperCase()
                color: Appearance.colors.colSubtext
                font.pixelSize: 54
                font.weight: Font.DemiBold
            }

            // Foot fade so the progress bar and play button read on any poster
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 64
                visible: root.fraction > 0 || root.hasResume || hover.hovered
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 1; color: Qt.rgba(0, 0, 0, 0.7) }
                }
            }

            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12 }
                height: 5
                radius: 3
                visible: root.fraction > 0 || root.hasResume
                color: Qt.rgba(1, 1, 1, 0.25)
                Rectangle {
                    width: Math.max(parent.height, parent.width * root.fraction)
                    height: parent.height
                    radius: 3
                    color: Appearance.colors.colPrimary
                }
            }

            Rectangle {
                id: playButton
                anchors { right: parent.right; bottom: parent.bottom; rightMargin: 14; bottomMargin: 28 }
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
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.playRequested()
                }
            }
        }

        // Selection ring: outside the clipped box, so the mask never trims it
        Rectangle {
            anchors.fill: posterBox
            z: 5
            radius: posterBox.radius
            color: "transparent"
            border.width: root.selected ? 3 : 0
            border.color: Appearance.colors.colPrimary
        }

        ColumnLayout {
            anchors { left: parent.left; right: parent.right; top: posterBox.bottom; topMargin: 10 }
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.title.display ?? root.title.name
                elide: Text.ElideRight
                maximumLineCount: 1
                color: Appearance.colors.colOnLayer0
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.Medium
            }
            StyledText {
                Layout.fillWidth: true
                text: root.status
                elide: Text.ElideRight
                color: root.hasResume ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
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

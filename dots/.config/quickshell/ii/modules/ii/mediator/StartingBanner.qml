pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Shown while an episode or movie is being opened. It names what is starting (poster, title,
 * episode code) and walks through the steps so a slow start never looks like a dead click:
 * finding a source, connecting, opening the player. The steps follow the time spent, and the
 * backend's own message wins while it has one. After a while it says the source is slow.
 */
RoundedBox {
    id: root

    readonly property bool resolving: MediatorService.streamResolving
    readonly property bool active: root.resolving || StremioService.starting || AnimeBrowseService.starting
    readonly property string label: String(MediatorService.streamQuery ?? "").trim()

    // "tt0903747:1:2" -> "S01E02"; anime ids are plain numbers and have no code
    readonly property string code: {
        const m = String(MediatorService.providerPendingEpisodeId ?? "").match(/^tt\d+:(\d+):(\d+)$/);
        return m ? "S" + m[1].padStart(2, "0") + "E" + m[2].padStart(2, "0") : "";
    }
    readonly property string poster: {
        const url = StremioService.starting ? StremioService.title?.poster : AnimeBrowseService.chosen?.poster;
        return String(url ?? "");
    }

    property int elapsed: 0   // seconds since it appeared
    readonly property var steps: [
        { "text": Translation.tr("Finding a source"), "icon": "travel_explore" },
        { "text": Translation.tr("Connecting to the stream"), "icon": "cloud_sync" },
        { "text": Translation.tr("Opening the player"), "icon": "play_circle" }
    ]
    readonly property int stepIndex: root.elapsed < 3 ? 0 : root.elapsed < 7 ? 1 : 2
    readonly property string detail: {
        if (root.elapsed >= 12)
            return Translation.tr("This source is slow today. Still working…");
        if (root.resolving && MediatorService.streamMessage !== "")
            return MediatorService.streamMessage;
        return root.steps[root.stepIndex].text + "…";
    }

    onActiveChanged: root.elapsed = 0
    Timer {
        interval: 1000
        repeat: true
        running: root.active
        onTriggered: root.elapsed += 1
    }

    visible: root.active
    implicitHeight: 84
    radius: Appearance.rounding.large
    color: Appearance.colors.colPrimaryContainer

    RowLayout {
        anchors { fill: parent; leftMargin: 12; rightMargin: 16; topMargin: 10; bottomMargin: 14 }
        spacing: 14

        // Poster, or the loading shape when there is none yet
        Item {
            Layout.preferredWidth: 42
            Layout.fillHeight: true

            RoundedBox {
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.1)
                visible: root.poster !== ""

                Image {
                    anchors.fill: parent
                    source: root.poster
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                }
            }

            MaterialLoadingIndicator {
                anchors.centerIn: parent
                visible: root.poster === ""
                implicitSize: 38
                loading: root.visible
                color: Appearance.colors.colPrimary
                shapeColor: Appearance.colors.colOnPrimary
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: root.label !== "" ? root.label : Translation.tr("Starting playback")
                color: Appearance.colors.colOnPrimaryContainer
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
            }

            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                text: (root.code !== "" ? root.code + "  ·  " : "") + root.detail
                color: Appearance.colors.colOnPrimaryContainer
                opacity: 0.8
                font.pixelSize: Appearance.font.pixelSize.small
            }
        }

        // Three dots for the three steps: done, current, still to come
        Row {
            spacing: 6
            Layout.alignment: Qt.AlignVCenter
            Repeater {
                model: root.steps

                Rectangle {
                    id: dot
                    required property int index
                    width: dot.index === root.stepIndex ? 18 : 6
                    height: 6
                    radius: 3
                    color: Appearance.colors.colPrimary
                    opacity: dot.index <= root.stepIndex ? 1 : 0.25
                    Behavior on width {
                        enabled: !Appearance.reducedMotion
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 4
        color: Qt.alpha(Appearance.colors.colOnPrimaryContainer, 0.15)
        clip: true
        Rectangle {
            id: runner
            width: parent.width * 0.3
            height: parent.height
            radius: 2
            color: Appearance.colors.colPrimary
            SequentialAnimation on x {
                loops: Animation.Infinite
                running: (root.visible) && !Appearance.motionOff
                NumberAnimation { from: -runner.width; to: runner.parent.width; duration: 1200; easing.type: Easing.InOutQuad }
            }
        }
    }
}

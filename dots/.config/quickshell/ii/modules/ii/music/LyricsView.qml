pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Effects

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Lyrics that follow the song, in the Material 3 Expressive vocabulary.
 *
 * The line being sung sits on a tonal pill that glides to the next line; its type gains
 * weight instead of changing size. Lines fade with distance from it and the top and bottom
 * dissolve. Clicking a line seeks to it; scrolling by hand pauses following for a few seconds.
 * Unsynced text is a plain, readable page.
 */
Item {
    id: root

    property color accent: ClockStyle.colPrimary
    readonly property var lines: MusicService.lyrics.lines ?? []
    readonly property bool synced: MusicService.lyrics.synced ?? false
    readonly property int current: MusicService.lyricIndex
    property bool userScrolling: false

    function followTarget(): void {
        if (!root.synced || root.userScrolling || root.current < 0)
            return;
        const item = list.itemAtIndex(root.current);
        if (!item)
            return;
        const target = Math.max(-list.topMargin, Math.min(list.contentHeight - list.height + list.bottomMargin,
            item.y + item.height / 2 - list.height / 2));
        follow.stop();
        follow.from = list.contentY;
        follow.to = target;
        follow.start();
    }

    Connections {
        target: MusicService
        function onLyricIndexChanged() { root.followTarget(); }
    }
    onLinesChanged: Qt.callLater(root.followTarget)
    onSyncedChanged: Qt.callLater(root.followTarget)

    NumberAnimation {
        id: follow
        target: list
        property: "contentY"
        duration: 560
        easing.type: Easing.OutCubic
    }

    Timer {
        id: resume
        interval: 4000
        onTriggered: { root.userScrolling = false; root.followTarget(); }
    }

    ClockEmptyState {
        anchors.centerIn: parent
        visible: root.lines.length === 0
        symbol: MusicService.lyricsLoading ? "hourglass_top" : "lyrics"
        title: MusicService.lyricsLoading ? Translation.tr("Finding lyrics…")
            : MusicService.hasTrack ? Translation.tr("No lyrics for this song") : Translation.tr("Nothing playing")
    }

    Item {
        id: viewport
        anchors.fill: parent
        visible: root.lines.length > 0
        layer.enabled: root.synced
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: fade
        }

        ListView {
            id: list
            WheelScroll {}
            anchors.fill: parent
            clip: true
            model: root.lines
            cacheBuffer: 200000
            boundsBehavior: Flickable.StopAtBounds
            topMargin: root.synced ? height * 0.38 : 24
            bottomMargin: root.synced ? height * 0.44 : 24
            spacing: root.synced ? 6 : 2
            ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

            onMovementStarted: { root.userScrolling = true; follow.stop(); resume.restart(); }
            onMovementEnded: resume.restart()

            delegate: Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool active: root.synced && index === root.current
                readonly property int distance: root.synced && root.current >= 0 ? Math.abs(index - root.current) : 0
                property real boldness: row.active ? 1 : 0
                Behavior on boldness { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                width: ListView.view.width
                height: lineText.implicitHeight + (root.synced ? 28 : 4)

                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    radius: 20
                    color: MusicTone.container
                    opacity: row.active ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                }

                StyledText {
                    id: lineText
                    anchors.verticalCenter: parent.verticalCenter
                    x: root.synced ? 16 : 8
                    width: parent.width - x * 2
                    text: row.modelData.text.length > 0 ? row.modelData.text : "♪"
                    wrapMode: Text.Wrap
                    font.variableAxes: ({ "wght": root.synced ? Math.round(430 + 340 * row.boldness) : 480 })
                    font.pixelSize: root.synced ? 26 : 18
                    color: row.active ? MusicTone.containerContent : MusicTone.contentVariant
                    opacity: !root.synced ? 0.9
                        : row.active ? 1 : Math.max(0.2, 0.62 - row.distance * 0.12)
                    Behavior on opacity { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.synced
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        MusicService.seek(row.modelData.t);
                        root.userScrolling = false;
                    }
                }
            }
        }
    }

    Rectangle {
        id: fade
        anchors.fill: parent
        visible: false
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Vertical
            GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
            GradientStop { position: 0.16; color: Qt.rgba(0, 0, 0, 1) }
            GradientStop { position: 0.84; color: Qt.rgba(0, 0, 0, 1) }
            GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
        }
    }
}

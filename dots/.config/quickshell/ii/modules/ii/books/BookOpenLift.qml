import QtQuick

import qs.services
import qs.modules.common
import qs.modules.ii.clock.components

/**
 * Opening a book: the cover is taken off the shelf, carried to the middle of the room, and
 * swung open on its spine before the viewer takes over. It only plays over the library; the
 * book itself is opened by whoever listens to `finished`.
 */
Item {
    id: root

    property string source: ""
    property string title: ""
    property rect origin: Qt.rect(0, 0, 0, 0)
    readonly property bool running: root.visible

    /// Emitted as the animation starts, so the viewer loads while it plays.
    signal started()
    signal finished()

    visible: false
    z: 40

    function play(src: string, ttl: string, from: rect): void {
        root.source = src;
        root.title = ttl;
        root.origin = from;
        const h = Math.min(root.height * 0.6, 520);
        card.x = from.x;
        card.y = from.y;
        card.width = from.width;
        card.height = from.height;
        card.opacity = 1;
        card.scale = 1;
        shadow.opacity = 0.35;
        scrim.opacity = 0;
        lift.targetW = h * 0.68;
        lift.targetH = h;
        lift.targetX = (root.width - h * 0.68) / 2;
        lift.targetY = (root.height - h) / 2;
        root.visible = true;
        anim.restart();
        root.started();
    }

    // Nothing behind the lift takes a click while it plays.
    MouseArea { anchors.fill: parent }

    Rectangle {
        id: scrim
        anchors.fill: parent
        color: ClockStyle.colScrim
        opacity: 0
    }

    Item {
        id: lift
        property real targetX: 0
        property real targetY: 0
        property real targetW: 0
        property real targetH: 0
    }

    Item {
        id: card
        transformOrigin: Item.Center

        Rectangle {
            id: shadow
            anchors.fill: parent
            anchors.topMargin: 18
            anchors.bottomMargin: -18
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            radius: 24
            color: "#000000"
            opacity: 0.35
        }

        BookCover {
            anchors.fill: parent
            source: root.source
            title: root.title
            format: ""
            radius: 24
        }
    }

    // One continuous motion: the cover settles in the middle while the room dims, then
    // pushes toward the viewer and dissolves as the reader takes the screen.
    SequentialAnimation {
        id: anim
        ParallelAnimation {
            NumberAnimation { target: scrim; property: "opacity"; to: 0.7; duration: Appearance.dur(240); easing.type: Easing.OutCubic }
            NumberAnimation { target: card; property: "x"; to: lift.targetX; duration: Appearance.dur(260); easing.type: Easing.OutQuint }
            NumberAnimation { target: card; property: "y"; to: lift.targetY; duration: Appearance.dur(260); easing.type: Easing.OutQuint }
            NumberAnimation { target: card; property: "width"; to: lift.targetW; duration: Appearance.dur(260); easing.type: Easing.OutQuint }
            NumberAnimation { target: card; property: "height"; to: lift.targetH; duration: Appearance.dur(260); easing.type: Easing.OutQuint }
        }
        PauseAnimation { duration: Appearance.dur(20) }
        ParallelAnimation {
            NumberAnimation { target: card; property: "scale"; to: 1.28; duration: Appearance.dur(200); easing.type: Easing.InCubic }
            NumberAnimation { target: card; property: "opacity"; to: 0; duration: Appearance.dur(200); easing.type: Easing.InCubic }
            NumberAnimation { target: scrim; property: "opacity"; to: 0.92; duration: Appearance.dur(200); easing.type: Easing.InQuad }
        }
        ScriptAction {
            script: {
                root.visible = false;
                root.finished();
            }
        }
    }
}

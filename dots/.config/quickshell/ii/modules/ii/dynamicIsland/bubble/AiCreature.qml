pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.modules.common

/**
 * The AI bubble's face: two eyes that follow the pointer, a body that leans after it.
 *
 *   resting    slow blinks; after a few minutes without the pointer moving, sleepy lids
 *   working    wide round eyes, glancing about as if reading
 *   attention  a hop, eyes locked on the pointer
 *
 * With `personality` on (the voice orb only), `mood` adds a few more faces, all made of
 * the same two eyes by changing their shape, tilt and timing:
 *
 *   startled   tall round eyes, one pop, a flick up toward where notifications appear
 *   delighted  short wide eyes tilted up at the outside, after something was done for you
 *   curious    wider eyes, a slow head tilt and wandering glances while it looks at the screen
 *   worried    low eyes tilted down at the outside, on a nearly empty battery
 *   night      drowsy sooner and heavier lids, in the small hours
 *   squint     narrow eyes once a turn has taken a while (derived here, not a mood)
 *
 * The pointer comes from CursorGaze, which polls only while a creature is watching.
 */
Item {
    id: root

    required property real diameter
    property bool working: false
    property bool attention: false
    /** Voice states, for the companion orb: the eyes swell with `level` (0 to 1). */
    property bool listening: false
    property bool speaking: false
    property bool error: false
    property real level: 0
    /** Off for the island bubble: the extra faces belong to the orb. */
    property bool personality: false
    property string mood: ""
    property color color: Appearance.colors.colPrimary
    /** Off: the eyes sit still and nothing polls. */
    property bool live: true
    /** On: the eyes follow `aimX`/`aimY` (a unit-ish vector) instead of the pointer. */
    property bool manualGaze: false
    /** Eyes closed (asleep). */
    property bool shut: false
    property real aimX: 0
    property real aimY: 0
    onManualGazeChanged: root.aim()
    onAimXChanged: if (manualGaze) root.aim()
    onAimYChanged: if (manualGaze) root.aim()

    readonly property bool still: !Config.options.appearance.reduceMotion
    readonly property string face: root.personality && !root.error ? root.mood : ""
    property bool longWork: false
    readonly property bool squint: root.personality && root.working && root.longWork && root.face === ""
    readonly property bool sleepy: !root.working && !root.attention && !root.listening
        && !root.speaking && !root.error
        && CursorGaze.moves >= 0 && (root.nowMs - CursorGaze.lastMoved) > (root.face === "night" ? 45000 : 180000)
    property double nowMs: Date.now()

    property real gazeX: 0
    property real gazeY: 0
    property bool blinking: false
    property real wander: 0

    implicitWidth: diameter
    implicitHeight: diameter

    readonly property var monitor: {
        const w = root.QsWindow.window;
        return w && w.screen ? Hyprland.monitorFor(w.screen) : null;
    }

    function aim() {
        if (root.manualGaze) {
            root.gazeX = root.aimX;
            root.gazeY = root.aimY;
            return;
        }
        const mon = root.monitor?.lastIpcObject;
        const c = root.mapToItem(null, root.width / 2, root.height / 2);
        const dx = CursorGaze.x - ((mon?.x ?? 0) + c.x);
        const dy = CursorGaze.y - ((mon?.y ?? 0) + c.y);
        const len = Math.max(1, Math.hypot(dx, dy));
        // Full deflection a short way off, easing to none right on top of it.
        const k = Math.min(1, len / 160);
        root.gazeX = dx / len * k;
        root.gazeY = dy / len * k;
    }

    // `visible` says nothing about the window: a hidden or locked-away one still counts.
    readonly property bool watching: root.live && root.visible && root.still
        && (root.QsWindow.window?.visible ?? true)
    property bool counted: false
    function syncWatch() {
        if (root.counted === root.watching) return;
        root.counted = root.watching;
        if (root.counted) CursorGaze.watch(); else CursorGaze.unwatch();
    }
    onWatchingChanged: root.syncWatch()
    Component.onCompleted: root.syncWatch()
    Component.onDestruction: if (root.counted) CursorGaze.unwatch()

    Connections {
        target: CursorGaze
        enabled: root.watching
        function onMovesChanged() { root.aim(); }
    }

    // A turn that takes a while earns a squint.
    Timer {
        interval: 6000
        running: root.personality && root.working
        onRunningChanged: if (!running) root.longWork = false
        onTriggered: root.longWork = true
    }
    onFaceChanged: if (root.face === "startled" && root.watching) pop.restart()

    Timer {
        interval: root.face === "night" || root.face === "worried" ? 5200 : 3600; repeat: true; running: root.watching
        onTriggered: {
            root.nowMs = Date.now();
            root.blinking = true;
            blinkEnd.restart();
        }
    }
    Timer { id: blinkEnd; interval: 140; onTriggered: root.blinking = false }

    // Working: eyes dart about, unless the pointer is the thing being watched.
    Timer {
        interval: 700; repeat: true; running: root.watching && (root.working || root.face === "curious") && !root.attention
        onTriggered: root.wander = (Math.random() * 2 - 1) * 0.6
    }

    readonly property real lookX: root.face === "startled" ? 0.7
        : root.attention ? root.gazeX
        : root.working || root.face === "curious" ? root.gazeX * 0.4 + root.wander : root.gazeX
    readonly property real lookY: root.face === "startled" ? -0.7
        : root.attention ? root.gazeY
        : root.working || root.face === "curious" ? root.gazeY * 0.4 : root.gazeY

    // The whole creature, which is what leans and hops.
    Item {
        id: body
        width: root.diameter
        height: root.diameter
        x: root.lookX * root.diameter * 0.05
        y: root.lookY * root.diameter * 0.05
        Behavior on x { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        Behavior on y { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

        // The pop of a flinch, once.
        SequentialAnimation {
            id: pop
            NumberAnimation { target: body; property: "scale"; to: 1.14; duration: 90; easing.type: Easing.OutQuad }
            NumberAnimation { target: body; property: "scale"; to: 1.0; duration: 240; easing.type: Easing.OutBack }
        }
        // A slow head tilt while it looks at something.
        SequentialAnimation on rotation {
            running: root.face === "curious" && root.still
            loops: Animation.Infinite
            NumberAnimation { to: 5; duration: 1100; easing.type: Easing.InOutSine }
            NumberAnimation { to: -3; duration: 1500; easing.type: Easing.InOutSine }
            onRunningChanged: if (!running) body.rotation = 0
        }
        SequentialAnimation on scale {
            running: root.attention && root.still
            loops: Animation.Infinite
            NumberAnimation { to: 1.12; duration: 220; easing.type: Easing.OutQuad }
            NumberAnimation { to: 1.0; duration: 260; easing.type: Easing.InQuad }
            PauseAnimation { duration: 900 }
        }

        Row {
            anchors.centerIn: parent
            spacing: Math.round(root.diameter * 0.12)
            Repeater {
                model: 2
                delegate: Item {
                    id: eye
                    required property int index
                    readonly property real eyeW: Math.round(root.diameter * (
                        root.face === "delighted" ? 0.22 : root.face === "startled" ? 0.2
                        : root.face === "curious" ? 0.19 : root.squint ? 0.18
                        : root.working || root.listening ? 0.2 : 0.15))
                    readonly property real eyeH: (root.blinking || root.shut) ? 3
                        : root.error ? Math.round(root.diameter * 0.1)
                        : root.face === "startled" ? Math.round(root.diameter * 0.38)
                        : root.face === "delighted" ? Math.round(root.diameter * 0.1)
                        : root.face === "curious" ? Math.round(root.diameter * 0.3)
                        : root.face === "worried" ? Math.round(root.diameter * 0.22)
                        : root.squint ? Math.round(root.diameter * 0.1)
                        : root.face === "night" && !root.working && !root.listening && !root.speaking
                            ? Math.round(root.diameter * 0.18)
                        : root.sleepy ? Math.round(root.diameter * 0.12)
                        : root.working ? eyeW
                        : root.listening ? Math.round(root.diameter * (0.26 + 0.14 * root.level))
                        : root.speaking ? Math.round(root.diameter * (0.2 + 0.16 * root.level))
                        : Math.round(root.diameter * 0.3)
                    width: eyeW
                    height: Math.round(root.diameter * 0.3)
                    Rectangle {
                        anchors.centerIn: parent
                        // Outer corners lift when pleased and sag when worried.
                        rotation: root.face === "delighted" ? (eye.index === 0 ? -10 : 10)
                            : root.face === "worried" ? (eye.index === 0 ? 10 : -10) : 0
                        Behavior on rotation { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        // Eyes lead the body: they shift further than it leans.
                        anchors.horizontalCenterOffset: root.lookX * root.diameter * 0.07
                        anchors.verticalCenterOffset: root.lookY * root.diameter * 0.06
                            + (root.sleepy ? root.diameter * 0.03 : 0)
                        width: eye.eyeW
                        height: eye.eyeH
                        radius: Math.min(width, height) / 2
                        color: root.color
                        Behavior on anchors.horizontalCenterOffset { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 90; easing.type: Easing.OutCubic } }
                        Behavior on height { NumberAnimation { duration: 120 } }
                        Behavior on width { NumberAnimation { duration: 120 } }
                    }
                }
            }
        }
    }
}

pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.bubble

/**
 * A small kitten that keeps the orb company. Same material as the orb: a soft wobbling
 * gradient silhouette with the orb's two eyes, plus ears, paws and whiskers. Click to pet it.
 *
 *   idle       slow breathing, ears twitch now and then
 *   listening  ears up
 *   thinking   eyes dart about like the orb's
 *   petted     a hop, a purr wobble and a heart
 */
Item {
    id: root
    /** Which way it faces: 1 sits on the orb's right, -1 on its left. */
    property int side: 1
    property real time: 0
    /** Tucked behind the orb (while the controls are fanned out). */
    property bool hidden: false
    /** 1 when there is room below the orb, -1 near the bottom edge. */
    property real downward: 1
    /** The orb's centre and the window size, in the window's coordinates. */
    property real orbX: 0
    property real orbY: 0
    property real areaWidth: 1920
    property real areaHeight: 1080
    /** Other things worth a look: [{x, y}] (the small orbs). */
    property var interests: []
    /** Where the orb's control buttons are while they are fanned out ([{x, y}] from the orb's centre), else []. */
    property var fan: []
    /** Other things drawn near the orb it must not stand on (small orbs, labels, approval buttons):
     *  [{x, y, w, h}] as offsets from the orb's centre. */
    property var obstacles: []
    signal moved()
    /** The kitten is playing with the orb: the orb looks at it, wears `orbMood`, and gets poked. */
    property bool withOrb: false
    property string orbMood: ""
    /** In front of the orb (sitting on it) rather than tucked behind. */
    property bool inFront: false
    z: inFront ? 2 : 0
    /** A poke at the orb: direction (dx, dy) and power. */
    signal poke(real dx, real dy, real power)

    readonly property bool reduced: AiCompanionUi.reducedMotion
    readonly property string phase: AiCompanionUi.phase
    readonly property bool busy: ["thinking", "transcribing", "preparing", "reading-files"].includes(root.phase)
    readonly property bool alert: root.phase === "attention" || root.phase === "error"
    readonly property bool listening: root.phase === "listening"
    property real purr: 0       // 0..1, decays after a pet
    property real hop: 0        // px lifted
    property real earTwitch: 0  // 0..1

    readonly property color toneA: Appearance.colors.colSecondary
    readonly property color toneB: Appearance.colors.colTertiary
    readonly property color ink: Appearance.colors.colOnSecondary

    width: 68; height: 64
    opacity: root.hidden ? 0 : 1
    scale: root.hidden ? .4 : 1
    Behavior on opacity { enabled: !root.reduced; NumberAnimation { duration: 160 } }
    Behavior on scale { enabled: !root.reduced; NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
    // Body language: squash (crouch, stretch, curl up), tilt and a wiggle, all about the feet.
    property real squash: 0
    property real tilt: 0
    property real wiggle: 0
    property real leap: 0
    Behavior on squash { enabled: !root.reduced; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on tilt { enabled: !root.reduced; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    transform: [
        Scale { origin.x: root.width / 2; origin.y: root.height * .88; xScale: 1 + root.squash * .16; yScale: 1 - root.squash * .22 },
        Rotation { origin.x: root.width / 2; origin.y: root.height * .88; angle: root.tilt + root.wiggle },
        Translate { y: -(root.hop + root.stride + root.leap) }
    ]

    onTimeChanged: canvas.requestPaint()
    onPurrChanged: canvas.requestPaint()
    onEarTwitchChanged: canvas.requestPaint()
    onSideChanged: { canvas.requestPaint(); if (!walking) home(); }
    onToneAChanged: canvas.requestPaint()
    onToneBChanged: canvas.requestPaint()

    function pet() {
        stopActivity();
        if (root.reduced) { purr = 1; purrFade.restart(); return; }
        petAnim.restart();
        purrFade.restart();
        heart.restart();
    }
    SequentialAnimation {
        id: petAnim
        NumberAnimation { target: root; property: "hop"; to: 9; duration: 110; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "hop"; to: 0; duration: 260; easing.type: Easing.OutBounce }
    }
    SequentialAnimation {
        id: purrFade
        PropertyAction { target: root; property: "purr"; value: 1 }
        NumberAnimation { target: root; property: "purr"; to: 0; duration: 2200; easing.type: Easing.InQuad }
    }
    // An occasional ear flick.
    Timer {
        interval: 4200; repeat: true; running: !root.reduced && root.visible && !root.hidden
        onTriggered: { interval = 3000 + Math.random() * 5000; twitch.restart(); }
    }
    SequentialAnimation {
        id: twitch
        NumberAnimation { target: root; property: "earTwitch"; to: 1; duration: 70 }
        NumberAnimation { target: root; property: "earTwitch"; to: 0; duration: 140 }
        NumberAnimation { target: root; property: "earTwitch"; to: .7; duration: 70 }
        NumberAnimation { target: root; property: "earTwitch"; to: 0; duration: 160 }
    }

    // --- Wandering: it sits near the orb, but strolls to a new spot every so often.
    // Offsets are from the orb's centre, so it follows when the orb is dragged.
    property real fromX: root.side * 74
    property real fromY: root.downward * 40
    property real toX: fromX
    property real toY: fromY
    property real walk: 1
    readonly property bool walking: walkAnim.running
    property bool zooming: false
    property real zoomAngle: 0
    property real zoomR: 84
    readonly property real offX: zooming ? Math.cos(zoomAngle) * zoomR : fromX + (toX - fromX) * walk
    readonly property real offY: zooming ? Math.sin(zoomAngle) * zoomR : fromY + (toY - fromY) * walk
    // Small steps while it travels.
    readonly property real stride: root.zooming ? Math.abs(Math.sin(root.zoomAngle * 7)) * 4 : root.walking ? Math.abs(Math.sin(root.walk * Math.hypot(toX - fromX, toY - fromY) / 11 * Math.PI)) * 3.5 : 0
    x: Math.max(width / 2, Math.min(root.areaWidth - width / 2, root.orbX + root.offX)) - width / 2
    y: Math.max(height / 2 + 6, Math.min(root.areaHeight - height / 2, root.orbY + root.offY)) - height / 2
    readonly property real centerX: x + width / 2
    readonly property real centerY: y + height / 2
    NumberAnimation {
        id: walkAnim
        target: root; property: "walk"; from: 0; to: 1
        easing.type: Easing.InOutSine
        onFinished: { root.fromX = root.toX; root.fromY = root.toY; root.walk = 1; }
    }
    function goTo(dx, dy, dur) {
        if (root.reduced) { fromX = toX = dx; fromY = toY = dy; walk = 1; return; }
        // Start from wherever it is now, in case a walk was cut short.
        const cx = offX, cy = offY;
        walkAnim.stop();
        fromX = cx; fromY = cy; toX = dx; toY = dy;
        walkAnim.duration = dur ?? (500 + Math.hypot(dx - cx, dy - cy) * 11);
        walkAnim.restart();
    }
    // Is this offset from the orb a good place to stand: on screen, and clear of the control
    // buttons, the small orbs, the labels and the approval buttons?
    function clear(dx, dy) {
        const ax = root.orbX + dx, ay = root.orbY + dy;
        if (ax < 40 || ax > root.areaWidth - 40 || ay < 56 || ay > root.areaHeight - 40) return false;
        for (const o of root.obstacles)
            if (dx + 30 > o.x - 4 && dx - 30 < o.x + o.w + 4 && dy + 28 > o.y - 4 && dy - 26 < o.y + o.h + 4) return false;
        for (const b of root.fan)
            if (Math.abs(dx - b.x) < 56 && Math.abs(dy - b.y) < 54) return false;
        return true;
    }
    // The clear spot nearest to a wanted one, searching outward around the orb.
    function nearestClear(wx, wy) {
        if (root.clear(wx, wy)) return {x: wx, y: wy};
        let best = null, bestDist = 1e9;
        for (const rad of [74, 88, 102]) {
            for (let deg = 0; deg < 360; deg += 10) {
                const a = deg * Math.PI / 180;
                const dx = Math.cos(a) * rad, dy = Math.sin(a) * rad;
                if (!root.clear(dx, dy)) continue;
                const d = Math.hypot(dx - wx, dy - wy);
                if (d < bestDist) { bestDist = d; best = {x: dx, y: dy}; }
            }
        }
        return best;
    }
    // While the buttons are out: the clear spot farthest from them.
    function avoid() {
        let best = null, bestScore = -1;
        for (let deg = 0; deg < 360; deg += 12) {
            for (const rad of [78, 92]) {
                const a = deg * Math.PI / 180;
                const dx = Math.cos(a) * rad, dy = Math.sin(a) * rad;
                if (!root.clear(dx, dy)) continue;
                let nearest = 1e9;
                for (const b of root.fan) nearest = Math.min(nearest, Math.hypot(dx - b.x, dy - b.y));
                const score = Math.min(nearest, 140) - Math.hypot(dx - root.offX, dy - root.offY) * .05;
                if (score > bestScore) { bestScore = score; best = {x: dx, y: dy}; }
            }
        }
        if (best) root.goTo(best.x, best.y);
    }
    onFanChanged: { if (fan.length > 0) avoid(); else if (!hidden) home(); }
    function home() {
        const spot = root.nearestClear(root.side * 74, root.downward * 40);
        if (spot) root.goTo(spot.x, spot.y);
    }
    function pickSpot() {
        for (let tries = 0; tries < 14; tries++) {
            const sgn = Math.random() < .3 ? -root.side : root.side;
            const ang = (-35 + Math.random() * 105) * Math.PI / 180;
            const rad = 66 + Math.random() * 44;
            const dx = sgn * Math.cos(ang) * rad, dy = root.downward * Math.sin(ang) * rad;
            if (root.clear(dx, dy)) return {x: dx, y: dy};
        }
        return null;
    }
    // Something moved into its spot (a small orb appeared, a label or the approval buttons came
    // up): it shuffles over rather than standing on it.
    onObstaclesChanged: {
        if (hidden || !visible || !clear(toX, toY)) {
            if (hidden || !visible) return;
            if (fan.length > 0) avoid(); else home();
        }
    }
    onDownwardChanged: if (!walking) home()
    // Calm for the orb's sake: it only wanders while nothing is going on.
    readonly property bool calm: !root.hidden && root.fan.length === 0 && !root.busy && !root.listening && root.phase !== "speaking" && !root.alert && root.purr < .05
    Timer {
        id: wander
        interval: 9000; repeat: true
        running: root.visible && root.calm && !root.reduced
        onTriggered: {
            interval = 7000 + Math.random() * 9000;
            if (root.walking || root.activity !== "") return;
            // Mostly a new spot; now and then back to its usual place beside the orb.
            if (Math.random() < .25) { root.home(); return; }
            const spot = root.pickSpot();
            if (spot) root.goTo(spot.x, spot.y);
        }
    }
    // Something happens: it hurries back to the orb's side.
    onCalmChanged: { if (!calm) stopActivity(); if (!calm && !hidden && fan.length === 0) home(); }

    // --- Looking: the orb, the pointer, the small orbs, or just somewhere else.
    property string gazeMode: "orb"
    property real glanceX: 0
    property real glanceY: 0
    function toward(px, py) {
        const dx = px - root.centerX, dy = py - root.centerY;
        const len = Math.max(1, Math.hypot(dx, dy));
        return {x: dx / len * Math.min(1, len / 60), y: dy / len * Math.min(1, len / 60)};
    }
    readonly property var aimAt: {
        root.time;  // follow the orb and the small orbs as they move
        if (root.gazeMode === "orb") return root.toward(root.orbX, root.orbY);
        if (root.gazeMode === "interest" && root.interests.length > 0) {
            const o = root.interests[root.glanceIndex % root.interests.length];
            return root.toward(o.x, o.y);
        }
        return {x: root.glanceX, y: root.glanceY};
    }
    property int glanceIndex: 0
    function lookSomewhere() {
        if (root.activity !== "") return;
        if (root.busy || root.listening || root.phase === "speaking" || root.purr > .05) { gazeMode = "orb"; return; }
        const r = Math.random();
        if (r < .34) gazeMode = "orb";
        else if (r < .6) gazeMode = "cursor";
        else if (r < .8 && root.interests.length > 0) { gazeMode = "interest"; glanceIndex = Math.floor(Math.random() * 8); }
        else {
            gazeMode = "away";
            const a = Math.random() * Math.PI * 2;
            glanceX = Math.cos(a) * .9; glanceY = Math.sin(a) * .7 - .2;
        }
    }
    Timer {
        interval: 2600; repeat: true
        running: root.visible && !root.hidden && !root.reduced
        onTriggered: { interval = 2200 + Math.random() * 3200; root.lookSomewhere(); }
    }
    onBusyChanged: if (busy) gazeMode = "orb"
    onListeningChanged: if (listening) gazeMode = "orb"

    // --- Play. When nothing is going on it does things: sleeps, stretches, runs laps around the
    // orb, stalks and pounces on the pointer, hides behind the orb and peeks out, or bats a ball
    // about. Anything happening on the orb's side (or a pet) cuts it short.
    property string activity: ""
    property bool sleeping: false
    property bool crouching: false
    property bool shut: false
    property bool toyOn: false
    property real toyX: 0
    property real toyY: 0
    property real toySize: 0
    property real toySpin: 0
    property var pending: null
    Timer {
        id: seq
        onTriggered: { const f = root.pending; root.pending = null; if (f) f(); }
    }
    function after(ms, fn) { root.pending = fn; seq.interval = ms; seq.restart(); }
    function arrive(extra) { return (walkAnim.running ? walkAnim.duration : 0) + (extra ?? 120); }
    readonly property var monitor: {
        const w = root.QsWindow.window;
        return w && w.screen ? Hyprland.monitorFor(w.screen) : null;
    }
    // The pointer, relative to the orb's centre.
    function pointer() {
        const mon = root.monitor?.lastIpcObject;
        return {x: CursorGaze.x - (mon?.x ?? 0) - root.orbX, y: CursorGaze.y - (mon?.y ?? 0) - root.orbY};
    }
    function stopActivity() {
        seq.stop(); root.pending = null;
        zoomAnim.stop();
        if (root.zooming) { fromX = toX = offX; fromY = toY = offY; walk = 1; root.zooming = false; }
        root.activity = ""; root.sleeping = false; root.crouching = false; root.shut = false;
        root.withOrb = false; root.orbMood = ""; root.inFront = false;
        root.squash = 0; root.tilt = 0; root.wiggle = 0;
        if (root.toyOn) toyFade.restart();
    }
    function endActivity(wait) {
        root.activity = ""; root.squash = 0; root.tilt = 0; root.shut = false;
        root.withOrb = false; root.orbMood = ""; root.inFront = false;
        root.gazeMode = "orb";
        root.after(wait ?? 600, () => root.home());
    }
    function hopNow(h) { leapAnim.to = h ?? 12; leapAnim.restart(); }

    function doSleep() {
        root.activity = "sleep";
        root.home();
        root.after(arrive(300), () => {
            root.sleeping = true; root.shut = true; root.squash = .5; root.tilt = side * 3;
            root.after(11000 + Math.random() * 12000, () => {
                root.sleeping = false; root.shut = false; root.squash = 0; root.tilt = 0;
                root.after(500, () => root.doStretch());
            });
        });
    }
    function doStretch() {
        root.activity = "stretch";
        root.shut = true; root.squash = .55; root.tilt = -side * 4;     // long and low
        root.after(1000, () => {
            root.squash = -.45; root.tilt = 0;                          // then up on its toes
            root.after(650, () => {
                root.squash = 0; root.shut = false;
                shakeAnim.restart();                                     // and a shake
                root.endActivity(900);
            });
        });
    }
    function doZoomies() {
        // Laps would run through anything drawn around the orb.
        if (root.obstacles.length > 0) return false;
        if (root.orbX < 170 || root.orbX > root.areaWidth - 170 || root.orbY < 160 || root.orbY > root.areaHeight - 130) return false;
        root.activity = "zoom";
        root.gazeMode = "away"; root.glanceX = 0; root.glanceY = 0;
        const a0 = Math.atan2(offY, offX);
        root.zoomR = Math.max(74, Math.min(96, Math.hypot(offX, offY)));
        root.zoomAngle = a0;
        root.zooming = true;
        const dir = Math.random() < .5 ? 1 : -1;
        zoomAnim.from = a0; zoomAnim.to = a0 + dir * Math.PI * 2 * (1.4 + Math.random() * .8);
        zoomAnim.duration = 2300;
        root.squash = .15;
        zoomAnim.restart();
        return true;
    }
    function doPounce() {
        const p = root.pointer();
        const d = Math.hypot(p.x, p.y);
        if (d < 150 || d > 560) return false;
        root.activity = "pounce";
        root.gazeMode = "cursor";
        root.crouching = true; root.squash = .5;
        const r = Math.max(70, Math.min(128, d - 30));
        const spot = root.nearestClear(p.x / d * r, p.y / d * r);
        if (!spot) { root.stopActivity(); return false; }
        root.after(1100, () => {
            root.crouching = false; root.wiggle = 0; root.squash = 0;
            root.goTo(spot.x, spot.y, 300);
            root.hopNow(18);
            root.after(380, () => {
                root.squash = .45;                                      // lands, a little squashed
                root.after(420, () => {
                    root.squash = 0;
                    root.endActivity(1300);
                });
            });
        });
        return true;
    }
    function doPeek() {
        root.activity = "peek";
        root.withOrb = true; root.orbMood = "curious";
        root.gazeMode = "away"; root.glanceX = 0; root.glanceY = 0;
        root.goTo(root.side * 24, root.downward * 8);                   // behind the orb
        root.after(arrive(1800), () => {
            root.goTo(root.side * 52, root.downward * 14, 700);         // an ear and an eye
            root.gazeMode = "orb";
            root.after(1500, () => {
                root.goTo(root.side * 24, root.downward * 8, 500);
                root.after(1000, () => {
                    root.goTo(root.side * 74, root.downward * 40, 420);  // and out with a hop
                    root.hopNow(14);
                    root.endActivity(700);
                });
            });
        });
    }
    function doToy() {
        const spot = root.pickSpot();
        if (!spot) return false;
        root.activity = "toy";
        root.toyX = spot.x; root.toyY = spot.y;
        root.toyOn = true;
        toyPop.restart();
        let bats = 2 + Math.floor(Math.random() * 3);
        const chase = () => {
            // Run up beside the ball, on the orb's side of it.
            const len = Math.max(1, Math.hypot(root.toyX, root.toyY));
            const near = root.nearestClear(root.toyX - root.toyX / len * 30, root.toyY - root.toyY / len * 30);
            root.gazeMode = "away";
            if (near) root.goTo(near.x, near.y, 520);
            root.after(arrive(60), () => {
                // Bat it somewhere else.
                if (bats-- <= 0) { root.toyOn = false; toyFade.restart(); root.endActivity(500); return; }
                root.squash = .35;
                root.after(260, () => {
                    root.squash = 0; root.hopNow(10);
                    const next = root.pickSpot();
                    if (next) { toyRoll.toX = next.x; toyRoll.toY = next.y; toyRoll.spinTo = root.toySpin + 500; toyRoll.restart(); }
                    root.after(750, chase);
                });
            });
        };
        chase();
        return true;
    }

    // Bats at the orb: crouches, springs, and the orb wobbles away and looks back, amused.
    function doBat() {
        root.activity = "bat";
        root.withOrb = true; root.orbMood = "curious"; root.gazeMode = "orb";
        let bats = 2 + Math.floor(Math.random() * 3);
        const dirX = -root.side, dirY = -root.downward * .15;
        const round = () => {
            root.goTo(root.side * 62, root.downward * 14, 520);
            root.after(arrive(40), () => {
                root.crouching = true; root.squash = .45;
                root.after(750, () => {
                    root.crouching = false; root.wiggle = 0; root.squash = 0;
                    root.goTo(root.side * 44, root.downward * 10, 170);
                    root.hopNow(13);
                    root.after(170, () => {
                        root.poke(dirX, dirY, .8 + Math.random() * .7);
                        root.orbMood = "startled"; root.squash = .3;
                        root.after(350, () => {
                            root.orbMood = "delighted"; root.squash = 0;
                            root.goTo(root.side * 68, root.downward * 16, 280);
                            if (--bats <= 0) { root.after(900, () => { root.orbMood = ""; root.endActivity(400); }); }
                            else root.after(700, round);
                        });
                    });
                });
            });
        };
        round();
    }
    // Climbs on top of the orb and sits there while it bobs.
    function doRide() {
        if (root.orbY < 130) return false;
        root.activity = "ride";
        root.withOrb = true; root.orbMood = "delighted"; root.gazeMode = "orb";
        root.goTo(root.side * 56, 0, 500);
        root.after(arrive(200), () => {
            root.squash = .4;
            root.after(380, () => {
                root.squash = 0; root.inFront = true;
                root.goTo(root.side * 6, -50, 420);
                root.hopNow(24);
                root.after(440, () => {
                    root.poke(0, 1, .7);                                     // lands: the orb dips
                    root.squash = .3;
                    root.after(260, () => {
                        root.squash = 0; root.gazeMode = "away"; root.glanceX = .8; root.glanceY = .1;
                        root.after(1500, () => {
                            root.glanceX = -.8;
                            root.after(1500, () => {
                                root.orbMood = ""; root.gazeMode = "orb";
                                root.after(1200, () => {
                                    root.goTo(root.side * 74, root.downward * 40, 440);
                                    root.hopNow(18);
                                    root.after(500, () => { root.inFront = false; root.endActivity(300); });
                                });
                            });
                        });
                    });
                });
            });
        });
        return true;
    }
    /** Start one by name (also `companion kitten <name>` over IPC): sleep, stretch, zoom, pounce, peek, toy. */
    function play(name) {
        stopActivity();
        switch (name) {
        case "sleep": doSleep(); return "sleep";
        case "stretch": doStretch(); return "stretch";
        case "zoom": return doZoomies() ? "zoom" : "no room";
        case "pounce": return doPounce() ? "pounce" : "pointer too close or too far";
        case "peek": doPeek(); return "peek";
        case "toy": return doToy() ? "toy" : "no room";
        case "bat": doBat(); return "bat";
        case "ride": return doRide() ? "ride" : "no room above the orb";
        case "stop": return "stopped";
        }
        return "unknown: sleep stretch zoom pounce peek toy bat ride stop";
    }
    // Every so often, if nothing is going on, it picks something to do.
    Timer {
        id: playTimer
        interval: 9000; repeat: true
        running: root.visible && root.calm && !root.reduced && !root.dragged
        onTriggered: {
            interval = 8000 + Math.random() * 10000;
            if (root.activity !== "" || root.walking || root.fan.length > 0) return;
            const roll = Math.random();
            if (roll < .12) root.doSleep();
            else if (roll < .22) root.doStretch();
            else if (roll < .34) { if (!root.doZoomies()) root.doStretch(); }
            else if (roll < .48) { if (!root.doPounce()) root.doToy(); }
            else if (roll < .58) root.doPeek();
            else if (roll < .72) root.doToy();
            else if (roll < .88) root.doBat();
            else { if (!root.doRide()) root.doBat(); }
        }
    }
    readonly property bool dragged: false
    NumberAnimation { id: zoomAnim; target: root; property: "zoomAngle"; easing.type: Easing.InOutQuad
        onFinished: {
            if (!root.zooming) return;
            // Settle wherever the lap ended, then drift back to the usual spot.
            root.fromX = root.toX = Math.cos(root.zoomAngle) * root.zoomR;
            root.fromY = root.toY = Math.sin(root.zoomAngle) * root.zoomR;
            root.walk = 1; root.zooming = false; root.squash = 0;
            root.endActivity(500);
        }
    }
    SequentialAnimation { id: leapAnim; property real to: 12
        NumberAnimation { target: root; property: "leap"; to: leapAnim.to; duration: 150; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "leap"; to: 0; duration: 240; easing.type: Easing.InQuad } }
    SequentialAnimation { id: shakeAnim
        NumberAnimation { target: root; property: "wiggle"; to: 7; duration: 60 }
        NumberAnimation { target: root; property: "wiggle"; to: -7; duration: 90 }
        NumberAnimation { target: root; property: "wiggle"; to: 5; duration: 80 }
        NumberAnimation { target: root; property: "wiggle"; to: 0; duration: 80 } }
    // Stalking: a tense little wiggle before the pounce.
    SequentialAnimation on wiggle {
        running: root.crouching; loops: Animation.Infinite
        NumberAnimation { to: 4; duration: 90 }
        NumberAnimation { to: -4; duration: 90 }
        onRunningChanged: if (!running && !shakeAnim.running) root.wiggle = 0
    }
    // The ball.
    ParallelAnimation { id: toyRoll; property real toX: 0; property real toY: 0; property real spinTo: 0
        NumberAnimation { target: root; property: "toyX"; to: toyRoll.toX; duration: 650; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "toyY"; to: toyRoll.toY; duration: 650; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "toySpin"; to: toyRoll.spinTo; duration: 650; easing.type: Easing.OutCubic } }
    NumberAnimation { id: toyPop; target: root; property: "toySize"; from: 0; to: 1; duration: 320; easing.type: Easing.OutBack; easing.overshoot: 2 }
    NumberAnimation { id: toyFade; target: root; property: "toySize"; to: 0; duration: 260; easing.type: Easing.InQuad
        onFinished: root.toyOn = false }
    Item {
        id: toy
        visible: root.toySize > .02
        width: 20; height: 20
        x: root.orbX + root.toyX - root.x - width / 2
        y: root.orbY + root.toyY - root.y - height / 2 + 14
        scale: root.toySize
        rotation: root.toySpin
        z: -1
        Rectangle {
            anchors.fill: parent; radius: 10
            gradient: Gradient { orientation: Gradient.Vertical
                GradientStop { position: 0; color: Appearance.colors.colPrimary }
                GradientStop { position: 1; color: Appearance.colors.colSecondary } }
            Rectangle { x: 3; y: 6; width: 10; height: 2; radius: 1; color: Appearance.colors.colOnPrimary; opacity: .55; rotation: -25 }
            Rectangle { x: 5; y: 3; width: 2; height: 10; radius: 1; color: Appearance.colors.colOnPrimary; opacity: .4; rotation: 20 }
        }
    }
    // Sleeping: little z's drift up.
    component Zed: StyledText {
        property int lag: 0
        text: "z"
        font.pixelSize: 11; font.weight: Font.Bold
        color: Appearance.colors.colSubtext
        opacity: 0
        x: root.width / 2 + 12; y: 6
        SequentialAnimation on opacity { running: root.sleeping; loops: Animation.Infinite
            onRunningChanged: if (!running) opacity = 0
            PauseAnimation { duration: lag }
            NumberAnimation { to: .85; duration: 500 }
            NumberAnimation { to: 0; duration: 1500 } }
        SequentialAnimation on y { running: root.sleeping; loops: Animation.Infinite
            PauseAnimation { duration: lag }
            NumberAnimation { from: 8; to: -14; duration: 2000 } }
    }
    Zed { lag: 0 }
    Zed { lag: 700; font.pixelSize: 9 }
    Zed { lag: 1400; font.pixelSize: 13 }

    Canvas {
        id: canvas
        anchors.fill: parent
        anchors.margins: -16
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            const t = root.reduced ? 0 : root.time;
            const w = 54, s = root.side;
            const cx = width / 2, cy = height / 2 + 6.4, r = w * .36;
            const breath = 1 + (root.reduced ? 0 : (root.sleeping ? .035 * Math.sin(t * 1.1) : .02 * Math.sin(t * 1.5))) + root.purr * .02 * Math.sin(t * 38);
            const grad = ctx.createLinearGradient(cx - r, cy - r * 1.4, cx + r, cy + r);
            grad.addColorStop(0, String(root.toneA));
            grad.addColorStop(1, String(root.toneB));
            const perk = root.listening ? 1.14 : 1;
            const rx = r * 1.08 * breath, ry = r * 1.04 * breath;

            ctx.fillStyle = grad;
            ctx.lineJoin = "round";
            // One outline for head and ears: the head's radius swells into two soft, round bumps,
            // so the ears grow out of the head with no seam or notch, like the orb's own blobs.
            const earAt = [-Math.PI / 2 - .7, -Math.PI / 2 + .7];
            const spread = .62;
            function earLift(a, i) {
                let d = Math.abs(a - earAt[i]);
                d = Math.min(d, Math.PI * 2 - d);
                const twitch = (earAt[i] > -Math.PI / 2) === (s > 0) ? root.earTwitch * .2 : 0;
                const h = .36 * perk + twitch;
                return d < spread ? h * Math.pow(.5 + .5 * Math.cos(Math.PI * d / spread), .85) : 0;
            }
            function outline() {
                ctx.beginPath();
                for (let k = 0; k <= 120; k++) {
                    const a = -Math.PI + k / 120 * Math.PI * 2;
                    const wob = 1 + (root.reduced ? 0 : .014 * Math.sin(a * 4 + t * .8));
                    // A shallow dip between the ears so they read as two separate bumps.
                    const mid = Math.abs(a + Math.PI / 2);
                    const dip = mid < .5 ? .075 * (.5 + .5 * Math.cos(Math.PI * mid / .5)) : 0;
                    const f = (1 + earLift(a, 0) + earLift(a, 1) - dip) * wob;
                    const x = cx + Math.cos(a) * rx * f;
                    const y = cy + Math.sin(a) * ry * f * (Math.sin(a) > 0 ? 1.02 : 1);
                    if (k === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
                }
                ctx.closePath();
            }

            // Paws: two little ovals peeking out under the chin.
            const pawY = cy + ry * .95;
            for (let i = -1; i <= 1; i += 2) {
                ctx.beginPath();
                ctx.ellipse(cx + i * rx * .42 - w * .075, pawY - w * .05, w * .15, w * .105);
                ctx.fill();
            }
            outline();
            ctx.fill();

            // Inner ears and a soft light across the head, as on the orb.
            ctx.globalAlpha = .3;
            ctx.fillStyle = String(Appearance.colors.colPrimaryContainer);
            ctx.save();
            outline();
            ctx.clip();
            for (let i = 0; i < 2; i++) {
                const dist = 1 + earLift(earAt[i], i) * .5;
                ctx.beginPath();
                ctx.ellipse(cx + Math.cos(earAt[i]) * rx * dist - w * .05, cy + Math.sin(earAt[i]) * ry * dist - w * .055, w * .1, w * .11);
                ctx.fill();
            }
            ctx.restore();
            ctx.globalAlpha = .13;
            ctx.fillStyle = String(Appearance.colors.colTertiary);
            ctx.save();
            outline();
            ctx.clip();
            ctx.beginPath();
            ctx.moveTo(cx - rx * 1.2, cy + ry * .3);
            ctx.bezierCurveTo(cx - rx * .3, cy - ry * .8, cx + rx * .2, cy + ry * .8, cx + rx * 1.2, cy - ry * .2);
            ctx.lineTo(cx + rx * 1.2, cy + ry * 1.3);
            ctx.lineTo(cx - rx * 1.2, cy + ry * 1.3);
            ctx.closePath();
            ctx.fill();
            ctx.restore();

            // Whiskers and a nose, drawn quiet.
            ctx.globalAlpha = .5;
            ctx.strokeStyle = String(root.ink);
            ctx.lineWidth = Math.max(1, w * .02);
            ctx.lineCap = "round";
            for (let i = -1; i <= 1; i += 2) {
                for (let j = -1; j <= 1; j += 2) {
                    ctx.beginPath();
                    ctx.moveTo(cx + i * rx * .62, cy + ry * (.32 + j * .06));
                    ctx.lineTo(cx + i * rx * 1.02, cy + ry * (.3 + j * .2));
                    ctx.stroke();
                }
            }
            ctx.globalAlpha = .9;
            ctx.fillStyle = String(Appearance.colors.colPrimaryContainer);
            ctx.beginPath();
            ctx.moveTo(cx - w * .03, cy + ry * .3);
            ctx.lineTo(cx + w * .03, cy + ry * .3);
            ctx.lineTo(cx, cy + ry * .3 + w * .03);
            ctx.closePath();
            ctx.fill();
            ctx.globalAlpha = 1;
        }
    }
    Timer {
        interval: 50; repeat: true
        running: root.visible && !root.hidden && !root.reduced
        onTriggered: root.time += .05
    }

    AiCreature {
        id: face
        x: (root.width - width) / 2
        y: root.height * .6 - height / 2 - 2
        diameter: 32
        live: !root.reduced && !root.hidden
        shut: root.shut
        manualGaze: root.gazeMode !== "cursor"
        aimX: root.aimAt.x
        aimY: root.aimAt.y
        color: root.ink
        personality: true
        mood: root.purr > .05 ? "delighted" : AiCompanionUi.mood
        listening: root.listening
        speaking: root.phase === "speaking"
        working: root.busy
        error: root.phase === "error"
        level: AiCompanionUi.level
    }

    // A heart for being petted.
    MaterialSymbol {
        id: heartIcon
        anchors.horizontalCenter: parent.horizontalCenter
        y: -6
        text: "favorite"
        iconSize: 14
        fill: 1
        color: Appearance.colors.colTertiary
        opacity: 0
    }
    ParallelAnimation {
        id: heart
        NumberAnimation { target: heartIcon; property: "y"; from: 2; to: -22; duration: 900; easing.type: Easing.OutCubic }
        SequentialAnimation {
            NumberAnimation { target: heartIcon; property: "opacity"; from: 0; to: 1; duration: 120 }
            PauseAnimation { duration: 450 }
            NumberAnimation { target: heartIcon; property: "opacity"; to: 0; duration: 330 }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.pet()
    }
    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr("Kitten")
    StyledToolTip {
        extraVisibleCondition: area.containsMouse && !root.hidden
        text: Translation.tr("Pet the kitten")
    }
}

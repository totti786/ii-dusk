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
    /** Where the top of the state label ("Ready to talk") is, as a y offset from the orb, or NaN when there is no label. */
    property real perchY: NaN
    readonly property bool canPerch: {
        if (isNaN(root.perchY) || root.orbY + root.perchY <= 44 || root.hidden) return false;
        for (const b of root.fan) if (Math.abs(root.side * 34 - b.x) < 56 && Math.abs(root.perchY - b.y) < 54) return false;
        return true;
    }
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
    // --- What it knows about the desktop and the day.
    readonly property var kept: AiCompanionUi.saved
    readonly property real affection: root.kept.affection ?? .5
    readonly property bool sulky: root.affection < .25
    readonly property bool fond: root.affection > .75
    property int hour: new Date().getHours()
    property int month: new Date().getMonth()
    readonly property bool night: root.hour >= 23 || root.hour < 5
    readonly property bool musicOn: MprisController.isPlaying === true
    readonly property bool cold: Battery.available && Battery.isLow && !Battery.isPluggedIn
    readonly property bool plugged: Battery.available && Battery.isCharging
    readonly property bool focusing: TimerService.pomodoroRunning && !TimerService.pomodoroBreak
    readonly property bool resting: TimerService.pomodoroRunning && TimerService.pomodoroBreak
    readonly property bool sunny: Number(Weather.data?.wCode ?? 0) === 113 && root.hour >= 8 && root.hour < 18
    // What it wears: a scarf in winter, sunglasses on a sunny day, a bow tie when it is very fond of you.
    readonly property string outfit: (root.month === 11 || root.month <= 1) ? "scarf" : root.sunny ? "shades" : root.fond ? "bow" : ""
    /** Something it carries to you (a gift, a reminder card): a Material symbol name, or "". */
    property string carry: ""
    property bool carryIsGift: false
    readonly property int giftCount: String(root.kept.gifts ?? "").split(",").filter(g => g.length > 0).length
    /** The orb ducks out of sight (hide and seek). */
    property bool orbHidden: false
    property bool laserOn: false
    property bool deepSleep: false
    property bool greeted: false
    property real lastGift: Date.now()
    property real hop: 0        // px lifted
    property real earTwitch: 0  // 0..1
    property bool chasing: false    // spinning after its own tail
    property bool annoyed: false    // petted far too much
    property int petCount: 0
    property real lastPet: 0
    signal hearts(int count)

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
    // Curled up against the cold when the battery is low, on top of whatever else it is doing.
    readonly property real shape: root.squash + (root.cold && root.activity === "" && !root.walking ? .3 : 0)
    property real tilt: 0
    property real wiggle: 0
    readonly property bool shivering: root.cold && root.activity === "" && !root.walking && !root.reduced && root.visible
    // Nods along to music while it is calm.
    readonly property real musicBob: root.musicOn && !root.reduced && root.calm && root.activity === "" && !root.walking ? Math.abs(Math.sin(root.time * 6.3)) * 2.2 : 0
    property real leap: 0
    Behavior on squash { enabled: !root.reduced; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    Behavior on tilt { enabled: !root.reduced; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
    transform: [
        Scale { origin.x: root.width / 2; origin.y: root.height * .88; xScale: 1 + root.shape * .16; yScale: 1 - root.shape * .22 },
        Rotation { origin.x: root.width / 2; origin.y: root.height * .88; angle: root.tilt + root.wiggle },
        Translate { y: -(root.hop + root.stride + root.leap + (root.phase === "speaking" && !root.reduced ? AiCompanionUi.level * 3.5 : 0) + root.musicBob) }
    ]

    onTimeChanged: canvas.requestPaint()
    onPurrChanged: canvas.requestPaint()
    onEarTwitchChanged: canvas.requestPaint()
    onSideChanged: { canvas.requestPaint(); if (!walking) home(); }
    onToneAChanged: canvas.requestPaint()
    onToneBChanged: canvas.requestPaint()

    function pet() {
        stopActivity();
        // Pets in a row build up: a heart, then a blissful squint and a burst of them, then too much.
        const now = Date.now();
        root.petCount = now - root.lastPet < 3500 ? root.petCount + 1 : 1;
        root.lastPet = now;
        const wasSulky = root.sulky;
        root.kept.affection = Math.min(1, root.affection + (wasSulky ? .15 : .04));
        root.kept.lastPetAt = now;
        if (root.carry !== "") root.collectCarry();
        if (wasSulky) { root.petCount = Math.max(root.petCount, 3); }
        if (root.reduced) { purr = 1; purrFade.restart(); root.hearts(1); return; }
        petAnim.restart();
        purrFade.restart();
        root.hearts(root.petCount >= 3 ? 3 : 1);
        if (root.petCount >= 7) {
            root.petCount = 0;
            root.annoyed = true; annoyTimer.restart();
            shakeAnim.restart(); root.hopNow(22);
            const spot = root.pickSpot();
            if (spot) root.goTo(spot.x, spot.y, 420);
        } else if (root.petCount >= 3) {
            root.shut = true; root.squash = .3; blissTimer.restart();
        }
    }
    // A gift is taken (a reminder card just vanishes with a nod).
    function collectCarry() {
        if (root.carryIsGift) {
            root.kept.gifts = String(root.kept.gifts ?? "") + root.carry + ",";
            root.kept.affection = Math.min(1, root.affection + .03);
        }
        root.carry = ""; root.carryIsGift = false;
    }
    Timer { id: blissTimer; interval: 2600; onTriggered: { if (root.activity === "") { root.shut = false; root.squash = 0; } } }
    Timer { id: annoyTimer; interval: 1800; onTriggered: root.annoyed = false }
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
    // Keeps time: the hour and month, and it slowly sulks if nobody pets it for hours.
    Timer {
        interval: 60000; repeat: true; running: true
        onTriggered: {
            const d = new Date();
            if (d.getHours() !== root.hour) { root.hour = d.getHours(); root.greeted = false; }
            root.month = d.getMonth();
            const since = Date.now() - Number(root.kept.lastPetAt ?? 0);
            if (since > 2 * 3600000 && root.affection > .05) root.kept.affection = Math.max(.05, root.affection - .0015);
        }
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
    // Is this offset inside something drawn around the orb (a label, a small orb, a button)?
    function inObstacle(dx, dy) {
        for (const o of root.obstacles)
            if (dx + 30 > o.x - 4 && dx - 30 < o.x + o.w + 4 && dy + 28 > o.y - 4 && dy - 26 < o.y + o.h + 4) return true;
        return false;
    }
    // Can it walk in a straight line from one offset to another without crossing one? A kitten
    // that already stands in one is let out.
    function pathClear(x0, y0, x1, y1) {
        if (root.inObstacle(x0, y0)) return true;
        for (let i = 1; i <= 12; i++)
            if (root.inObstacle(x0 + (x1 - x0) * i / 12, y0 + (y1 - y0) * i / 12)) return false;
        return true;
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
        if (root.clear(wx, wy) && root.pathClear(root.offX, root.offY, wx, wy)) return {x: wx, y: wy};
        let best = null, bestDist = 1e9;
        for (const rad of [74, 88, 102]) {
            for (let deg = 0; deg < 360; deg += 10) {
                const a = deg * Math.PI / 180;
                const dx = Math.cos(a) * rad, dy = Math.sin(a) * rad;
                if (!root.clear(dx, dy) || !root.pathClear(root.offX, root.offY, dx, dy)) continue;
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
                if (!root.clear(dx, dy) || !root.pathClear(root.offX, root.offY, dx, dy)) continue;
                let nearest = 1e9;
                for (const b of root.fan) nearest = Math.min(nearest, Math.hypot(dx - b.x, dy - b.y));
                const score = Math.min(nearest, 140) - Math.hypot(dx - root.offX, dy - root.offY) * .05;
                if (score > bestScore) { bestScore = score; best = {x: dx, y: dy}; }
            }
        }
        if (best) root.goTo(best.x, best.y);
    }
    onFanChanged: { if (canPerch) perch(); else if (fan.length > 0) avoid(); else if (!hidden) home(); }
    // A label has come up over the orb: it climbs on top of it, sits a moment, then dozes there
    // until the label goes. It never stands behind or under the text.
    function perch() {
        if (root.activity === "perch") return;
        stopActivity();
        root.activity = "perch";
        root.gazeMode = "orb";
        root.goTo(root.side * 34, root.perchY, 520);
        root.after(arrive(80), () => {
            root.hopNow(6);
            root.squash = .3; root.tilt = root.side * 2;
            root.after(2600, () => {
                if (root.activity !== "perch") return;
                root.sleeping = true; root.shut = true; root.squash = .5;
            });
        });
    }
    onPerchYChanged: {
        if (hidden || !visible) return;
        if (canPerch) perch();
        else if (activity === "perch") { stopActivity(); home(); hopNow(10); }
    }
    function home() {
        const spot = root.nearestClear(root.side * (root.fond ? 60 : root.sulky ? 106 : 74), root.downward * 40);
        if (spot) root.goTo(spot.x, spot.y);
    }
    function pickSpot() {
        for (let tries = 0; tries < 14; tries++) {
            const sgn = Math.random() < .3 ? -root.side : root.side;
            const ang = (-35 + Math.random() * 105) * Math.PI / 180;
            const rad = 66 + Math.random() * 44;
            const dx = sgn * Math.cos(ang) * rad, dy = root.downward * Math.sin(ang) * rad;
            if (root.clear(dx, dy) && root.pathClear(root.offX, root.offY, dx, dy)) return {x: dx, y: dy};
        }
        return null;
    }
    // Something moved into its spot (a small orb appeared, a label or the approval buttons came
    // up): it shuffles over rather than standing on it.
    onObstaclesChanged: {
        if (hidden || !visible) return;
        if (canPerch && activity !== "perch") { perch(); return; }
        if (activity === "perch") return;
        if (!clear(offX, offY) || !clear(toX, toY)) {
            if (activity !== "") stopActivity();
            if (fan.length > 0) avoid(); else home();
        }
    }
    // Whatever happened, it is never left standing on the text: if it ends up on one it climbs on
    // top of it (a label) or steps off.
    Timer {
        interval: 250; repeat: true
        running: root.visible && !root.hidden && root.obstacles.length > 0
        onTriggered: {
            if (root.walking || root.zooming || root.activity === "perch" || !root.inObstacle(root.offX, root.offY)) return;
            if (root.activity !== "") root.stopActivity();
            if (root.canPerch) root.perch(); else if (root.fan.length > 0) root.avoid(); else root.home();
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
    onCalmChanged: {
        if (!calm && activity !== "perch") stopActivity();
        if (!calm && !hidden && fan.length === 0) { if (canPerch) perch(); else if (activity !== "perch") home(); }
    }

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
        if (root.gazeMode === "fly") return root.toward(root.orbX + root.flyX, root.orbY + root.flyY);
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
        root.chasing = false; flyAnim.stop(); if (root.flyOn) flyFade.restart();
        root.orbHidden = false; root.deepSleep = false;
        if (root.laserOn) { root.laserOn = false; CursorGaze.unwatch(); }
        if (root.cupOn) cupFade.restart();
        root.yarn = false;
    }
    function endActivity(wait) {
        root.activity = ""; root.squash = 0; root.tilt = 0; root.shut = false;
        root.withOrb = false; root.orbMood = ""; root.inFront = false;
        root.gazeMode = "orb";
        root.after(wait ?? 600, () => root.home());
    }
    function hopNow(h) { leapAnim.to = h ?? 12; leapAnim.restart(); }

    // Beds down right against the orb, on its lower side, rather than on the perch above it.
    function curlUp() {
        const spots = [[root.side * 46, 20], [-root.side * 46, 20], [root.side * 40, 34]];
        for (const [x, y] of spots) {
            if (!root.inObstacle(x, y)) { root.goTo(x, y, 420); return; }
        }
        root.home();
    }
    function doSleep() {
        root.activity = "sleep";
        root.curlUp();
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
                if (bats-- <= 0) {
                    root.toyOn = false; toyFade.restart();
                    if (root.yarn) {                                   // tangled in the thread
                        root.crouching = true; root.squash = .3;
                        root.after(1300, () => { root.crouching = false; root.wiggle = 0; root.squash = 0; shakeAnim.restart(); root.yarn = false; root.endActivity(700); });
                        return;
                    }
                    root.endActivity(500); return;
                }
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

    // Spins after its own tail, gets dizzy, and shakes it off.
    function doTailChase() {
        root.activity = "tail";
        root.home();
        root.after(arrive(200), () => {
            root.chasing = true; root.gazeMode = "away"; root.glanceX = root.side * .8; root.glanceY = .5;
            root.hopNow(8);
            root.after(2900, () => {
                root.chasing = false; root.squash = .3; root.tilt = -root.side * 7;     // dizzy
                root.after(700, () => {
                    root.squash = 0; root.tilt = 0;
                    shakeAnim.restart();
                    root.endActivity(900);
                });
            });
        });
    }
    // A butterfly drifts by. It watches, stalks it, pounces, and misses.
    property bool flyOn: false
    property real flyX: 0
    property real flyY: 0
    property real flySize: 0
    property real flap: 1
    function flyTo(x, y, dur) { flyAnim.tx = x; flyAnim.ty = y; flyAnim.dur = dur; flyAnim.restart(); }
    function doButterfly() {
        const s = root.side;
        root.activity = "fly";
        root.flyX = -s * 150; root.flyY = -60; root.flyOn = true; flyPop.restart();
        root.gazeMode = "fly";
        root.flyTo(-s * 50, -74, 1300);
        root.after(1350, () => {
            root.flyTo(s * 30, -98, 1200);
            root.after(1250, () => {
                root.flyTo(s * 92, -36, 1100);
                root.after(1150, () => {
                    root.crouching = true; root.squash = .5;
                    root.after(850, () => {
                        root.crouching = false; root.wiggle = 0; root.squash = 0;
                        const spot = root.nearestClear(s * 76, -22) ?? {x: s * 74, y: root.downward * 40};
                        root.goTo(spot.x, spot.y, 280);
                        root.hopNow(22);
                        root.after(300, () => {
                            root.flyTo(s * 175, -150, 650); flyFade.restart();   // gone, just out of reach
                            root.squash = .4;
                            root.after(420, () => {
                                root.squash = 0; root.gazeMode = "away"; root.glanceX = s * .9; root.glanceY = -.8;
                                root.after(1500, () => root.endActivity(600));
                            });
                        });
                    });
                });
            });
        });
    }

    // A big yawn. The orb catches it.
    function doYawn() {
        root.activity = "yawn";
        root.withOrb = true; root.gazeMode = "orb";
        root.shut = true; root.squash = -.4;
        root.after(500, () => { root.orbMood = "night"; });
        root.after(1700, () => {
            root.squash = 0; root.shut = false; root.withOrb = false; root.orbMood = "";
            root.endActivity(500);
        });
    }
    // Washes a paw: little head dips, eyes shut.
    function doGroom() {
        root.activity = "groom";
        root.home();
        root.after(arrive(250), () => {
            root.shut = true; root.squash = .25; root.tilt = -root.side * 7;
            let n = 6;
            const lick = () => {
                if (n-- <= 0) { root.shut = false; root.squash = 0; root.tilt = 0; root.endActivity(600); return; }
                root.tilt = -root.side * (n % 2 ? 3 : 8);
                root.after(330, lick);
            };
            lick();
        });
    }
    // Sits up like it was told to, and the orb is proud of it.
    function doTrick() {
        root.activity = "trick";
        root.withOrb = true; root.orbMood = "curious"; root.gazeMode = "orb";
        root.goTo(root.side * 62, root.downward * 14, 520);
        root.after(arrive(900), () => {
            root.squash = -.3;                                         // sits up tall
            root.hopNow(6);
            root.after(900, () => {
                root.orbMood = "delighted";
                root.hopNow(18); shakeAnim.restart();
                root.hearts(1);
                root.after(1100, () => { root.squash = 0; root.orbMood = ""; root.endActivity(500); });
            });
        });
    }
    // Hide and seek: the orb ducks out of sight, the kitten looks for it, the orb pops back out.
    function doHide() {
        root.activity = "hide";
        root.withOrb = false; root.orbHidden = true;
        root.gazeMode = "away";
        let n = 0;
        const look = () => {
            if (n++ >= 3) {
                root.orbHidden = false;                                // found!
                root.orbMood = "delighted"; root.withOrb = true;
                root.squash = -.4; root.hopNow(20); shakeAnim.restart();
                root.gazeMode = "orb";
                root.after(1300, () => { root.squash = 0; root.orbMood = ""; root.withOrb = false; root.endActivity(500); });
                return;
            }
            const spot = root.pickSpot();
            if (spot) root.goTo(spot.x, spot.y, 520);
            root.glanceX = (Math.random() - .5) * 1.8; root.glanceY = (Math.random() - .5) * 1.2;
            root.after(arrive(650), () => { root.squash = .2; root.after(350, () => { root.squash = 0; look(); }); });
        };
        root.after(500, look);
        return true;
    }
    // A cup near the edge of the orb's patch: it looks at you, then pushes it off.
    property bool cupOn: false
    property real cupX: 0
    property real cupY: 0
    property real cupSize: 0
    property real cupSpin: 0
    function doKnock() {
        const s = root.side;
        const spot = root.nearestClear(s * 98, root.downward * 34);
        if (!spot) return false;
        root.activity = "knock";
        root.cupX = spot.x; root.cupY = spot.y; root.cupSpin = 0; root.cupOn = true; cupPop.restart();
        root.gazeMode = "away"; root.glanceX = s * .8; root.glanceY = .3;
        const beside = root.nearestClear(spot.x - s * 36, spot.y) ?? {x: s * 62, y: root.downward * 20};
        root.goTo(beside.x, beside.y, 520);
        root.after(arrive(500), () => {
            root.squash = .3;
            cupSlide.tx = spot.x + s * 26; cupSlide.restart();           // a slow, deliberate push
            root.after(1500, () => {
                root.gazeMode = "cursor";                              // looking straight at you
                root.after(1000, () => {
                    root.squash = 0; root.hopNow(8);
                    cupFall.restart();
                    root.orbMood = "startled"; root.withOrb = true;
                    root.poke(-s, .3, 1);
                    root.after(700, () => {
                        root.gazeMode = "away"; root.glanceX = -s * .8; root.glanceY = -.5;   // who, me?
                        root.orbMood = "";
                        root.after(1500, () => root.endActivity(500));
                    });
                });
            });
        });
        return true;
    }
    // A cup and its string... the yarn ball variant of the toy: it trails thread and gets tangled.
    property bool yarn: false
    property real yarnX0: 0
    property real yarnY0: 0
    function doYarn() {
        root.yarn = true;
        const ok = root.doToy();
        if (!ok) { root.yarn = false; return false; }
        root.yarnX0 = root.toyX; root.yarnY0 = root.toyY;
        return true;
    }
    // The laser dot: the kitten chases the pointer for a while.
    function doLaser() {
        if (root.laserOn) { root.stopActivity(); root.endActivity(300); return "laser off"; }
        stopActivity();
        root.activity = "laser"; root.laserOn = true; CursorGaze.watch();
        root.gazeMode = "cursor";
        laserTimer.restart();
        laserStop.restart();
        return "laser";
    }
    // Something at the orb or on the desktop gets its attention.
    function perkUp(glx, gly) {
        if (root.hidden || !root.visible) return;
        if (root.activity === "perch" || root.activity === "laser") { twitch.restart(); root.hopNow(8); return; }
        stopActivity();
        root.activity = "perk";
        twitch.restart(); root.hopNow(11);
        root.gazeMode = "away"; root.glanceX = glx; root.glanceY = gly;
        root.after(2200, () => root.endActivity(300));
    }
    // A timer or alarm goes off: a jump, a shake, and the orb joins in.
    function celebrate() {
        if (root.hidden || !root.visible) return;
        stopActivity();
        root.activity = "party";
        root.withOrb = true; root.orbMood = "delighted"; root.gazeMode = "orb";
        root.hopNow(20); shakeAnim.restart();
        root.after(450, () => { root.hopNow(14); root.poke(-root.side, -.2, .6); });
        root.after(1900, () => { root.orbMood = ""; root.withOrb = false; root.endActivity(300); });
    }
    // Brings you something and keeps it above its head until you take it.
    readonly property var giftIcons: ["eco", "set_meal", "star", "local_florist", "cookie", "spa", "bug_report", "diamond"]
    function doGift() {
        if (root.carry !== "") return false;
        root.activity = "gift";
        root.home();
        root.after(arrive(250), () => {
            root.hopNow(14);
            root.carry = root.giftIcons[Math.floor(Math.random() * root.giftIcons.length)];
            root.carryIsGift = true;
            root.lastGift = Date.now();
            root.gazeMode = "cursor";
            root.after(1500, () => root.endActivity(300));
        });
        return true;
    }
    function deliver(icon) {
        if (root.carry !== "" && root.carryIsGift) return;
        root.carry = icon; root.carryIsGift = false;
        root.hopNow(10);
        carryTimer.restart();
    }
    Timer { id: carryTimer; interval: 7000; onTriggered: { if (!root.carryIsGift) root.carry = ""; } }
    // A gift nobody takes is taken back after a while.
    Timer { interval: 30000; repeat: true; running: root.carryIsGift; onTriggered: if (Date.now() - root.lastGift > 120000) { root.carry = ""; root.carryIsGift = false; } }
    Timer {
        id: laserStop; interval: 40000
        onTriggered: if (root.laserOn) { root.stopActivity(); root.endActivity(300); }
    }
    Timer {
        id: laserTimer; interval: 420; repeat: true
        running: root.laserOn
        property real lastX: 0
        property real lastY: 0
        property int still: 0
        onTriggered: {
            const p = root.pointer();
            const d = Math.hypot(p.x, p.y);
            const moved = Math.hypot(p.x - lastX, p.y - lastY);
            lastX = p.x; lastY = p.y;
            if (moved < 6) still++; else still = 0;
            if (root.walking) return;
            if (still >= 3 && still % 3 === 0) {                        // dot is still: pounce on it
                root.squash = .45;
                root.after(220, () => { root.squash = 0; root.hopNow(16); });
                return;
            }
            // Keeps a little way off the dot, on the orb's side of it.
            const stand = Math.max(0, d - 40);
            const tx = d > 1 ? p.x / d * stand : 0, ty = d > 1 ? p.y / d * stand : 0;
            if (!root.inObstacle(tx, ty) && Math.hypot(tx - root.offX, ty - root.offY) > 26)
                root.goTo(tx, ty, 380);
        }
    }
    // Lies down after the cursor has been still for a long time (and breaks for the Pomodoro);
    // wakes up startled when it moves.
    function doDeepSleep() {
        root.activity = "sleep"; root.deepSleep = true;
        root.curlUp();
        root.after(arrive(300), () => {
            root.sleeping = true; root.shut = true; root.squash = .5; root.tilt = root.side * 3;
            root.withOrb = true; root.orbMood = "night";
        });
    }
    function wakeUp() {
        const was = root.deepSleep;
        root.stopActivity();
        root.activity = "wake";
        root.squash = -.45; root.hopNow(16); shakeAnim.restart();
        root.orbMood = was ? "startled" : ""; root.withOrb = was;
        root.gazeMode = "orb";
        root.after(900, () => { root.orbMood = ""; root.withOrb = false; root.squash = 0; root.endActivity(300); });
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
        if (root.orbY < 130 || root.obstacles.length > 0) return false;
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
        if (name === "laser" && root.laserOn) { stopActivity(); root.endActivity(300); return "laser off"; }
        stopActivity();
        switch (name) {
        case "sleep": doSleep(); return "sleep";
        case "stretch": doStretch(); return "stretch";
        case "zoom": return doZoomies() ? "zoom" : "no room";
        case "pounce": return doPounce() ? "pounce" : "pointer too close or too far";
        case "peek": doPeek(); return "peek";
        case "toy": return doToy() ? "toy" : "no room";
        case "bat": doBat(); return "bat";
        case "tail": doTailChase(); return "tail";
        case "yawn": doYawn(); return "yawn";
        case "groom": doGroom(); return "groom";
        case "trick": doTrick(); return "trick";
        case "hide": return doHide() ? "hide" : "no room";
        case "knock": return doKnock() ? "knock" : "no room";
        case "yarn": return doYarn() ? "yarn" : "no room";
        case "gift": return doGift() ? "gift" : "already carrying something";
        case "laser": return doLaser();
        case "pet": root.pet(); return "pet";
        case "hop": root.hopNow(18); shakeAnim.restart(); return "hop";
        case "come": root.home(); root.after(arrive(100), () => { root.hopNow(12); root.hearts(1); }); return "come";
        case "play": { const pick = ["toy", "butterfly", "bat", "tail", "yarn", "knock", "trick"]; return root.play(pick[Math.floor(Math.random() * pick.length)]); }
        case "wake": root.wakeUp(); return "wake";
        case "butterfly": doButterfly(); return "butterfly";
        case "ride": return doRide() ? "ride" : "no room above the orb";
        case "stop": return "stopped";
        }
        return "unknown: sleep stretch zoom pounce peek toy bat ride tail butterfly yawn groom trick hide knock yarn gift laser pet hop come play wake stop";
    }
    // Every so often, if nothing is going on, it picks something to do.
    Timer {
        id: playTimer
        interval: 9000; repeat: true
        running: root.visible && root.calm && !root.reduced && !root.dragged
        onTriggered: {
            interval = 8000 + Math.random() * 10000;
            if (root.activity !== "" || root.walking || root.fan.length > 0) return;
            // The time of day and its mood colour what it feels like doing.
            if (root.sulky && Math.random() < .7) return;
            if (root.focusing && Math.random() < .6) return;                // quiet while you work
            if (root.resting && !root.sleeping) { root.doSleep(); return; }  // naps through your breaks
            if (!root.greeted && root.hour >= 5 && root.hour < 10) { root.greeted = true; root.doYawn(); return; }
            if (root.night && Math.random() < .55) { if (Math.random() < .5) root.doSleep(); else root.doYawn(); return; }
            if (!root.carryIsGift && Date.now() - root.lastGift > 40 * 60000 && root.affection > .4 && Math.random() < .35) { if (root.doGift()) return; }
            const roll = Math.random();
            if (roll < .07) root.doSleep();
            else if (roll < .12) root.doStretch();
            else if (roll < .16) root.doYawn();
            else if (roll < .21) root.doGroom();
            else if (roll < .29) { if (!root.doZoomies()) root.doStretch(); }
            else if (roll < .38) { if (!root.doPounce()) root.doToy(); }
            else if (roll < .43) root.doPeek();
            else if (roll < .50) root.doToy();
            else if (roll < .56) root.doYarn();
            else if (roll < .62) root.doBat();
            else if (roll < .69) root.doTailChase();
            else if (roll < .77) root.doButterfly();
            else if (roll < .82) { if (!root.doKnock()) root.doBat(); }
            else if (roll < .87) root.doTrick();
            else if (roll < .91) { if (!root.doHide()) root.doPeek(); }
            else { if (!root.doRide()) root.doBat(); }
        }
    }
    // --- Awareness: it notices what happens on the desktop.
    Connections {
        target: Notifications
        function onNotify(notification) { root.perkUp(.9, -.8); }
    }
    Connections {
        target: TimerService
        function onCountdownFinished(countdown) { root.celebrate(); }
        function onPomodoroBreakChanged() {
            if (!TimerService.pomodoroRunning || root.hidden || !root.visible) return;
            if (TimerService.pomodoroBreak) { if (root.calm && root.activity === "") root.doSleep(); }
            else { root.stopActivity(); root.hopNow(16); shakeAnim.restart(); root.endActivity(500); }   // back to work
        }
    }
    Connections {
        target: AlarmService
        function onAlarmRang(alarm) { root.celebrate(); }
    }
    Connections {
        target: RemindersService
        function onAlerted(reminder, level) { root.deliver("sticky_note_2"); root.perkUp(0, 0); }
    }
    Connections {
        target: Battery
        function onIsChargingChanged() {
            if (Battery.isCharging && root.visible && !root.hidden) { purrFade.restart(); root.hearts(1); root.hopNow(8); }
        }
    }
    // Falls asleep when you have not touched the mouse for a long while (and calm), wakes startled.
    Timer {
        interval: 15000; repeat: true
        running: root.visible && !root.hidden && !root.reduced
        onTriggered: {
            if (root.activity === "" && root.calm && !root.walking && Date.now() - CursorGaze.lastMoved > 180000) root.doDeepSleep();
        }
    }
    Connections {
        target: CursorGaze
        function onMovesChanged() { if (root.deepSleep && root.sleeping) root.wakeUp(); }
    }
    // The pointer matters only while the kitten is out (for its eyes, and for dozing off).
    readonly property bool watching: root.visible && !root.hidden && !root.reduced
    property bool counted: false
    function syncWatch() {
        if (root.counted === root.watching) return;
        root.counted = root.watching;
        if (root.counted) CursorGaze.watch(); else CursorGaze.unwatch();
    }
    onWatchingChanged: root.syncWatch()
    Component.onCompleted: root.syncWatch()
    Component.onDestruction: { if (root.counted) CursorGaze.unwatch(); if (root.laserOn) CursorGaze.unwatch(); }
    // Other parts of the shell ask for a trick by name (the voice orb: "good kitty").
    Connections {
        target: AiCompanionUi
        function onKittenRequest(name) { root.play(name); }
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
        running: root.crouching || root.chasing || root.shivering; loops: Animation.Infinite
        NumberAnimation { to: root.chasing ? 9 : root.shivering ? 1.6 : 4; duration: root.chasing ? 110 : root.shivering ? 55 : 90 }
        NumberAnimation { to: root.chasing ? -9 : root.shivering ? -1.6 : -4; duration: root.chasing ? 110 : root.shivering ? 55 : 90 }
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
    ParallelAnimation { id: flyAnim; property real tx: 0; property real ty: 0; property real dur: 1000
        NumberAnimation { target: root; property: "flyX"; to: flyAnim.tx; duration: flyAnim.dur; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "flyY"; to: flyAnim.ty; duration: flyAnim.dur; easing.type: Easing.InOutSine } }
    NumberAnimation { id: flyPop; target: root; property: "flySize"; from: 0; to: 1; duration: 300; easing.type: Easing.OutBack }
    NumberAnimation { id: flyFade; target: root; property: "flySize"; to: 0; duration: 600; easing.type: Easing.InQuad
        onFinished: root.flyOn = false }
    SequentialAnimation on flap { running: root.flyOn; loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 85 }
        NumberAnimation { to: .4; duration: 85 } }
    Item {
        id: butterfly
        visible: root.flySize > .02
        width: 20; height: 14
        x: root.orbX + root.flyX - root.x - width / 2 + Math.sin(root.time * 3.1) * 4
        y: root.orbY + root.flyY - root.y - height / 2 + 14 + Math.cos(root.time * 4.3) * 4
        scale: root.flySize
        rotation: Math.sin(root.time * 3.1) * 14
        z: 3
        Rectangle { width: 10; height: 13; radius: 5; color: Appearance.colors.colTertiary; transform: Scale { origin.x: 10; xScale: root.flap } }
        Rectangle { x: 10; width: 10; height: 13; radius: 5; color: Appearance.colors.colPrimary; transform: Scale { origin.x: 0; xScale: root.flap } }
        Rectangle { x: 9; y: 1; width: 2; height: 12; radius: 1; color: Appearance.colors.colOnSurface; opacity: .7 }
    }
    ParallelAnimation { id: cupSlide; property real tx: 0
        NumberAnimation { target: root; property: "cupX"; to: cupSlide.tx; duration: 1400; easing.type: Easing.InOutSine } }
    ParallelAnimation { id: cupFall
        NumberAnimation { target: root; property: "cupY"; to: root.cupY + 130; duration: 650; easing.type: Easing.InQuad }
        NumberAnimation { target: root; property: "cupSpin"; to: 260; duration: 650 }
        SequentialAnimation { PauseAnimation { duration: 400 } NumberAnimation { target: root; property: "cupSize"; to: 0; duration: 250 } }
        onFinished: root.cupOn = false }
    NumberAnimation { id: cupPop; target: root; property: "cupSize"; from: 0; to: 1; duration: 300; easing.type: Easing.OutBack }
    NumberAnimation { id: cupFade; target: root; property: "cupSize"; to: 0; duration: 220; onFinished: root.cupOn = false }
    Item {
        id: cup
        visible: root.cupSize > .02
        width: 16; height: 18
        x: root.orbX + root.cupX - root.x - width / 2
        y: root.orbY + root.cupY - root.y - height / 2 + 10
        scale: root.cupSize; rotation: root.cupSpin
        z: -1
        Rectangle { width: 14; height: 16; y: 2; x: 1; radius: 4; color: Appearance.colors.colSecondaryContainer
            Rectangle { x: 2; y: 3; width: 10; height: 2; radius: 1; color: Appearance.colors.colOnSecondaryContainer; opacity: .35 } }
        Rectangle { x: 11; y: 5; width: 7; height: 8; radius: 4; color: "transparent"; border.width: 2; border.color: Appearance.colors.colSecondaryContainer }
    }
    // Yarn: a string from where the ball started to where it is now.
    Rectangle {
        visible: root.yarn && root.toySize > .02
        readonly property real ax: root.orbX + root.yarnX0 - root.x
        readonly property real ay: root.orbY + root.yarnY0 - root.y + 14
        readonly property real bx: root.orbX + root.toyX - root.x
        readonly property real by: root.orbY + root.toyY - root.y + 14
        x: ax; y: ay - 1
        width: Math.hypot(bx - ax, by - ay); height: 2; radius: 1
        transformOrigin: Item.Left
        rotation: Math.atan2(by - ay, bx - ax) * 180 / Math.PI
        color: Appearance.colors.colPrimary; opacity: .6; z: -2
    }
    // The laser dot follows the pointer.
    Rectangle {
        visible: root.laserOn
        width: 9; height: 9; radius: 5; z: 4
        color: Appearance.m3colors.m3error
        readonly property var ptr: { CursorGaze.moves; return root.pointer(); }
        x: root.orbX + ptr.x - root.x - width / 2
        y: root.orbY + ptr.y - root.y - height / 2
        Rectangle { anchors.centerIn: parent; width: 18; height: 18; radius: 9; color: parent.color; opacity: .25 }
    }
    // What it carries over its head: a gift, or a reminder card.
    MaterialSymbol {
        id: carryIcon
        visible: root.carry !== "" && !root.hidden
        text: root.carry
        iconSize: 17
        fill: 1
        color: root.carryIsGift ? Appearance.colors.colTertiary : Appearance.colors.colPrimary
        x: (root.width - width) / 2 + root.side * 20
        y: -8 + (root.reduced ? 0 : Math.sin(root.time * 3) * 1.5)
        z: 5
    }
    // Sunglasses sit over the eyes.
    Item {
        visible: root.outfit === "shades" && !root.shut
        x: (root.width - 30) / 2; y: root.height * .6 - 8; width: 30; height: 12; z: 3
        Rectangle { x: 0; y: 1; width: 13; height: 9; radius: 4; color: "#14121a"; opacity: .92
            Rectangle { x: 2; y: 2; width: 5; height: 2; radius: 1; color: "white"; opacity: .35 } }
        Rectangle { x: 17; y: 1; width: 13; height: 9; radius: 4; color: "#14121a"; opacity: .92
            Rectangle { x: 2; y: 2; width: 5; height: 2; radius: 1; color: "white"; opacity: .35 } }
        Rectangle { x: 12; y: 4; width: 6; height: 2; color: "#14121a"; opacity: .92 }
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

            // Tail, behind everything: a slow sway, a quick wag when it purrs, straight up and fat
            // when startled, curled low asleep, and a full spin while it chases it.
            {
                const L = w * .4;
                const bx = cx + s * rx * .78, by = cy + ry * .74;
                const cxp = bx + s * L * .5, cyp = by - L * .1;
                const startled = root.alert || AiCompanionUi.mood === "startled";
                let th;
                if (root.chasing) th = t * 12;
                else if (startled) th = .05;
                else if (root.purr > .05) th = .25 + .55 * Math.sin(t * 9);
                else if (root.musicOn && root.calm && root.activity === "") th = .3 + .45 * Math.sin(t * 6.3);
                else if (root.cold || root.sulky) th = 1.25 + .04 * Math.sin(t * 1.2);
                else if (root.fond) th = .25 + .4 * Math.sin(t * 2.6 + .5);
                else if (root.sleeping) th = 1.1 + .05 * Math.sin(t * 1.1);
                else th = .3 + .3 * Math.sin(t * 1.6 + .5);
                const fx = root.chasing ? 1 : .6, fy = root.chasing ? 1 : .9;
                const tx = cxp + s * L * Math.sin(th) * fx, ty = cyp - L * Math.cos(th) * fy;
                ctx.strokeStyle = grad;
                ctx.lineCap = "round";
                ctx.lineWidth = w * (startled ? .17 : .12);
                ctx.beginPath();
                ctx.moveTo(bx, by);
                ctx.quadraticCurveTo(cxp, cyp + L * .25, tx, ty);
                ctx.stroke();
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

            // A scarf round the neck, or a bow tie.
            if (root.outfit === "scarf") {
                ctx.strokeStyle = String(Appearance.colors.colError);
                ctx.lineWidth = w * .1; ctx.lineCap = "round";
                ctx.beginPath(); ctx.arc(cx, cy + ry * .06, rx * .93, .13 * Math.PI, .87 * Math.PI); ctx.stroke();
                ctx.lineWidth = w * .075;
                ctx.beginPath(); ctx.moveTo(cx + s * rx * .35, cy + ry * .98); ctx.lineTo(cx + s * rx * .5, cy + ry * 1.42); ctx.stroke();
                ctx.globalAlpha = .9;
            } else if (root.outfit === "bow") {
                const by = cy + ry * .98;
                ctx.fillStyle = String(Appearance.colors.colTertiary);
                ctx.beginPath(); ctx.moveTo(cx, by); ctx.lineTo(cx - w * .13, by - w * .06); ctx.lineTo(cx - w * .13, by + w * .07); ctx.closePath(); ctx.fill();
                ctx.beginPath(); ctx.moveTo(cx, by); ctx.lineTo(cx + w * .13, by - w * .06); ctx.lineTo(cx + w * .13, by + w * .07); ctx.closePath(); ctx.fill();
                ctx.fillStyle = String(Appearance.colors.colOnTertiary);
                ctx.beginPath(); ctx.arc(cx, by, w * .03, 0, Math.PI * 2); ctx.fill();
            }
            ctx.globalAlpha = .3;
            ctx.fillStyle = String(Appearance.colors.colPrimaryContainer);
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
    /** Milliseconds between frames it wants, 0 when nothing moves. Quick only for quick
     *  things: a purr or a spin; the breath and the tail's sway need very few. */
    readonly property int frameInterval: !root.visible || root.hidden || root.reduced ? 0
        : root.purr > .05 || root.chasing || root.flyOn || root.zooming ? 33
        : root.musicOn || root.carry !== "" || root.walking ? 50
        : root.sleeping ? 166 : 83
    property real unpainted: 0
    /** Called by the window's clock, which may run faster than the kitten needs. */
    function tick(seconds) {
        if (root.frameInterval === 0) return;
        root.unpainted += Math.min(.25, seconds);
        if (root.unpainted * 1000 < root.frameInterval - 8) return;
        root.time += root.unpainted;
        root.unpainted = 0;
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
        mood: root.annoyed ? "worried" : root.purr > .05 ? "delighted" : AiCompanionUi.mood
        listening: root.listening
        speaking: root.phase === "speaking"
        working: root.busy
        error: root.phase === "error"
        level: AiCompanionUi.level
    }

    // Hearts for being petted: one, or a little burst of three when it is really enjoying it.
    component HeartBit: MaterialSymbol {
        id: bit
        required property int index
        property real dx: 0
        text: "favorite"
        iconSize: index === 0 ? 14 : 11
        fill: 1
        color: index === 1 ? Appearance.colors.colPrimary : Appearance.colors.colTertiary
        opacity: 0
        x: (root.width - width) / 2 + dx
        y: -6
        Connections {
            target: root
            function onHearts(count) { if (bit.index < count) beat.restart(); }
        }
        ParallelAnimation {
            id: beat
            NumberAnimation { target: bit; property: "y"; from: 2; to: -22 - bit.index * 4; duration: 900; easing.type: Easing.OutCubic }
            SequentialAnimation {
                PauseAnimation { duration: bit.index * 130 }
                NumberAnimation { target: bit; property: "opacity"; from: 0; to: 1; duration: 120 }
                PauseAnimation { duration: 450 }
                NumberAnimation { target: bit; property: "opacity"; to: 0; duration: 330 }
            }
        }
    }
    HeartBit { index: 0 }
    HeartBit { index: 1; dx: -17 }
    HeartBit { index: 2; dx: 17 }

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
        text: root.carry !== "" && root.carryIsGift ? Translation.tr("Take the gift") : root.giftCount > 0 ? Translation.tr("Pet the kitten · %1 gifts collected").arg(root.giftCount) : Translation.tr("Pet the kitten")
    }
}

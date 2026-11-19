pragma ComponentBehavior: Bound
import QtQuick
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.bubble

/** One small orb: a live thing (timer, alarm, reminder, track) that budded off the main orb. */
Item {
    id: root
    /** The entry from AiCompanionSatellites.info(), or null while it is being removed. */
    property var info: null
    /** Where it settles, as an offset from the main orb's centre. */
    property real offsetX: 0
    property real offsetY: 0
    property real originX: 0
    property real originY: 0
    property real orbitTime: 0
    signal activated()
    signal dismissed()

    readonly property bool reduced: AiCompanionUi.reducedMotion
    readonly property string state: root.info?.state ?? ""
    readonly property bool done: root.state === "done"
    readonly property real progress: root.info?.progress ?? -1
    readonly property bool media: root.info?.kind === "media"
    readonly property bool working: root.state === "working" || root.state === "waiting"
    readonly property bool failed: root.state === "failed"
    // Same palette as the main orb: a gradient from its tone to its accent.
    readonly property color toneA: root.failed ? Appearance.m3colors.m3error : root.done ? Appearance.colors.colTertiary : root.media ? Appearance.colors.colSecondary : Appearance.colors.colPrimary
    readonly property color toneB: root.done ? Appearance.colors.colPrimary : root.media ? Appearance.colors.colTertiary : Appearance.colors.colSecondary
    readonly property color ink: root.failed ? Appearance.m3colors.m3onError : Appearance.colors.colOnPrimary

    width: 46; height: 46
    // It buds out of the orb: starts on it, small, and travels to its place with a little overshoot.
    property real pop: 0
    SequentialAnimation {
        id: spawn
        PropertyAction { target: root; property: "pop"; value: 0 }
        NumberAnimation { target: root; property: "pop"; to: 1; duration: 460; easing.type: Easing.OutBack; easing.overshoot: 1.5 }
    }
    /** Bud out of the orb again (a new thing took this slot). */
    function respawn() {
        if (root.reduced) pop = 1;
        else spawn.restart();
    }
    Component.onCompleted: root.respawn()
    // A slow bob so a row of them reads as alive, not as a toolbar.
    readonly property real bob: root.reduced ? 0 : Math.sin(root.orbitTime * .9 + root.offsetX * .05) * 1.6
    x: root.originX + root.offsetX * pop - width / 2
    y: root.originY + root.offsetY * pop - height / 2 + bob
    scale: (.3 + .7 * Math.min(1, pop)) * root.breath * (hover.containsMouse && !root.reduced ? 1.1 : 1)
    opacity: Math.min(1, pop * 1.6)
    Behavior on scale { enabled: !root.reduced; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

    // A little blob like the main orb: a soft wobbling silhouette, not a disc. A timer's
    // progress is a liquid level rising inside it.
    Canvas {
        id: blob
        anchors.fill: parent
        property real clock: root.orbitTime
        onClockChanged: requestPaint()
        property real level: root.progress
        onLevelChanged: requestPaint()
        property color a: root.toneA
        property color b: root.toneB
        onAChanged: requestPaint()
        onBChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            ctx.reset();
            // A task being worked on churns faster, like the main orb when it is thinking.
            const t = root.reduced ? 0 : clock * (root.working ? 3.2 : 1.6) + root.offsetX * .07;
            const cx = width / 2, cy = height / 2, r = width * .44;
            const amp = root.done || root.working ? .085 : .055;
            ctx.beginPath();
            for (let i = 0; i <= 64; i++) {
                const angle = i / 64 * Math.PI * 2;
                const wave = Math.sin(angle * 5 + t * .9) * amp + Math.sin(angle * 3 - t * 1.3) * amp * .6;
                const radius = r * (1 + wave);
                const x = cx + Math.cos(angle) * radius, y = cy + Math.sin(angle) * radius;
                if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y);
            }
            ctx.closePath();
            const base = ctx.createLinearGradient(cx - r, cy - r, cx + r, cy + r);
            base.addColorStop(0, String(a));
            base.addColorStop(1, String(b));
            ctx.fillStyle = base;
            ctx.fill();
            ctx.save();
            ctx.clip();
            ctx.fillStyle = String(Appearance.colors.colPrimaryContainer);
            ctx.globalAlpha = level >= 0 ? .6 : .3;
            ctx.beginPath();
            if (level >= 0) {
                // The surface of the liquid, rising as the timer runs down.
                const top = cy + r - Math.max(.04, Math.min(1, level)) * 2 * r;
                ctx.moveTo(cx - r * 1.3, cy + r * 1.3);
                for (let x = -1.3; x <= 1.3; x += .1)
                    ctx.lineTo(cx + x * r, top + Math.sin(x * 4 + t * 1.6) * r * .07);
                ctx.lineTo(cx + r * 1.3, cy + r * 1.3);
            } else {
                // A soft sweep of light, as on the main orb.
                const drift = Math.sin(t * .65) * r * .18;
                ctx.moveTo(cx - r * 1.4, cy + r * .45 + drift);
                ctx.bezierCurveTo(cx - r * .3, cy - r * .9 + drift, cx + r * .2, cy + r * .9 - drift, cx + r * 1.4, cy - r * .25);
                ctx.lineTo(cx + r * 1.4, cy + r * 1.4); ctx.lineTo(cx - r * 1.4, cy + r * 1.4);
            }
            ctx.closePath();
            ctx.fill();
            ctx.restore();
        }
    }
    // Each one has the main orb's eyes, and its own mood for what it is watching.
    readonly property string kind: root.info?.kind ?? ""
    readonly property real secondsLeft: root.info?.left ?? 1e9
    readonly property string mood: root.done ? "delighted"
        : root.state === "paused" ? "night"
        : root.kind === "timer" && root.secondsLeft <= 30 ? "worried"      // nearly out of time
        : root.media ? "delighted"                                  // enjoying the music
        : root.state === "waiting" || root.state === "soon" ? "curious"
        : ""
    AiCreature {
        id: face
        anchors.centerIn: parent
        diameter: Math.round(root.width * 0.86)
        live: !root.reduced
        color: root.ink
        personality: true
        mood: root.mood
        working: root.state === "working"
        attention: root.done || root.state === "waiting"   // a finished one fidgets for notice
        error: root.failed
        longWork: root.state === "working"
    }
    // What kind of thing it is, small, since the face is doing the talking.
    Rectangle {
        width: 17; height: 17; radius: 9
        x: parent.width - width + 1; y: parent.height - height + 1
        color: Appearance.colors.colSurfaceContainerHigh
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.info?.icon ?? "circle"
            iconSize: 11
            fill: 1
            color: Appearance.colors.colOnSurface
        }
    }
    // The music one sways to a beat nobody can hear.
    SequentialAnimation on rotation {
        running: root.media && !root.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 7; duration: 650; easing.type: Easing.InOutSine }
        NumberAnimation { to: -7; duration: 650; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.rotation = 0
    }
    // A finished timer breathes until it is dismissed.
    property real breath: 1
    SequentialAnimation on breath {
        running: root.done && !root.reduced
        loops: Animation.Infinite
        NumberAnimation { to: 1.12; duration: 700; easing.type: Easing.InOutSine }
        NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
        onRunningChanged: if (!running) root.breath = 1
    }
    MouseArea {
        id: hover
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => { if (mouse.button === Qt.RightButton) root.dismissed(); else root.activated(); }
    }
    Accessible.role: Accessible.Button
    Accessible.name: (root.info?.label ?? "") + ", " + (root.info?.detail ?? "")
    StyledToolTip {
        extraVisibleCondition: hover.containsMouse
        text: (root.info?.label ?? "") + ((root.info?.detail ?? "").length > 0 ? "\n" + root.info.detail : "")
    }
}

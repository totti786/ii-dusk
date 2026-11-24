pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.services.ai
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.dynamicIsland.core
import "CompanionPlacement.js" as Placement

Scope {
    id: root
    readonly property var ui: AiCompanionUi
    readonly property var saved: root.ui.saved
    readonly property var voice: root.ui.voice
    property alias controlsOpen: surface.controlsOpen
    property bool motionReady: false
    property real returnProgress: 0
    property real returnStartX: 0
    property real returnStartY: 0
    readonly property var orbitPositions: Placement.orbitOffsets(root.centerX, root.centerY, root.bounds)
    // Small orbs for live things (timers, alarms, music) that bud off the main one.
    readonly property var satellites: AiCompanionSatellites {}
    readonly property bool satellitesShown: !root.ui.docked && !root.ui.dragging && !dockFade.running
    readonly property var satelliteOffsets: Placement.satelliteOffsets(root.satellites.ids.length, root.centerX, root.centerY, root.bounds, 78)
    // The kitten pokes the orb: it gives way a little and springs back.
    property real orbNudgeX: 0
    property real orbNudgeY: 0
    function pokeOrb(dx, dy, power) {
        if (root.ui.reducedMotion) return;
        nudgeAnim.tx = dx * 13 * power; nudgeAnim.ty = dy * 13 * power;
        nudgeAnim.restart();
    }
    ParallelAnimation {
        id: nudgeAnim
        property real tx: 0
        property real ty: 0
        SequentialAnimation {
            NumberAnimation { target: root; property: "orbNudgeX"; to: nudgeAnim.tx; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "orbNudgeX"; to: 0; duration: 750; easing.type: Easing.OutElastic; easing.amplitude: 1; easing.period: .5 }
        }
        SequentialAnimation {
            NumberAnimation { target: root; property: "orbNudgeY"; to: nudgeAnim.ty; duration: 110; easing.type: Easing.OutQuad }
            NumberAnimation { target: root; property: "orbNudgeY"; to: 0; duration: 750; easing.type: Easing.OutElastic; easing.amplitude: 1; easing.period: .5 }
        }
    }
    readonly property bool expanded: root.controlsOpen && !root.ui.dragging && !root.ui.approvalNeeded
    readonly property var bounds: root.ui.screenBounds(overlay.screen)
    readonly property var storedCenter: Placement.fromRatios(root.saved.xRatio, root.saved.yRatio, root.bounds, 38)
    readonly property real centerX: (root.ui.dragging ? root.ui.dragX : root.storedCenter.x) - root.bounds.x
    readonly property real centerY: (root.ui.dragging ? root.ui.dragY : root.storedCenter.y) - root.bounds.y

    Connections {
        target: GlobalStates
        function onAiCompanionOpenSerialChanged() { root.ui.show(); }
    }
    Connections {
        target: root.ui
        function onDocking() { if (overlay.visible) { root.returnStartX = root.centerX; root.returnStartY = root.centerY; dockFade.restart(); } }
        function onDraggingChanged() { if (root.ui.dragging) { root.controlsOpen = false; dockFade.stop(); root.returnProgress = 0; surface.opacity = 1; } }
        function onDockedChanged() { if (!root.ui.docked) { dockFade.stop(); root.returnProgress = 0; surface.opacity = 1; } }
    }
    GlobalShortcut {
        name: "aiCompanionToggle"
        description: "Talk to or interrupt the voice companion"
        onPressed: root.ui.toggle()
    }
    IpcHandler {
        target: "companion"
        function open(): void { root.ui.show(); }
        function collapse(): void { root.controlsOpen = false; root.voice.stop(); }
        function hide(): void { root.ui.hide(); }
        function toggle(): void { root.ui.toggle(); }
        function talk(): void { root.ui.show(); root.voice.start(); }
        function ask(text: string): void { root.ui.show(); root.voice.ask(text); }
        function stop(): void { root.voice.stop(); }
        function transcript(): void { root.ui.transcript(); }
        function attach(path: string): bool { return root.ui.attachFiles([path]); }
        function detach(path: string): void {
            const index = Ai.attachments.findIndex(file => file.path === path);
            if (index >= 0) Ai.removeAttachment(index);
        }
        /** Wear a face (startled, delighted, curious, worried, night) to check it; empty clears. */
        function mood(name: string): string {
            root.ui.moodForced = name;
            return root.ui.mood;
        }
        /** The model behind each stage of a spoken request, as the voice settings page sets them. */
        function models(): string {
            return JSON.stringify({instant: Config.options.ai.voice.rules ? "rules" : "off",
                remoteAi: Ai.onlineAllowed ? "on" : Ai.localOnly ? "local only" : "off",
                quick: !Config.options.ai.voice.fastPath ? "off" : !Ai.onlineAllowed ? "unavailable (remote AI is " + (Ai.localOnly ? "local only" : "off") + ")" : root.voice.claudeState === "missing" ? "unavailable (Claude Code not found)" : root.voice.claudeState === "signedOut" ? "unavailable (Claude Code not signed in)" : root.voice.fastModelId(),
                tasks: root.voice.escalationModelId() || Ai.currentModelId + " (sidebar)"});
        }
        /** Remote AI for the whole shell: "on", "local" (local models only) or "off"; empty reports it. Same switch as Settings > Sidebars. */
        function remote(mode: string): string {
            const wanted = {on: 1, local: 2, off: 0}[String(mode).trim().toLowerCase()];
            if (wanted !== undefined) Config.options.policies.ai = wanted;
            return Ai.onlineAllowed ? "on" : Ai.localOnly ? "local" : "off";
        }
        function approve(): bool { return root.ui.answerApproval(true); }
        function deny(): bool { return root.ui.answerApproval(false); }
        function dock(): bool { return root.ui.dock(); }
        function undock(): void { root.ui.undock(); }
        function kitten(name: string): string { return kitten.play(name); }
        function status(): string {
            return JSON.stringify({visible: root.saved.visible, docked: root.ui.docked, canDock: root.ui.canDock,
                dragging: root.ui.dragging, nearDock: root.ui.nearDock, dockTarget: root.ui.dockTarget,
                timings: root.voice.timings, attachments: root.ui.attachmentCount, fileHover: root.ui.fileHover,
                approval: root.ui.approvalNeeded ? root.ui.describe(root.ui.approval) : null,
                state: root.ui.phase, mood: root.ui.mood, active: root.voice.active, runId: root.voice.runId, rawPhase: root.voice.phase, level: root.ui.level, error: root.voice.errorText,
                x: surface.x, y: surface.y, width: surface.width, height: surface.height,
                mapped: overlay.visible, opacity: surface.opacity, returning: dockFade.running,
                centerX: root.centerX, centerY: root.centerY, monitor: overlay.screen?.name ?? "",
                backend: Ai.voiceService.backendName, engine: Ai.voiceService.sttEngine,
                voiceAvailable: Ai.voiceService.available});
        }
    }
    ParallelAnimation {
        id: dockFade
        NumberAnimation {
            target: surface; property: "opacity"; from: 1; to: 0
            duration: 120; easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: root; property: "returnProgress"; from: 0; to: root.ui.reducedMotion ? 0 : 1
            duration: root.ui.reducedMotion ? 0 : 120; easing.type: Easing.OutCubic
        }
    }
    PanelWindow {
        contentItem.LayoutMirroring.enabled: Translation.isRtl
        contentItem.LayoutMirroring.childrenInherit: true
        id: overlay
        screen: Quickshell.screens.find(screen => screen.name === (root.ui.dragging ? root.ui.dragMonitor : root.saved.monitor))
            ?? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        // Up for an approval too, so a request is answerable even while the orb is docked
        // in the island: the window shows just the card then, not the orb.
        visible: Persistent.ready && root.saved.visible && (!root.ui.docked || root.ui.dragging || dockFade.running || root.ui.approvalNeeded)
            && !GlobalStates.screenLocked && !GlobalStates.regionSelectorOpen
        onVisibleChanged: {
            root.motionReady = false;
            if (visible) Qt.callLater(() => root.motionReady = overlay.visible);
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:aiCompanion"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // Keep the native pointer grab alive until release. The island owns
        // its own grab when pulling a bubble out; that preview stays passthrough.
        // The orb's own hit area is a rectangle bound to where the orb is going, not
        // the item: a region that follows the item only refreshes when the item's
        // own geometry changes, so after the orb was moved by a summon (not a drag,
        // which swaps the mask for the whole window) the input stayed where it was.
        mask: root.ui.dragging ? dragMask : orbMask
        Region {
            id: dragMask
            item: root.ui.dragging ? (root.ui.dragFromIsland ? null : fullWindow) : null
        }
        Region {
            id: orbMask
            x: Math.round(root.centerX - surface.inputArea.width / 2)
            y: Math.round(root.centerY - surface.inputArea.height / 2)
            width: root.ui.docked ? 0 : surface.inputArea.width
            height: root.ui.docked ? 0 : surface.inputArea.height
            // So do the small orbs, one hit area per slot.
            Region { x: Math.round(sat0.x); y: Math.round(sat0.y); width: sat0.shown ? sat0.width : 0; height: sat0.shown ? sat0.height : 0 }
            Region { x: Math.round(sat1.x); y: Math.round(sat1.y); width: sat1.shown ? sat1.width : 0; height: sat1.shown ? sat1.height : 0 }
            Region { x: Math.round(sat2.x); y: Math.round(sat2.y); width: sat2.shown ? sat2.width : 0; height: sat2.shown ? sat2.height : 0 }
            Region { x: Math.round(sat3.x); y: Math.round(sat3.y); width: sat3.shown ? sat3.width : 0; height: sat3.shown ? sat3.height : 0 }
            Region { x: Math.round(sat4.x); y: Math.round(sat4.y); width: sat4.shown ? sat4.width : 0; height: sat4.shown ? sat4.height : 0 }
            // The kitten can be petted.
            Region { x: Math.round(kitten.x); y: Math.round(kitten.y); width: kitten.shown ? kitten.width : 0; height: kitten.shown ? kitten.height : 0 }
            // The approval buttons take clicks too while they are up.
            Region {
                x: denyButton.x; y: denyButton.y
                width: ask.shown ? denyButton.width : 0; height: ask.shown ? denyButton.height : 0
            }
            Region {
                x: allowButton.x; y: allowButton.y
                width: ask.shown ? allowButton.width : 0; height: ask.shown ? allowButton.height : 0
            }
        }
        Item { id: fullWindow; anchors.fill: parent }
        // What the agent is waiting to do. Not a card: the orb holds out two answers, a
        // label above says what is being asked, and the buttons pop out either side of it
        // (under the island when it is docked there).
        Item {
            id: ask
            readonly property var about: root.ui.approvalNeeded ? root.ui.describe(root.ui.approval) : ({title: "", detail: "", mono: false})
            readonly property bool docked: root.ui.docked && !!root.ui.dockTarget
            readonly property real cx: Math.max(60, Math.min(root.bounds.width - 60,
                docked ? root.ui.dockTarget.x + root.ui.dockTarget.width / 2 - root.bounds.x : root.centerX))
            readonly property real cy: docked ? root.ui.dockTarget.y + root.ui.dockTarget.height - root.bounds.y + 52 : root.centerY
            readonly property real spread: docked ? 34 : 78
            readonly property bool labelAbove: cy > 110
            readonly property bool shown: root.ui.approvalNeeded && !root.ui.dragging
            property real pop: shown ? 1 : 0
            Behavior on pop {
                enabled: !root.ui.reducedMotion
                NumberAnimation { duration: ask.shown ? 360 : 140; easing.type: ask.shown ? Easing.OutBack : Easing.OutCubic; easing.overshoot: 1.6 }
            }
            visible: pop > 0.01
            Rectangle {
                id: askLabel
                readonly property bool hasDetail: ask.about.detail.length > 0
                anchors.horizontalCenter: undefined
                x: ask.cx - width / 2
                y: ask.labelAbove ? ask.cy - 62 - height : ask.cy + 62
                width: Math.min(300, Math.max(askTitle.implicitWidth, hasDetail ? askDetail.implicitWidth : 0) + 28)
                height: hasDetail ? 46 : 30
                radius: 16
                color: Appearance.m3colors.m3surfaceContainerHigh
                opacity: ask.pop
                scale: .85 + .15 * ask.pop
                Accessible.role: Accessible.AlertMessage
                Accessible.name: Translation.tr("Approval needed: %1").arg(ask.about.title)
                Column {
                    anchors.centerIn: parent
                    width: parent.width - 20
                    StyledText {
                        id: askTitle
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: Translation.tr("%1?").arg(ask.about.title)
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSurface
                    }
                    StyledText {
                        id: askDetail
                        visible: askLabel.hasDetail
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        maximumLineCount: 1
                        text: ask.about.detail
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.family: ask.about.mono ? Appearance.font.family.monospace : Appearance.font.family.main
                        color: Appearance.colors.colSubtext
                    }
                }
            }
            component AskButton: IconToolbarButton {
                property real side: 1
                property int index: 0
                width: 54; height: 54; iconSize: 28
                buttonRadius: hovered ? 20 : 27
                buttonRadiusPressed: 18
                animationsEnabled: !root.ui.reducedMotion
                x: ask.cx + side * ask.spread * ask.pop - width / 2
                y: ask.cy - height / 2
                opacity: ask.pop
                scale: (.4 + .6 * ask.pop) * (down ? .94 : hovered && !root.ui.reducedMotion ? 1.06 : 1)
                Behavior on scale { enabled: !root.ui.reducedMotion; NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            }
            AskButton {
                id: denyButton
                side: -1
                text: "close"
                colBackground: Appearance.m3colors.m3secondaryContainer
                colText: Appearance.colors.colOnSecondaryContainer
                Accessible.name: Translation.tr("Deny")
                onClicked: root.ui.answerApproval(false)
                StyledToolTip { text: Translation.tr("Deny") }
            }
            AskButton {
                id: allowButton
                side: 1
                text: "check"
                colBackground: Appearance.colors.colPrimary
                colText: Appearance.colors.colOnPrimary
                Accessible.name: Translation.tr("Allow")
                onClicked: root.ui.answerApproval(true)
                StyledToolTip { text: Translation.tr("Allow") }
            }
        }
        // Small orbs: a fixed pool of slots, so each has a stable input region.
        Item {
            id: satelliteLayer
            anchors.fill: parent
            property real clock: 0
            Timer {
                interval: 50; repeat: true
                running: root.satellitesShown && root.satellites.ids.length > 0 && !root.ui.reducedMotion
                onTriggered: satelliteLayer.clock += .05
            }
            component Slot: CompanionSatellite {
                id: slot
                required property int slotIndex
                readonly property string key: root.satellites.ids[slotIndex] ?? ""
                readonly property var spot: root.satelliteOffsets[slotIndex] ?? null
                readonly property bool shown: key.length > 0 && spot !== null && root.satellitesShown
                visible: shown
                info: { root.satellites.tick; return key.length > 0 ? root.satellites.info(key) : null; }
                offsetX: spot?.x ?? 0
                offsetY: spot?.y ?? 0
                originX: root.centerX
                originY: root.centerY
                orbitTime: satelliteLayer.clock
                onKeyChanged: if (key.length > 0) respawn()
                onActivated: root.satellites.activate(key)
                onDismissed: root.satellites.dismiss(key)
            }
            Slot { id: sat0; slotIndex: 0 }
            Slot { id: sat1; slotIndex: 1 }
            Slot { id: sat2; slotIndex: 2 }
            Slot { id: sat3; slotIndex: 3 }
            Slot { id: sat4; slotIndex: 4 }
        }
        // The kitten sits beside the orb, on the side with room, and tucks away when the controls fan out.
        CompanionKitten {
            id: kitten
            readonly property bool shown: Config.options.ai.voice.kitten !== false && !root.ui.docked && !root.ui.dragging && !dockFade.running
            visible: shown
            side: root.centerX > root.bounds.width - 140 ? -1 : 1
            hidden: root.ui.approvalNeeded
            // Steps clear of the buttons while they are fanned out.
            fan: root.expanded ? root.orbitPositions : []
            onPoke: (dx, dy, power) => root.pokeOrb(dx, dy, power)
            downward: root.centerY > root.bounds.height - 140 ? -1 : 1
            orbX: root.centerX
            orbY: root.centerY
            areaWidth: root.bounds.width
            areaHeight: root.bounds.height
            // Things it must not stand on, as offsets from the orb: the small orbs, the state label
            // above it and the approval label and buttons.
            obstacles: {
                const out = [];
                if (root.satellitesShown)
                    for (let i = 0; i < root.satellites.ids.length; i++) {
                        const o = root.satelliteOffsets[i];
                        if (o) out.push({x: o.x - 24, y: o.y - 24, w: 48, h: 48});
                    }
                const lift = root.satellitesShown && root.satelliteOffsets.length > 0 ? 58 : 0;
                if (root.centerY > 92 + lift && (root.expanded || root.voice.active || root.ui.fileHover))
                    out.push({x: -120, y: -86 - lift, w: 240, h: 28});
                if (ask.shown) {
                    out.push({x: askLabel.x - root.centerX, y: askLabel.y - root.centerY, w: askLabel.width, h: askLabel.height});
                    out.push({x: denyButton.x - root.centerX, y: denyButton.y - root.centerY, w: 54, h: 54});
                    out.push({x: allowButton.x - root.centerX, y: allowButton.y - root.centerY, w: 54, h: 54});
                }
                return out;
            }
            // Things it can look at besides the orb and the pointer: the small orbs.
            interests: [sat0, sat1, sat2, sat3, sat4].filter(o => o.shown).map(o => ({x: o.x + o.width / 2, y: o.y + o.height / 2}))
        }
        CompanionSurface {
            id: surface
            visible: !root.ui.docked || root.ui.dragging || dockFade.running
            dragging: root.ui.dragging
            interactionHeld: root.ui.controlPressed || chatAction.down || returnAction.down || voiceAction.down || hideAction.down
            property real displayedCenterX: root.centerX
            property real displayedCenterY: root.centerY
            x: (dockFade.running ? root.returnStartX : displayedCenterX) - width/2 + root.orbNudgeX
            y: (dockFade.running ? root.returnStartY : displayedCenterY) - height/2 + root.orbNudgeY
            scale: root.ui.reducedMotion ? 1 : 1-root.returnProgress*.55
            Behavior on displayedCenterX {
                enabled: !root.ui.dragging && !root.ui.reducedMotion && overlay.visible && root.motionReady
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            Behavior on displayedCenterY {
                enabled: !root.ui.dragging && !root.ui.reducedMotion && overlay.visible && root.motionReady
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }
            CompanionOrb {
                id: core
                anchors.centerIn: parent
                width: 84; height: 84
                hovered: root.expanded || grip.containsMouse
                playMood: kitten.withOrb ? kitten.orbMood : ""
                lookAt: {
                    if (!kitten.withOrb || !kitten.visible) return null;
                    const dx = kitten.centerX - root.centerX, dy = kitten.centerY - root.centerY;
                    const len = Math.max(1, Math.hypot(dx, dy));
                    const k = Math.min(1, len / 60);
                    return {x: dx / len * k, y: dy / len * k};
                }
                ambientMotion: overlay.visible && !root.ui.docked
            }
            CompanionDragArea {
                id: grip
                anchors.centerIn: parent
                width: 88; height: 88
                orbAnchor: core
                fromIsland: false
            }
            CompanionFileDrop {
                anchors.centerIn: parent
                width: 104; height: 104
                z: 5
            }
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                // Above the small orbs when there are any, so the two never overlap.
                readonly property real lift: root.satellitesShown && root.satelliteOffsets.length > 0 ? 58 : 0
                y: 18 - lift
                width: Math.min(260, stateLabel.implicitWidth+20)
                height: 28; radius: 14
                visible: !root.ui.dragging && !root.ui.approvalNeeded && root.centerY > 92 + lift && (root.expanded || root.voice.active || root.ui.fileHover)
                color: Appearance.m3colors.m3surfaceContainerHigh
                StyledText {
                    id: stateLabel
                    anchors.centerIn: parent
                    width: parent.width-20
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnSurface
                    text: root.ui.fileHover ? root.ui.label
                        : root.ui.phase === "listening" ? Translation.tr("Listening")
                        : root.ui.phase === "speaking" ? Translation.tr("Click to interrupt") : root.ui.label
                }
            }
            Rectangle {
                x: parent.width/2+16; y: parent.height/2+16
                width: 24; height: 24; radius: 12
                visible: root.ui.fileHover || root.ui.attachmentCount > 0 || Ai.attachmentWorkPending
                color: Appearance.colors.colTertiaryContainer
                StyledText {
                    anchors.centerIn: parent
                    text: Ai.attachmentWorkPending ? "…" : root.ui.fileHover ? "+" : String(root.ui.attachmentCount)
                    color: Appearance.colors.colOnTertiaryContainer
                    font.pixelSize: Appearance.font.pixelSize.small
                }
            }
            Item {
                id: orbit
                anchors.fill: parent
                property real spread: root.expanded ? 1 : 0
                Behavior on spread {
                    enabled: !root.ui.reducedMotion
                    NumberAnimation { duration: root.expanded ? 260 : 170; easing.type: Easing.OutCubic }
                }
                opacity: root.expanded ? 1 : 0
                visible: opacity > .01
                enabled: root.expanded
                Behavior on opacity { NumberAnimation { duration: 120 } }
                OrbitButton {
                    id: chatAction
                    slot: 0
                    text: "chat_bubble"; tip: Translation.tr("Open conversation")
                    onClicked: root.ui.transcript()
                }
                OrbitButton {
                    id: returnAction
                    slot: 2
                    text: "vertical_align_top"; tip: Translation.tr("Return to island")
                    enabled: root.ui.canDock
                    onClicked: root.ui.dock()
                }
                OrbitButton {
                    id: voiceAction
                    slot: 1
                    colBackground: Appearance.colors.colPrimaryContainer
                    colText: Appearance.colors.colOnPrimaryContainer
                    text: root.voice.active ? "stop" : "mic"
                    tip: root.voice.active ? Translation.tr("Stop conversation") : Translation.tr("Start talking")
                    onClicked: root.voice.active ? root.voice.stop() : root.ui.toggle()
                }
                OrbitButton {
                    id: hideAction
                    slot: 3
                    text: "close"; tip: Translation.tr("Hide companion")
                    onClicked: root.ui.hide()
                }
            }
        }
    }
    component OrbitButton: IconToolbarButton {
        property string tip: ""
        property int slot: 0
        readonly property real offsetX: root.orbitPositions[slot].x
        readonly property real offsetY: root.orbitPositions[slot].y
        readonly property real reveal: root.ui.reducedMotion ? 1 : .7 + .3*orbit.spread
        width: 44; height: 44; iconSize: 22
        animationsEnabled: !root.ui.reducedMotion
        x: Math.max(24, Math.min(root.bounds.width-24, surface.x+surface.width/2+offsetX*reveal))-surface.x-width/2
        y: Math.max(24, Math.min(root.bounds.height-24, surface.y+surface.height/2+offsetY*reveal))-surface.y-height/2
        buttonRadius: hovered ? 16 : 22
        buttonRadiusPressed: 16
        colBackground: Appearance.m3colors.m3surfaceContainerHigh
        colText: Appearance.colors.colOnSurface
        Accessible.name: tip
        scale: (root.ui.reducedMotion ? 1 : .88+.12*orbit.spread)
            * (enabled && down ? .96 : hovered && !root.ui.reducedMotion ? 1.04 : 1)
        Behavior on scale { enabled: !root.ui.reducedMotion; NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        StyledToolTip { text: parent.tip }
    }
}

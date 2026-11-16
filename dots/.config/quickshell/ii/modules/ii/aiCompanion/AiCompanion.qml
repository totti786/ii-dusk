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
    readonly property bool expanded: root.controlsOpen && !root.ui.dragging
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
        function dock(): bool { return root.ui.dock(); }
        function undock(): void { root.ui.undock(); }
        function status(): string {
            return JSON.stringify({visible: root.saved.visible, docked: root.ui.docked, canDock: root.ui.canDock,
                dragging: root.ui.dragging, nearDock: root.ui.nearDock, dockTarget: root.ui.dockTarget,
                timings: root.voice.timings, attachments: root.ui.attachmentCount, fileHover: root.ui.fileHover,
                state: root.ui.phase, active: root.voice.active, level: root.ui.level, error: root.voice.errorText,
                x: surface.x, y: surface.y, width: surface.width, height: surface.height,
                mapped: overlay.visible, opacity: surface.opacity, returning: dockFade.running,
                centerX: root.centerX, centerY: root.centerY, monitor: overlay.screen?.name ?? "",
                backend: Ai.voiceService.backendName, voiceAvailable: Ai.voiceService.available});
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
        id: overlay
        screen: Quickshell.screens.find(screen => screen.name === (root.ui.dragging ? root.ui.dragMonitor : root.saved.monitor))
            ?? Quickshell.screens.find(screen => screen.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        anchors { top: true; bottom: true; left: true; right: true }
        visible: Persistent.ready && root.saved.visible && (!root.ui.docked || root.ui.dragging || dockFade.running)
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
        mask: Region {
            item: root.ui.dragging ? (root.ui.dragFromIsland ? null : fullWindow)
                : root.ui.docked ? null : surface.inputArea
        }
        Item { id: fullWindow; anchors.fill: parent }
        CompanionSurface {
            id: surface
            dragging: root.ui.dragging
            interactionHeld: root.ui.controlPressed || chatAction.down || returnAction.down || voiceAction.down || hideAction.down
            property real displayedCenterX: root.centerX
            property real displayedCenterY: root.centerY
            x: (dockFade.running ? root.returnStartX : displayedCenterX) - width/2
            y: (dockFade.running ? root.returnStartY : displayedCenterY) - height/2
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
                y: 18
                width: Math.min(260, stateLabel.implicitWidth+20)
                height: 28; radius: 14
                visible: !root.ui.dragging && root.centerY > 92 && (root.expanded || root.voice.active || root.ui.fileHover)
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
                        : root.ui.phase === "listening" ? Translation.tr("Listening · click to send")
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

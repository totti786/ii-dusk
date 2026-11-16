pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.ii.dynamicIsland.core
import "../../modules/ii/aiCompanion/CompanionPlacement.js" as Placement
import "../../modules/ii/aiCompanion/CompanionFiles.js" as Files

/** One presentation owner: island bubble, floating orb, or drag preview. */
Singleton {
    id: root
    readonly property var saved: Persistent.states.aiCompanion
    readonly property var voice: Ai.companionVoice
    readonly property bool reducedMotion: Appearance.reducedMotion || Config.options.sidebar.ai.reducedMotion
    readonly property string phase: voice.state === "idle" && Ai.speechService.speaking ? Ai.speechService.phase : voice.state
    readonly property real level: Ai.speechService.speaking ? Ai.speechService.level : voice.level
    readonly property bool canDock: IslandPolicy.enabled && IslandPolicy.auxiliaryBubble && IslandPolicy.widgetEnabled("companion")
    readonly property bool docked: root.saved.docked && root.canDock
    readonly property string label: {
        if (root.fileHover) return Translation.tr("Drop files to attach");
        switch (root.phase) {
        case "starting": return Translation.tr("Opening microphone");
        case "listening": return Translation.tr("Listening");
        case "transcribing": return Translation.tr("Understanding");
        case "reading-files": return Translation.tr("Reading files");
        case "thinking": return Translation.tr("Thinking");
        case "preparing": return Translation.tr("Preparing voice");
        case "speaking": return Translation.tr("Speaking");
        case "attention": return Translation.tr("Approval needed");
        case "error": return Translation.tr("Tap to retry");
        default: return Translation.tr("Ready to talk");
        }
    }
    readonly property string symbol: phase === "listening" ? "mic" : phase === "speaking" ? "volume_up"
        : phase === "attention" ? "approval" : phase === "error" ? "error" : phase === "thinking" || phase === "transcribing" ? "more_horiz" : "graphic_eq"
    signal docking()
    property bool fileHover: false
    readonly property int attachmentCount: Ai.attachments.length
    function attachFiles(urls): bool {
        const paths = Files.localPaths(urls);
        if (paths.length === 0) return false;
        for (const path of paths) Ai.attachFile(path);
        root.transcript();
        return true;
    }
    property bool dragging: false
    property bool dragFromIsland: false
    property bool controlPressed: false
    property string dragMonitor: ""
    property real dragX: 0
    property real dragY: 0
    property real startX: 0
    property real startY: 0
    property real pointerX: 0
    property real pointerY: 0
    property var dockTarget: null
    property var dragDockTarget: null
    readonly property var activeDockTarget: root.dragging ? root.dragDockTarget : root.dockTarget
    readonly property bool nearDock: root.dragging && root.canDock && root.activeDockTarget !== null
        && root.dragMonitor === root.activeDockTarget.monitor
        && Placement.nearDock(root.dragX, root.dragY, root.activeDockTarget, 64)

    function screenBounds(screen): var {
        const monitor = Hyprland.monitorFor(screen);
        return {x: monitor?.x ?? 0, y: monitor?.y ?? 0, width: screen?.width ?? 1920, height: screen?.height ?? 1080};
    }
    function screenAt(x, y): var {
        return Quickshell.screens.find(screen => {
            const b = root.screenBounds(screen);
            return x >= b.x && x < b.x + b.width && y >= b.y && y < b.y + b.height;
        }) ?? Quickshell.screens.find(screen => screen.name === root.saved.monitor) ?? Quickshell.screens[0];
    }
    function publishDockTarget(monitor, x, y, width, height): void {
        const old = root.dockTarget;
        if (old && old.monitor === monitor && Math.abs(old.x-x) < .5 && Math.abs(old.y-y) < .5 && old.width === width && old.height === height) return;
        root.dockTarget = {monitor: monitor, x: x, y: y, width: width, height: height};
    }
    function show(): void {
        root.saved.visible = true;
        if (!root.saved.monitor) root.saved.monitor = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        Ai.voiceService.ensureDetected();
    }
    function hide(): void { root.voice.stop(); root.dragging = false; root.controlPressed = false; root.saved.visible = false; }
    function toggle(): void { root.show(); root.voice.toggle(); }
    function transcript(): void { Ai.surfaceRouter.open({surface: "sidebar", focusIntent: "composer"}); }
    function dock(): bool {
        if (!root.canDock) return false;
        root.docking();
        root.saved.docked = true;
        root.saved.visible = true;
        root.saved.monitor = root.dockTarget?.monitor ?? root.saved.monitor;
        return true;
    }
    function place(x, y, screen, snap = true): void {
        if (!screen) return;
        const bounds = root.screenBounds(screen);
        const point = snap ? Placement.settle(x, y, bounds, 38) : Placement.constrain(x, y, bounds, 38);
        const ratios = Placement.ratios(point, bounds, 38);
        root.saved.monitor = screen.name;
        root.saved.xRatio = ratios.x;
        root.saved.yRatio = ratios.y;
    }
    function undock(): void {
        const target = root.dockTarget;
        if (target) root.place(target.x + target.width/2, target.y + target.height + 100, root.screenAt(target.x, target.y));
        root.saved.docked = false;
        root.show();
    }
    function beginDrag(x, y, centerX, centerY, monitor, fromIsland): void {
        root.pointerX = x; root.pointerY = y;
        root.startX = centerX; root.startY = centerY;
        root.dragX = centerX; root.dragY = centerY;
        root.dragMonitor = monitor;
        root.dragFromIsland = fromIsland;
        root.dragDockTarget = root.dockTarget;
        root.dragging = true;
    }
    function moveDrag(x, y): void {
        if (!root.dragging) return;
        root.dragX = root.startX + x-root.pointerX;
        root.dragY = root.startY + y-root.pointerY;
        root.dragMonitor = root.screenAt(root.dragX, root.dragY)?.name ?? root.dragMonitor;
    }
    function finishDrag(): void {
        if (!root.dragging) return;
        const dock = root.nearDock;
        root.place(root.dragX, root.dragY, root.screenAt(root.dragX, root.dragY));
        if (dock && !root.docked) root.docking();
        root.saved.docked = dock;
        root.dragging = false;
        root.dragFromIsland = false;
        root.controlPressed = false;
    }
    function cancelDrag(): void {
        root.dragging = false; root.dragFromIsland = false; root.controlPressed = false;
    }
    Connections {
        target: GlobalStates
        function onScreenLockedChanged() { if (GlobalStates.screenLocked) root.cancelDrag(); }
    }
}

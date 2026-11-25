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
        case "listening":
            if (!root.voice.oneShot) return Translation.tr("Listening");
            if (!root.voice.holdHeld) return Translation.tr("Finishing recording…");
            return root.voice.captureReady ? Translation.tr("Release to send") : Translation.tr("Starting microphone…");
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
    // ── Personality ─────────────────────────────────────────────────────────────
    // One mood word for the creature: a forced one (IPC, for checking each face), then the
    // voice session's short-lived reactions, then a flinch at a new notification, then the
    // slow states: worried on a nearly empty battery, drowsy in the small hours.
    property string moodForced: ""
    property string startle: ""
    property int hourNow: new Date().getHours()
    readonly property bool lowBattery: Battery.available && !Battery.isCharging && Battery.percentage <= 0.15
    readonly property string mood: root.moodForced || root.voice.mood || root.startle
        || (root.lowBattery ? "worried" : root.hourNow < 5 ? "night" : "")
    Timer { interval: 300000; running: true; repeat: true; onTriggered: root.hourNow = new Date().getHours() }
    Timer { id: startleTimer; interval: 1500; onTriggered: root.startle = "" }
    Connections {
        target: Notifications
        function onNotify() {
            if (root.voice.active || Notifications.effectiveSilent) return;
            root.startle = "startled";
            startleTimer.restart();
        }
    }

    // ── Approvals: what the agent is waiting on, answered from the orb ──────────
    property var approval: null
    readonly property bool approvalNeeded: root.approval !== null

    /** The newest approval card still waiting on the user, or null. */
    function findApproval(): var {
        const ids = Ai.messageIDs;
        for (let i = ids.length - 1; i >= 0; i--) {
            const message = Ai.messageByID[ids[i]];
            for (const card of Array.from(message?.toolCards ?? [])) {
                if (card.kind === "opencodeShellApproval" && card.state === "pending")
                    return {message: message, callId: String(card.callId), tool: String(card.data?.tool ?? ""),
                            input: card.data?.input ?? ({})};
            }
        }
        return null;
    }
    function short(text: string, limit: int): string {
        const flat = String(text ?? "").replace(/\s+/g, " ").trim();
        return flat.length > limit ? flat.slice(0, limit - 1) + "…" : flat;
    }
    /** What to show and say for an approval: a title, the detail to check, and a spoken phrase. */
    function describe(approval): var {
        const input = approval?.input ?? ({});
        switch (approval?.tool) {
        case "run_shell_command":
            return {title: Translation.tr("Run a command"), detail: root.short(input.command, 200),
                    spoken: Translation.tr("run a command"), mono: true};
        case "run_privileged_command":
            return {title: Translation.tr("Run as administrator"), detail: root.short(input.command, 200),
                    spoken: Translation.tr("run an administrator command"), mono: true, strict: true};
        case "write_file":
            return {title: Translation.tr("Write a file"), detail: root.short(input.path, 200),
                    spoken: Translation.tr("write a file"), mono: true};
        case "desktop_input":
            return {title: Translation.tr("Control mouse and keyboard"),
                    detail: root.short([input.action, input.key, input.text, input.x !== undefined ? input.x + "," + input.y : ""].filter(Boolean).join(" · "), 200),
                    spoken: Translation.tr("control the mouse and keyboard"), mono: false};
        case "desktop_capture":
            return {title: Translation.tr("Look at your screen"), detail: String(input.monitor ?? ""),
                    spoken: Translation.tr("take a screenshot"), mono: false};
        case "browser_call":
            return {title: Translation.tr("Use the browser"), detail: root.short(input.name, 120),
                    spoken: Translation.tr("use the browser"), mono: false};
        case "settings_set":
            return {title: Translation.tr("Change a setting"), detail: root.short(input.key, 120),
                    spoken: Translation.tr("change a setting"), mono: true};
        default:
            return {title: String(approval?.tool ?? "").replace(/_/g, " "),
                    detail: root.short(JSON.stringify(input), 160),
                    spoken: String(approval?.tool ?? "").replace(/_/g, " "), mono: false};
        }
    }
    function refreshApproval(): void {
        // Only while the orb's own run is in flight: the run coordinator never marks a
        // shell approval as "needs action", so the cards themselves are the signal.
        root.approval = root.voice.active && root.voice.runId.length > 0 ? root.findApproval() : null;
    }
    function answerApproval(allow: bool): bool {
        const pending = root.approval;
        if (!pending) return false;
        root.approval = null;
        Ai.answerShellApproval(pending.message, pending.callId, allow ? "once" : "reject");
        root.voice.approvalAnswered(allow);
        return true;
    }
    property Timer approvalWatch: Timer {
        interval: 300
        repeat: true
        running: root.voice.active && root.voice.runId.length > 0
        triggeredOnStart: true
        onTriggered: root.refreshApproval()
    }
    property Connections approvalState: Connections {
        target: root.voice
        function onRunIdChanged() { if (root.voice.runId.length === 0) root.approval = null; }
    }

    /** Ask the kitten to do something by name (sleep, toy, trick, pet, laser...). */
    signal kittenRequest(string name)
    function kittenPlay(name): bool {
        if (!root.saved.visible || root.docked) return false;
        root.kittenRequest(String(name));
        return true;
    }
    signal emerging(real fromX, real fromY)
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
    readonly property bool canAttachScreen: Config.options.ai.voice.screen === true && Ai.enabled
        && Ai.currentModelSupportsVision && !Ai.isGenerating && !GlobalStates.screenLocked
    function attachScreen(): void {
        if (!root.canAttachScreen) return;
        root.voice.stop();
        GlobalStates.snipForAiRequested();
    }
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
    /**
     * Bring the orb to a spot on a screen (a double-click on the desktop). Floating, it
     * glides there; docked in the island, it comes out of the bubble and settles at the
     * spot (the `emerging` signal carries where it left from). Hidden, it stays hidden.
     * Coordinates are the screen's own.
     */
    function summon(screen, x, y): bool {
        if (!screen || !root.saved.visible || root.dragging) return false;
        const b = root.screenBounds(screen);
        if (root.docked) {
            const target = root.dockTarget;
            root.place(b.x + x, b.y + y, screen, false);
            root.saved.docked = false;
            if (target) root.emerging(target.x + target.width / 2, target.y + target.height / 2);
            return true;
        }
        root.place(b.x + x, b.y + y, screen, false);
        return true;
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

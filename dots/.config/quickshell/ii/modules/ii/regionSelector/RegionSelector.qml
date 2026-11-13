pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.utils
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

Scope {
    id: root

    function dismiss() {
        GlobalStates.regionSelectorOpen = false
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    // Bumped on every open so grim starts before (or while) the overlay tree
    // is created, instead of waiting for RegionSelection to finish loading.
    property int captureToken: 0

    function beginCapture() {
        // Before the selector takes focus: focus-grabbed overlays (cheatsheet,
        // popups) close right after, but they are still in the screenshot.
        ShellRegions.freeze()
        root.captureToken += 1
    }

    function openSelector() {
        root.beginCapture()
        GlobalStates.regionSelectorOpen = true
    }

    Variants {
        model: Quickshell.screens

        delegate: Scope {
            id: monitorScope
            required property var modelData

            readonly property HyprlandMonitor monitor: Hyprland.monitorFor(monitorScope.modelData)
            property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
            readonly property bool monitorWantsSelector: !Config.options.regionSelector.showOnlyOnFocusedMonitor || monitorIsFocused
            // Keep the overlay tree after the first open so later screenshots
            // only wait on grim, not on rebuilding ~2k lines of QML.
            property bool stickyLoaded: false

            // Build the selector in the background a few seconds after the shell starts
            // (and after every reload), so the first screenshot does not pay for creating
            // ~2k lines of QML on the GUI thread while the screen is already frozen.
            Timer {
                interval: 5000
                running: true
                onTriggered: monitorScope.stickyLoaded = true
            }

            TempScreenshotProcess {
                id: captureProc
                running: false
                screen: monitorScope.modelData
                screenshotDir: Directories.screenshotTemp
                format: "ppm"
                screenshotPath: `${Directories.screenshotTemp}/image-${monitorScope.modelData.name}.ppm`
            }

            Connections {
                target: root
                function onCaptureTokenChanged() {
                    if (!monitorScope.monitorWantsSelector)
                        return
                    captureProc.recapture(root.captureToken)
                }
            }

            Loader {
                id: regionSelectorLoader
                active: (GlobalStates.regionSelectorOpen && monitorScope.monitorWantsSelector) || monitorScope.stickyLoaded
                asynchronous: !GlobalStates.regionSelectorOpen
                onLoaded: monitorScope.stickyLoaded = true

                sourceComponent: RegionSelection {
                    screen: monitorScope.modelData
                    screenshotPath: captureProc.screenshotPath
                    captureReady: captureProc.completed && captureProc.startedToken === root.captureToken
                    captureToken: root.captureToken
                    onDismiss: root.dismiss()
                    action: root.action
                    selectionMode: root.selectionMode
                }
            }
        }
    }

    function screenshot() {
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    // Whole focused monitor, no selector: grim -> save + clipboard, then the
    // same preview overlay the region path raises.
    readonly property string fullShotPath: `${Directories.screenshotTemp}/full-shot.png`
    property string fullShotMonitor: ""

    function fullscreen() {
        if (fullShotProc.running)
            return
        const name = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? ""
        if (name === "")
            return
        const q = StringUtils.shellSingleQuoteEscape
        const saveDir = (Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : (Directories.home + "/Pictures/Screenshots")).toString().replace(/^file:\/\//, "")
        root.fullShotMonitor = name
        ShellRegions.freeze()
        fullShotProc.command = ["bash", "-c", `mkdir -p '${q(Directories.screenshotTemp)}' '${q(saveDir)}' && grim -t png -o '${q(name)}' '${q(root.fullShotPath)}' && f='${q(saveDir)}'/Screenshot_$(date +%Y-%m-%d-%H-%M-%S).png && cp '${q(root.fullShotPath)}' "$f" && wl-copy < "$f" && notify-send -i camera-photo -t 4000 --hint=boolean:suppress-sound:true 'Screenshot saved' "Saved to: $f"`]
        fullShotProc.running = true
    }

    Process {
        id: fullShotProc
        onExited: exitCode => {
            if (exitCode !== 0)
                return
            ScreenshotAction.playShutterSound(ScreenshotAction.Action.Copy)
            if (Config.options.regionSelector.enableOverlay ?? true) {
                GlobalStates.screenshotOverlayMonitor = root.fullShotMonitor
                GlobalStates.screenshotOverlayImagePath = root.fullShotPath
                GlobalStates.screenshotOverlayRegionX = 0
                GlobalStates.screenshotOverlayRegionY = 0
                GlobalStates.screenshotOverlayRegionW = 0
                GlobalStates.screenshotOverlayRegionH = 0
                GlobalStates.screenshotOverlayOpen = true
            }
        }
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        root.openSelector()
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function record() {
        if (Config.options.screenRecord.useToolbar ?? false) {
            GlobalStates.openRecordingToolbar();
            return;
        }
        root.recordDirect();
    }

    function recordWithSound() {
        if (Config.options.screenRecord.useToolbar ?? false) {
            GlobalStates.openRecordingToolbar();
            return;
        }
        root.recordWithSoundDirect();
    }

    function recordDirect() {
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function recordWithSoundDirect() {
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    function edit() {
        root.action = RegionSelection.SnipAction.Edit
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        root.openSelector()
    }

    /** Grabs a region and attaches it to the chat. */
    function askAi() {
        root.action = RegionSelection.SnipAction.AskAI
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        GlobalStates.regionSelectorOpen = true
    }

    Connections {
        target: GlobalStates
        function onSnipForAiRequested() {
            root.askAi();
        }
        function onRecordRegionRequested(sound) {
            if (sound) {
                root.recordWithSoundDirect();
            } else {
                root.recordDirect();
            }
        }
    }

    IpcHandler {
        target: "region"

        function close() {
            root.dismiss()
        }

        function screenshot() {
            root.screenshot()
        }
        function fullscreen() {
            root.fullscreen()
        }
        function edit() {
            root.edit()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function askAi() {
            root.askAi()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
        function recordDirect() {
            root.recordDirect()
        }
        function recordWithSoundDirect() {
            root.recordWithSoundDirect()
        }
    }

    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    GlobalShortcut {
        name: "fullScreenshot"
        description: "Takes a screenshot of the focused monitor"
        onPressed: root.fullscreen()
    }
    GlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}

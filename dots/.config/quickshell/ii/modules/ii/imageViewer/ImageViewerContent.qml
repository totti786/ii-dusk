pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import QtQuick.Window
import Quickshell.Hyprland

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Looks at one image and the others in its folder. The folder is listed once, sorted the way
 * a file manager does; left and right walk it, the wheel zooms around the pointer, a drag
 * pans, a double click flips between fit and actual size. Formats Qt cannot read are
 * handed to the system's own viewer (Loupe) with one click.
 */
FocusScope {
    id: root

    signal closeRequested()

    // What Qt's own plugins and kimageformats (AVIF, HEIC, JXL, RAW, JPEG 2000, PSD...) read
    readonly property var extensions: ["jpg", "jpeg", "png", "webp", "gif", "bmp", "svg", "tif", "tiff", "avif", "heic", "heif", "jxl",
        "jp2", "qoi", "tga", "ico", "psd", "exr", "hdr", "dng", "cr2", "cr3", "nef", "arw", "orf", "rw2", "raf"]
    readonly property var animatedExtensions: ["gif", "webp"]

    property string path: ""
    property string folder: ""
    property var files: []
    property int index: -1
    property real zoom: 1               // 1 = fit the window
    property string notice: ""

    readonly property string name: root.path.split("/").pop()
    readonly property string ext: root.name.indexOf(".") >= 0 ? root.name.split(".").pop().toLowerCase() : ""
    readonly property bool animated: root.animatedExtensions.includes(root.ext)
    readonly property bool failed: root.animated ? anim.status === Image.Error : still.status === Image.Error
    readonly property bool ready: root.animated ? anim.status === AnimatedImage.Ready : still.status === Image.Ready
    readonly property size natural: root.animated ? Qt.size(anim.implicitWidth, anim.implicitHeight) : Qt.size(still.implicitWidth, still.implicitHeight)

    /// False while the (kept) window is hidden: the picture is dropped so it holds no memory
    readonly property bool shown: GlobalStates.imageViewerOpen

    /// The window fills its monitor: nothing but the picture is drawn. Read from the size, so
    /// leaving fullscreen any other way (the compositor's own key) is noticed too.
    readonly property bool immersive: {
        const w = root.Window.window;
        if (!w)
            return false;
        return Quickshell.screens.some(s => w.width >= s.width - 2 && w.height >= s.height - 2);
    }

    function toggleFullscreen(): void {
        Hyprland.dispatch("hl.dsp.window.fullscreen({ mode = 0, action = 'toggle' })");
    }

    focus: true

    function open(p: string): void {
        const clean = String(p ?? "").replace(/^file:\/\//, "");
        if (clean === "")
            return;
        root.path = clean;
        root.zoom = 1;
        const dir = clean.substring(0, clean.lastIndexOf("/")) || "/";
        if (dir !== root.folder) {
            root.folder = dir;
            root.files = [];
            lister.running = false;
            lister.command = ["sh", "-c", 'find "$1" -maxdepth 1 -type f -printf "%f\\n" | sort -V', "sh", dir];
            lister.running = true;
        } else {
            root.syncIndex();
        }
    }

    function syncIndex(): void {
        root.index = root.files.indexOf(root.name);
    }

    function step(delta: int): void {
        if (root.files.length === 0)
            return;
        const next = (root.index + delta + root.files.length) % root.files.length;
        root.path = root.folder + "/" + root.files[next];
        root.index = next;
        root.zoom = 1;
    }

    function say(text: string): void {
        root.notice = text;
        noticeTimer.restart();
    }

    function zoomBy(factor: real, cx: real, cy: real): void {
        const old = root.zoom;
        const z = Math.max(1, Math.min(32, old * factor));
        if (z === old)
            return;
        // Keep the point under the pointer where it is
        const px = (view.contentX + cx) / view.contentWidth;
        const py = (view.contentY + cy) / view.contentHeight;
        root.zoom = z;
        view.returnToBounds();
        view.contentX = px * view.contentWidth - cx;
        view.contentY = py * view.contentHeight - cy;
        view.returnToBounds();
    }

    function actualSize(): real {
        const fit = Math.min(view.width / Math.max(1, root.natural.width), view.height / Math.max(1, root.natural.height));
        return fit > 0 ? Math.max(1, 1 / fit) : 1;
    }

    function toggleActual(cx: real, cy: real): void {
        if (root.zoom > 1.01)
            root.zoomBy(1 / root.zoom, cx, cy);
        else
            root.zoomBy(root.actualSize(), cx, cy);
    }

    function trash(): void {
        if (root.path === "")
            return;
        const gone = root.name;
        run.command = ["gio", "trash", root.path];
        run.after = () => {
            root.files = root.files.filter(f => f !== gone);
            if (root.files.length === 0) {
                root.closeRequested();
                return;
            }
            const next = Math.min(root.index, root.files.length - 1);
            root.path = root.folder + "/" + root.files[next];
            root.index = next;
            root.zoom = 1;
            root.say(Translation.tr("Moved to trash"));
        };
        run.running = true;
    }

    function copyImage(): void {
        run.command = ["sh", "-c", 'wl-copy --type "$(file -b --mime-type "$1")" < "$1"', "sh", root.path];
        run.after = () => root.say(Translation.tr("Copied to clipboard"));
        run.running = true;
    }

    function setWallpaper(): void {
        Wallpapers.select(root.path);
        root.say(Translation.tr("Wallpaper set"));
    }

    Process {
        id: lister
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                root.files = text.split("\n").filter(n => n.length > 0
                    && root.extensions.includes(n.split(".").pop().toLowerCase()));
                root.syncIndex();
            }
        }
    }

    Process {
        id: run
        property var after: null
        onExited: code => {
            if (code === 0 && run.after)
                run.after();
            else if (code !== 0)
                root.say(Translation.tr("That did not work"));
        }
    }

    Timer {
        id: noticeTimer
        interval: 2500
        onTriggered: root.notice = ""
    }

    Component.onCompleted: {
        root.open(GlobalStates.imageViewerPath);
        root.forceActiveFocus();
    }

    Connections {
        target: GlobalStates
        function onImageViewerRequestChanged() {
            root.open(GlobalStates.imageViewerPath);
            root.forceActiveFocus();
        }
    }

    // Window-wide shortcuts rather than key handlers on an item: whichever item inside the
    // window has focus (or none, right after opening), the keys still arrive
    Shortcut { sequences: ["Ctrl+W", "Ctrl+Q"]; onActivated: root.closeRequested() }
    // Escape steps out of fullscreen first, and only then closes
    Shortcut { sequences: ["Escape"]; onActivated: root.immersive ? root.toggleFullscreen() : root.closeRequested() }
    Shortcut { sequences: ["F", "F11", "Return"]; onActivated: root.toggleFullscreen() }
    Shortcut { sequences: ["Right", "Down", "Space", "PgDown"]; onActivated: root.step(1) }
    Shortcut { sequences: ["Left", "Up", "PgUp"]; onActivated: root.step(-1) }
    Shortcut { sequences: ["Home"]; onActivated: if (root.files.length > 0) { root.index = -1; root.step(1); } }
    Shortcut { sequences: ["End"]; onActivated: if (root.files.length > 0) { root.index = 0; root.step(-1); } }
    Shortcut { sequences: ["+", "=", "Ctrl++"]; onActivated: root.zoomBy(1.25, view.width / 2, view.height / 2) }
    Shortcut { sequences: ["-", "Ctrl+-"]; onActivated: root.zoomBy(0.8, view.width / 2, view.height / 2) }
    Shortcut { sequences: ["0"]; onActivated: root.zoomBy(1 / root.zoom, view.width / 2, view.height / 2) }
    Shortcut { sequences: ["1"]; onActivated: root.toggleActual(view.width / 2, view.height / 2) }
    Shortcut { sequences: ["Delete"]; onActivated: root.trash() }
    Shortcut { sequences: ["Ctrl+C"]; onActivated: root.copyImage() }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: root.immersive ? 0 : ClockStyle.paneGap
        anchors.topMargin: root.immersive ? 0 : ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            visible: !root.immersive
            Layout.fillWidth: true
            title: root.name !== "" ? root.name : Translation.tr("Image viewer")
            subtitle: {
                const bits = [];
                if (root.files.length > 1 && root.index >= 0)
                    bits.push(`${root.index + 1} / ${root.files.length}`);
                if (root.ready && root.natural.width > 0)
                    bits.push(`${root.natural.width} × ${root.natural.height}`);
                if (root.zoom > 1.01)
                    bits.push(`${Math.round(root.zoom * 100)}% of fit`);
                return bits.join("  ·  ");
            }
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                symbol: "fullscreen"
                tooltip: Translation.tr("Fullscreen (F)")
                onClicked: root.toggleFullscreen()
            }
            ClockIconButton {
                symbol: "content_copy"
                tooltip: Translation.tr("Copy image (Ctrl+C)")
                onClicked: root.copyImage()
            }
            ClockIconButton {
                symbol: "wallpaper"
                tooltip: Translation.tr("Set as wallpaper")
                onClicked: root.setWallpaper()
            }
            ClockIconButton {
                symbol: "folder_open"
                tooltip: Translation.tr("Show in folder")
                onClicked: Quickshell.execDetached(["xdg-open", root.folder])
            }
            ClockIconButton {
                symbol: "delete"
                tooltip: Translation.tr("Move to trash (Delete)")
                onClicked: root.trash()
            }
        }

        // ── the picture ──
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: root.immersive ? 0 : ClockStyle.radiusCard
            color: root.immersive ? "black" : "#0c0c0c"
            clip: true

            Flickable {
                id: view
                anchors.fill: parent
                contentWidth: Math.max(width, width * root.zoom)
                contentHeight: Math.max(height, height * root.zoom)
                interactive: root.zoom > 1.01
                boundsBehavior: Flickable.StopAtBounds
                clip: true

                Item {
                    width: view.contentWidth
                    height: view.contentHeight

                    Image {
                        id: still
                        anchors.fill: parent
                        visible: !root.animated
                        source: !root.animated && root.shown && root.path !== "" ? "file://" + root.path : ""
                        fillMode: Image.PreserveAspectFit
                        autoTransform: true
                        asynchronous: true
                        mipmap: true
                        cache: false
                    }
                    AnimatedImage {
                        id: anim
                        anchors.fill: parent
                        visible: root.animated
                        source: root.animated && root.shown && root.path !== "" ? "file://" + root.path : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        cache: false
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                onWheel: wheel => {
                    if (wheel.modifiers & Qt.ControlModifier || root.zoom > 1.01 || wheel.angleDelta.y !== 0) {
                        root.zoomBy(wheel.angleDelta.y > 0 ? 1.15 : 1 / 1.15, wheel.x, wheel.y);
                        wheel.accepted = true;
                    }
                }
            }

            // two fingers on the touchpad (or touchscreen): zoom around the pinch centre
            PinchHandler {
                id: pinch
                target: null
                property real last: 1
                onActiveChanged: if (active) pinch.last = 1
                onActiveScaleChanged: {
                    const f = pinch.activeScale / pinch.last;
                    pinch.last = pinch.activeScale;
                    root.zoomBy(f, pinch.centroid.position.x, pinch.centroid.position.y);
                }
            }

            // Fullscreen: one quiet line at the foot, there while the pointer moves
            Rectangle {
                visible: root.immersive
                opacity: hover.moving ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(250) } }
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 18 }
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.55)
                implicitHeight: 30
                implicitWidth: hudText.implicitWidth + 28
                StyledText {
                    id: hudText
                    anchors.centerIn: parent
                    color: Qt.rgba(1, 1, 1, 0.85)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    text: (root.files.length > 1 && root.index >= 0 ? `${root.index + 1} / ${root.files.length}   ·   ` : "") + root.name
                }
            }

            // Fullscreen: the pointer goes away after a moment of stillness
            HoverHandler {
                id: hover
                cursorShape: root.immersive && !hover.moving ? Qt.BlankCursor : Qt.ArrowCursor
                property bool moving: true
                onPointChanged: { hover.moving = true; idle.restart(); }
            }
            Timer {
                id: idle
                interval: 1800
                onTriggered: hover.moving = false
            }

            // double click flips fit / actual size; a plain click stays free for dragging
            TapHandler {
                acceptedButtons: Qt.LeftButton
                onDoubleTapped: (point) => root.toggleActual(point.position.x, point.position.y)
            }

            BusyIndicator {
                anchors.centerIn: parent
                running: root.path !== "" && !root.ready && !root.failed
                visible: running
            }

            ColumnLayout {
                visible: root.failed
                anchors.centerIn: parent
                spacing: 10
                MaterialSymbol { Layout.alignment: Qt.AlignHCenter; text: "broken_image"; iconSize: 48; color: ClockStyle.colSubtext }
                StyledText { Layout.alignment: Qt.AlignHCenter; text: Translation.tr("Can't open this format here"); color: ClockStyle.colOnSurface }
                ClockButton {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: "open_in_new"
                    label: Translation.tr("Open in Loupe")
                    onClicked: Quickshell.execDetached(["loupe", root.path])
                }
            }

            ClockEmptyState {
                visible: root.path === ""
                anchors.centerIn: parent
                symbol: "image"
                title: Translation.tr("No image open")
                subtitle: Translation.tr("Open a file with: qs -c ii ipc call imageViewer open <path>")
            }

            // previous / next, shown on hover
            Repeater {
                model: [{ side: "left", sym: "chevron_left", d: -1 }, { side: "right", sym: "chevron_right", d: 1 }]
                delegate: Rectangle {
                    id: arrow
                    required property var modelData
                    visible: root.files.length > 1 && !root.immersive
                    anchors.verticalCenter: parent.verticalCenter
                    x: modelData.side === "left" ? 12 : parent.width - width - 12
                    width: 44
                    height: 44
                    radius: arrowArea.pressed ? Appearance.rounding.normal : height / 2
                    color: Qt.rgba(0, 0, 0, arrowArea.containsMouse ? 0.7 : 0.4)
                    scale: arrowArea.pressed ? 0.94 : 1
                    Behavior on radius {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                    Behavior on scale {
                        animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                    }
                    MaterialSymbol { anchors.centerIn: parent; text: arrow.modelData.sym; iconSize: 26; color: "white" }
                    MouseArea {
                        id: arrowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.step(arrow.modelData.d)
                    }
                }
            }

            Rectangle {
                visible: root.notice !== ""
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 14 }
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.65)
                implicitHeight: 32
                implicitWidth: noticeText.implicitWidth + 28
                StyledText { id: noticeText; anchors.centerIn: parent; text: root.notice; color: "white" }
            }
        }
    }
}

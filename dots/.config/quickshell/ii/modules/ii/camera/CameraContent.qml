pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtMultimedia
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * A webcam viewfinder with photo and video capture. The camera is only active while this
 * view exists, so closing the window releases the device. Photos go to ~/Pictures/Camera,
 * videos to ~/Videos/Camera.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property string home: String(Quickshell.env("HOME") || "")
    readonly property string photoDir: root.home + "/Pictures/Camera"
    readonly property string videoDir: root.home + "/Videos/Camera"

    property bool videoMode: false
    property bool mirror: true
    property int timerSeconds: 0          // 0, 3, 5 or 10
    property int countdown: 0
    property string lastPath: ""
    property string notice: ""
    property int deviceIndex: 0
    /// Whether mirroring was on when the current photo or video was started
    property bool shotMirrored: false
    /// The newest photo or video, for the thumbnail beside the shutter
    property string latest: ""
    readonly property bool latestIsVideo: root.latest.endsWith(".mp4")

    readonly property var devices: mediaDevices.videoInputs
    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState
    property int recordSeconds: 0

    focus: true

    function stamp(): string {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_HH-mm-ss");
    }

    function say(text: string): void {
        root.notice = text;
        noticeTimer.restart();
    }

    function shoot(): void {
        if (root.videoMode) {
            root.toggleRecording();
            return;
        }
        if (root.countdown > 0)
            return;
        if (root.timerSeconds > 0) {
            root.countdown = root.timerSeconds;
            tick.restart();
        } else {
            root.capturePhoto();
        }
    }

    function capturePhoto(): void {
        mkdir.command = ["mkdir", "-p", root.photoDir];
        mkdir.next = () => {
            const path = root.photoDir + "/IMG_" + root.stamp() + ".jpg";
            root.lastPath = path;
            root.shotMirrored = root.mirror;
            capture.captureToFile(path);
        };
        mkdir.running = true;
    }

    function toggleRecording(): void {
        if (root.recording) {
            recorder.stop();
            return;
        }
        mkdir.command = ["mkdir", "-p", root.videoDir];
        mkdir.next = () => {
            root.lastPath = root.videoDir + "/VID_" + root.stamp() + ".mp4";
            root.shotMirrored = root.mirror;
            recorder.outputLocation = "file://" + root.lastPath;
            recorder.record();
        };
        mkdir.running = true;
    }

    /// The viewfinder is flipped in the scene graph, so the file comes out unflipped; when
    /// mirroring is on, flip the saved file too so it matches what was on screen.
    property var flipQueue: []

    function noteSaved(path: string): void {
        // Drop and re-set the source: a mirrored file is rewritten under the same name
        root.latest = "";
        Qt.callLater(() => root.latest = path);
    }

    function saved(path: string, mirrored: bool): void {
        if (mirrored) {
            root.flipQueue = root.flipQueue.concat([path]);
            root.flipNext();
        } else {
            root.noteSaved(path);
            root.say(Translation.tr("Saved ") + path.split("/").pop());
        }
    }

    function openLatest(): void {
        if (root.latest === "")
            return;
        if (root.latestIsVideo)
            Quickshell.execDetached(["xdg-open", root.latest]);
        else
            GlobalStates.openImageViewerApp(root.latest);
    }

    function flipNext(): void {
        if (flip.running || root.flipQueue.length === 0)
            return;
        const path = root.flipQueue[0];
        root.flipQueue = root.flipQueue.slice(1);
        const ext = path.slice(path.lastIndexOf("."));
        const tmp = path + ".flip" + ext;
        flip.path = path;
        flip.command = ["sh", "-c", 'ffmpeg -y -loglevel error -i "$1" -vf hflip -q:v 2 -c:a copy "$2" && mv "$2" "$1"', "sh", path, tmp];
        root.say(Translation.tr("Mirroring…"));
        flip.running = true;
    }

    Process {
        id: flip
        property string path: ""
        onExited: code => {
            if (code === 0)
                root.noteSaved(flip.path);
            root.say(code === 0 ? Translation.tr("Saved ") + flip.path.split("/").pop() : Translation.tr("Could not mirror the file"));
            root.flipNext();
        }
    }

    // Whatever was taken last time, so the thumbnail is there from the start
    Process {
        id: newest
        command: ["sh", "-c", 'ls -t "$1"/*.jpg "$2"/*.mp4 2>/dev/null | head -1', "sh", root.photoDir, root.videoDir]
        running: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (root.latest === "" && text.trim() !== "") root.latest = text.trim()
        }
    }

    Process {
        id: mkdir
        property var next: null
        onExited: if (mkdir.next) mkdir.next()
    }

    MediaDevices {
        id: mediaDevices
    }

    CaptureSession {
        camera: Camera {
            id: camera
            active: true
            cameraDevice: root.devices.length > 0 ? root.devices[Math.min(root.deviceIndex, root.devices.length - 1)] : mediaDevices.defaultVideoInput
        }
        imageCapture: ImageCapture {
            id: capture
            onImageSaved: (id, path) => {
                shutterFlash.restart();
                root.saved(path, root.shotMirrored);
            }
            onErrorOccurred: (id, error, msg) => root.say(msg)
        }
        recorder: MediaRecorder {
            id: recorder
            quality: MediaRecorder.HighQuality
            onRecorderStateChanged: {
                if (recorderState === MediaRecorder.RecordingState) {
                    root.recordSeconds = 0;
                    recClock.start();
                } else {
                    recClock.stop();
                    if (root.lastPath !== "")
                        root.saved(root.lastPath, root.shotMirrored);
                }
            }
            onErrorOccurred: (error, msg) => root.say(msg)
        }
        videoOutput: viewfinder
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown -= 1;
            if (root.countdown <= 0) {
                tick.stop();
                root.capturePhoto();
            }
        }
    }

    Timer {
        id: recClock
        interval: 1000
        repeat: true
        onTriggered: root.recordSeconds += 1
    }

    Timer {
        id: noticeTimer
        interval: 3500
        onTriggered: root.notice = ""
    }

    Component.onDestruction: if (root.recording) recorder.stop()

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape || ((event.modifiers & Qt.ControlModifier) && (event.key === Qt.Key_W || event.key === Qt.Key_Q))) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Space || event.key === Qt.Key_Return) {
            root.shoot();
            event.accepted = true;
        } else if (event.key === Qt.Key_M) {
            root.mirror = !root.mirror;
            event.accepted = true;
        } else if (event.key === Qt.Key_V && !root.recording) {
            root.videoMode = !root.videoMode;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Camera")
            subtitle: root.devices.length > 0
                ? camera.cameraDevice.description
                : Translation.tr("No camera found")
            onCloseRequested: root.closeRequested()

            ClockIconButton {
                visible: root.devices.length > 1
                symbol: "cameraswitch"
                tooltip: Translation.tr("Switch camera")
                onClicked: root.deviceIndex = (root.deviceIndex + 1) % root.devices.length
            }
            ClockIconButton {
                symbol: "folder_open"
                tooltip: Translation.tr("Open folder")
                onClicked: Quickshell.execDetached(["xdg-open", root.videoMode ? root.videoDir : root.photoDir])
            }
        }

        // ── viewfinder ──
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: "black"
            clip: true

            VideoOutput {
                id: viewfinder
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
                transform: Scale {
                    origin.x: viewfinder.width / 2
                    xScale: root.mirror ? -1 : 1
                }
            }

            ClockEmptyState {
                anchors.centerIn: parent
                visible: root.devices.length === 0
                symbol: "videocam_off"
                title: Translation.tr("No camera found")
                subtitle: Translation.tr("Plug in a webcam")
            }

            // recording badge
            Rectangle {
                visible: root.recording
                anchors { top: parent.top; left: parent.left; margins: 12 }
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.55)
                implicitHeight: 28
                implicitWidth: badgeRow.implicitWidth + 20
                Row {
                    id: badgeRow
                    anchors.centerIn: parent
                    spacing: 7
                    Rectangle { width: 9; height: 9; radius: 4.5; color: Appearance.colors.colErrorContainer; anchors.verticalCenter: parent.verticalCenter }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        color: "white"
                        font.features: ({ "tnum": 1 })
                        text: String(Math.floor(root.recordSeconds / 60)).padStart(2, "0") + ":" + String(root.recordSeconds % 60).padStart(2, "0")
                    }
                }
            }

            // countdown
            StyledText {
                visible: root.countdown > 0
                anchors.centerIn: parent
                text: root.countdown
                color: "white"
                font.pixelSize: 120
                font.weight: Font.Bold
                style: Text.Outline
                styleColor: Qt.rgba(0, 0, 0, 0.5)
            }

            // notice
            Rectangle {
                visible: root.notice !== ""
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 12 }
                radius: height / 2
                color: Qt.rgba(0, 0, 0, 0.6)
                implicitHeight: 30
                implicitWidth: noticeText.implicitWidth + 24
                StyledText { id: noticeText; anchors.centerIn: parent; text: root.notice; color: "white" }
            }

            Rectangle {
                id: flash
                anchors.fill: parent
                color: "white"
                opacity: 0
                SequentialAnimation on opacity {
                    id: shutterFlash
                    running: false
                    NumberAnimation { to: 0.85; duration: Appearance.dur(40) }
                    NumberAnimation { to: 0; duration: Appearance.dur(260) }
                }
            }
        }

        // ── controls ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            // the last shot: opens in the viewer (a video in the player)
            ClippingRectangle {
                id: thumb
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 52
                implicitHeight: 52
                radius: width / 2
                color: ClockStyle.colSurfaceHigh
                clip: true
                visible: root.latest !== ""

                Image {
                    anchors.fill: parent
                    visible: !root.latestIsVideo
                    source: root.latest !== "" && !root.latestIsVideo ? "file://" + root.latest : ""
                    sourceSize: Qt.size(104, 104)
                    fillMode: Image.PreserveAspectCrop
                    autoTransform: true
                    asynchronous: true
                    cache: false
                }
                MaterialSymbol {
                    anchors.centerIn: parent
                    visible: root.latestIsVideo
                    text: "play_circle"
                    fill: 1
                    iconSize: 30
                    color: ClockStyle.colOnSurface
                }
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: "white"
                    opacity: thumbArea.containsMouse ? 0.12 : 0
                }
                MouseArea {
                    id: thumbArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openLatest()
                }
                StyledToolTip { text: root.latestIsVideo ? Translation.tr("Play the last video") : Translation.tr("Open the last photo") }
            }

            // photo / video
            Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter
                ClockChip {
                    symbol: "photo_camera"
                    label: Translation.tr("Photo")
                    selected: !root.videoMode
                    enabled: !root.recording
                    onClicked: root.videoMode = false
                }
                ClockChip {
                    symbol: "videocam"
                    label: Translation.tr("Video")
                    selected: root.videoMode
                    enabled: !root.recording
                    onClicked: root.videoMode = true
                }
            }

            Item { Layout.fillWidth: true }

            // shutter
            Rectangle {
                id: shutter
                Layout.alignment: Qt.AlignVCenter
                implicitWidth: 64
                implicitHeight: 64
                radius: 32
                color: "transparent"
                border.width: 3
                border.color: ClockStyle.colOnSurfaceVariant
                opacity: root.devices.length > 0 ? 1 : 0.4
                scale: shutterArea.pressed ? 0.92 : 1
                Behavior on scale {
                    animation: Appearance.animation.elementMoveSmall.numberAnimation.createObject(this)
                }

                Rectangle {
                    anchors.centerIn: parent
                    width: root.recording ? 26 : 50
                    height: width
                    radius: root.recording ? 6 : width / 2
                    color: root.videoMode ? Appearance.colors.colErrorContainer : ClockStyle.colOnSurfaceVariant
                    Behavior on width { NumberAnimation { duration: Appearance.dur(140); easing.type: Easing.OutCubic } }
                    Behavior on radius { NumberAnimation { duration: Appearance.dur(140) } }
                }
                MouseArea {
                    id: shutterArea
                    anchors.fill: parent
                    enabled: root.devices.length > 0
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shoot()
                }
            }

            Item { Layout.fillWidth: true }

            Row {
                spacing: 8
                Layout.alignment: Qt.AlignVCenter
                ClockIconButton {
                    symbol: "timer"
                    filled: root.timerSeconds > 0
                    toggled: root.timerSeconds > 0
                    visible: !root.videoMode
                    tooltip: root.timerSeconds > 0 ? Translation.tr("Timer: %1 s").arg(root.timerSeconds) : Translation.tr("Timer off")
                    onClicked: root.timerSeconds = root.timerSeconds === 0 ? 3 : root.timerSeconds === 3 ? 5 : root.timerSeconds === 5 ? 10 : 0
                }
                ClockIconButton {
                    symbol: "flip"
                    toggled: root.mirror
                    tooltip: Translation.tr("Mirror preview")
                    onClicked: root.mirror = !root.mirror
                }
            }
        }
    }
}

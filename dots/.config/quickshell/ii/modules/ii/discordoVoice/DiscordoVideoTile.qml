pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtMultimedia

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One person in the call. With a camera on it plays their video, otherwise it shows their picture.
 *
 * The helper serves each camera as MPEG-TS on a private unix socket and announces it as `videoUrl`.
 * The player runs in low-latency mode (about 200 ms behind). If frames stop for a few seconds, for
 * any reason, the player is reset: that reconnects, which also asks the sender for a fresh keyframe.
 * Nothing plays while `active` is false (the stage is hidden), so a hidden call costs no decoding.
 */
Item {
    id: root

    property string name: ""
    property string avatarUrl: ""
    property string videoUrl: ""
    property bool speaking: false
    property bool muted: false
    property bool deafened: false
    property bool isSelf: false
    property bool focused: false
    property bool active: true
    property bool canAdjustVolume: false
    // Your own camera, flipped left to right like a mirror
    property bool mirrored: false

    signal clicked()
    signal volumeClicked()
    signal mirrorClicked()

    readonly property bool hasVideo: root.videoUrl !== ""
    readonly property bool videoLive: videoLoader.item ? videoLoader.item.live : false
    readonly property real minSide: Math.min(root.width, root.height)
    readonly property bool hovered: hover.hovered

    Accessible.role: Accessible.Button
    Accessible.name: root.focused
        ? Translation.tr("%1, enlarged. Press to show everyone.").arg(root.name)
        : Translation.tr("%1. Press to enlarge.").arg(root.name)

    Rectangle {
        id: card
        anchors.fill: parent
        radius: ClockStyle.radiusCard
        color: ClockStyle.colSurfaceHigh
    }

    // Picture and name: what everyone without a camera looks like
    Item {
        anchors.fill: parent
        visible: !root.videoLive

        DiscordoAvatar {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: -Math.round(root.minSide * 0.06)
            size: Math.max(32, Math.min(120, Math.round(root.minSide * 0.42)))
            source: root.avatarUrl
            name: root.name
        }

        // A camera that is on but has not shown a picture yet
        MaterialLoadingIndicator {
            visible: root.hasVideo && root.active
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: ClockStyle.gapSmall
            implicitSize: 24
            color: ClockStyle.colPrimaryContainer
            shapeColor: ClockStyle.colOnPrimaryContainer
        }
    }

    // Rounded video: the player draws a rectangle, the mask rounds it
    Item {
        id: videoMask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        Rectangle {
            anchors.fill: parent
            radius: card.radius
        }
    }

    Loader {
        id: videoLoader
        anchors.fill: parent
        active: root.hasVideo && root.active
        // Hidden by opacity, not `visible`: an invisible output may stop receiving frames, and it would never go live
        opacity: root.videoLive ? 1 : 0
        layer.enabled: root.videoLive
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: videoMask
        }

        sourceComponent: Item {
            id: surface

            property bool live: false
            property real started: 0
            property real lastFrame: 0

            function restart(): void {
                surface.started = Date.now();
                surface.lastFrame = 0;
                surface.live = false;
                // Low latency is a playback option (Qt 6.10+); it has to be assigned as a whole
                const options = player.playbackOptions;
                options.playbackIntent = 1;
                options.probeSize = 32768;
                player.playbackOptions = options;
                player.source = "";
                player.source = root.videoUrl;
                player.play();
            }

            Rectangle {
                anchors.fill: parent
                color: "black"
            }

            MediaPlayer {
                id: player
                videoOutput: output
                Component.onCompleted: surface.restart()
                onErrorOccurred: retry.restart()
                onMediaStatusChanged: {
                    if (player.mediaStatus === MediaPlayer.EndOfMedia || player.mediaStatus === MediaPlayer.InvalidMedia)
                        retry.restart();
                }
            }

            VideoOutput {
                id: output
                anchors.fill: parent
                // Whole picture when enlarged, filled tile otherwise
                fillMode: root.focused ? VideoOutput.PreserveAspectFit : VideoOutput.PreserveAspectCrop
                // Only the picture is flipped, not the name or the buttons
                transform: Scale {
                    origin.x: output.width / 2
                    xScale: root.isSelf && root.mirrored ? -1 : 1
                }
            }

            Connections {
                target: output.videoSink
                function onVideoFrameChanged(): void {
                    surface.lastFrame = Date.now();
                    if (!surface.live)
                        surface.live = true;
                }
            }

            Connections {
                target: root
                function onVideoUrlChanged(): void {
                    if (root.videoUrl !== "")
                        surface.restart();
                }
            }

            // The server is gone for a moment, or the stream ended: try again shortly
            Timer {
                id: retry
                interval: 1000
                onTriggered: surface.restart()
            }

            // Frames stopped: show the picture again, and after a while reconnect
            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    const quiet = Date.now() - (surface.lastFrame > 0 ? surface.lastFrame : surface.started);
                    if (surface.live && quiet > 2500)
                        surface.live = false;
                    if (quiet > 6000)
                        surface.restart();
                }
            }
        }
    }

    // Name, and whether they can hear and be heard
    Rectangle {
        id: label
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: ClockStyle.gapSmall
        height: 28
        width: Math.min(labelRow.implicitWidth + ClockStyle.gap, parent.width - ClockStyle.gapSmall * 2)
        radius: height / 2
        color: Qt.alpha("black", 0.55)

        Row {
            id: labelRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: ClockStyle.gapSmall
            spacing: ClockStyle.gapTiny

            MaterialSymbol {
                anchors.verticalCenter: parent.verticalCenter
                visible: root.deafened || root.muted
                text: root.deafened ? "headset_off" : "mic_off"
                iconSize: ClockStyle.iconSmall
                color: "white"
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, root.width - ClockStyle.gapSmall * 4 - 28)
                text: root.name + (root.isSelf ? Translation.tr(" (you)") : "")
                elide: Text.ElideRight
                color: "white"
                font.pixelSize: ClockStyle.textSmall
                font.weight: root.speaking ? Font.DemiBold : Font.Medium
            }
        }
    }

    // Who is talking
    Rectangle {
        anchors.fill: parent
        radius: card.radius
        color: "transparent"
        border.width: root.speaking ? 3 : 0
        border.color: ClockStyle.colPrimary
        Behavior on border.width {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }

    // Volume and enlarge, shown on hover, or while enlarged
    Row {
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: ClockStyle.gapSmall
        spacing: ClockStyle.gapTiny
        opacity: root.hovered || root.focused ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }

        Repeater {
            model: [
                { "symbol": "flip", "enabled": root.isSelf && root.hasVideo, "name": root.mirrored ? Translation.tr("Stop mirroring your preview") : Translation.tr("Mirror your preview"), "action": "mirror" },
                { "symbol": "volume_up", "enabled": root.canAdjustVolume, "name": Translation.tr("Volume for %1").arg(root.name), "action": "volume" },
                { "symbol": root.focused ? "close_fullscreen" : "open_in_full", "enabled": true,
                    "name": root.focused ? Translation.tr("Show everyone") : Translation.tr("Enlarge %1").arg(root.name), "action": "focus" }
            ]

            delegate: Rectangle {
                id: action
                required property var modelData
                visible: action.modelData.enabled
                width: 32
                height: 32
                radius: 16
                color: actionArea.containsMouse ? Qt.alpha("black", 0.75) : Qt.alpha("black", 0.55)

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: action.modelData.symbol
                    iconSize: ClockStyle.iconSmall
                    color: "white"
                }

                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    Accessible.role: Accessible.Button
                    Accessible.name: action.modelData.name
                    onClicked: {
                        if (action.modelData.action === "volume")
                            root.volumeClicked();
                        else if (action.modelData.action === "mirror")
                            root.mirrorClicked();
                        else
                            root.clicked();
                    }
                }
            }
        }
    }
}

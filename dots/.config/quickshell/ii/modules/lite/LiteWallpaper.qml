pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * The Lite family's wallpaper: one still image per monitor, decoded at the monitor's own size
 * and nothing else. No widgets, no parallax, no blur copies, no video. A video wallpaper falls
 * back to the theme colour, since decoding it is exactly the cost this family avoids.
 */
Scope {
    id: root

    readonly property bool locked: GlobalStates.screenLocked
    // The lock screen's own picture when one is set; the session lock is transparent (xray), so
    // this window is what shows behind the password field.
    readonly property string desktopPath: Config.options?.background?.wallpaperPath ?? ""
    readonly property string lockPath: (Config.options?.background?.useSeparateLockscreenWallpaper ?? false)
        && (Config.options?.background?.lockscreenWallpaperPath ?? "") !== ""
        ? Config.options.background.lockscreenWallpaperPath : root.desktopPath
    readonly property string path: root.locked ? root.lockPath : root.desktopPath
    readonly property bool isImage: /\.(jpe?g|png|webp|bmp|gif|avif|jxl)$/i.test(root.path)

    Variants {
        model: GlobalStates.allowedScreens

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Background
            WlrLayershell.namespace: "quickshell:background"
            color: Appearance.colors.colLayer0Base

            Image {
                anchors.fill: parent
                visible: root.isImage
                source: root.isImage ? "file://" + root.path : ""
                sourceSize: Qt.size(modelData.width * 1, modelData.height * 1)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                mipmap: false
            }

            // Lock screen: dim the picture and show the time, which the ii family draws as a
            // desktop widget that this family does not load.
            Rectangle {
                anchors.fill: parent
                color: "black"
                opacity: root.locked ? 0.38 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(250); easing.type: Easing.OutCubic } }
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.2
                spacing: 4
                opacity: root.locked ? 1 : 0
                visible: opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Appearance.dur(250); easing.type: Easing.OutCubic } }

                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DateTime.time
                    color: "white"
                    font.pixelSize: Math.min(win.height * 0.17, 190)
                    font.weight: Font.Light
                }
                StyledText {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: DateTime.longDate
                    color: "white"
                    opacity: 0.85
                    font.pixelSize: 24
                }
            }
        }
    }
}

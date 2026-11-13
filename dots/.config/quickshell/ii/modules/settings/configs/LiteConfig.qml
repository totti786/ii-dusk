import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Everything specific to the Lite panel family: its automatic power saver, the apps it leaves out
 * until they are asked for, and a plain list of what it does without. The page only exists for the
 * family it configures.
 */
Item {
    id: liteRoot
    anchors.fill: parent

    property alias contentY: page.contentY

    // The apps Lite does not load unless asked to. Each switch is a key under lite.extras.
    readonly property var extras: [
        { key: "modes", icon: "tune", title: Translation.tr("Modes & routines"), hint: Translation.tr("Super+Alt+Y") },
        { key: "easyEffects", icon: "graphic_eq", title: Translation.tr("EasyEffects"), hint: Translation.tr("Super+Alt+E") },
        { key: "usage", icon: "bar_chart", title: Translation.tr("Usage"), hint: Translation.tr("Super+Alt+U") },
        { key: "health", icon: "monitor_heart", title: Translation.tr("System health"), hint: Translation.tr("Ctrl+Alt+H") },
        { key: "colorPicker", icon: "colorize", title: Translation.tr("Color picker"), hint: Translation.tr("Super+Shift+C") },
        { key: "displayModes", icon: "monitor", title: Translation.tr("Display modes"), hint: Translation.tr("Ctrl+Alt+D") },
        { key: "wallpaperSelector", icon: "wallpaper", title: Translation.tr("Wallpaper selector"), hint: "" }
    ]

    // What the desktop family has and Lite never loads, with the reason it stays out.
    readonly property var leftOut: [
        { icon: "dock_to_bottom", title: Translation.tr("Dock and Dynamic Island"), why: Translation.tr("Always-on surfaces that keep a window and effects alive") },
        { icon: "side_navigation", title: Translation.tr("Sidebars"), why: Translation.tr("Large panels with many widgets resident in memory") },
        { icon: "widgets", title: Translation.tr("Desktop widgets and wallpaper effects"), why: Translation.tr("Parallax, blur copies and widget windows cost the most RAM") },
        { icon: "grid_view", title: Translation.tr("Overview"), why: Translation.tr("Live window thumbnails; the launcher replaces it") },
        { icon: "album", title: Translation.tr("Media mode"), why: Translation.tr("Needs the desktop wallpaper layer") },
        { icon: "edit", title: Translation.tr("Edit mode and the desktop menu"), why: Translation.tr("Only useful with desktop widgets") },
        { icon: "view_quilt", title: Translation.tr("Tiling assistant and screen corners"), why: Translation.tr("Drag helpers and hot corners run extra overlays") },
        { icon: "sports_esports", title: Translation.tr("Game HUD and overlays"), why: Translation.tr("Full-screen overlay windows") },
        { icon: "keyboard", title: Translation.tr("On-screen keyboard and touch gestures"), why: Translation.tr("Touch features") }
    ]

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        ContentSection {
            title: Translation.tr("Power saver")
            icon: "battery_saver"

            NoticeBox {
                Layout.fillWidth: true
                visible: !PanelFamily.isLite
                materialIcon: "info"
                text: Translation.tr("These settings apply to the Lite panel family. Switch to it to see them take effect.")
            }

            ConfigSwitch {
                buttonIcon: "battery_saver"
                text: Translation.tr("Switch to power saver on a low battery")
                checked: Config.options.lite.autoSaver.enable
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.lite.autoSaver.enable)
                        Config.options.lite.autoSaver.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Only the power profile changes. It goes back to the one you were using when the charger is in or the charge recovers, and a profile you pick yourself is left alone.")
                }
            }

            ConfigSpinBox {
                icon: "percent"
                text: Translation.tr("Turn on at (%)")
                value: Config.options.lite.autoSaver.threshold
                from: 5
                to: 80
                stepSize: 5
                onValueChanged: {
                    if (Config.ready)
                        Config.options.lite.autoSaver.threshold = value;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Bar")
            icon: "toolbar"

            ConfigSwitch {
                buttonIcon: "photo_camera"
                text: Translation.tr("Show mic, camera and screen-share use")
                checked: Config.options.lite.bar.privacy
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.lite.bar.privacy)
                        Config.options.lite.bar.privacy = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Turns on a background probe of the audio and video streams while it is enabled.")
                }
            }
            ConfigSwitch {
                buttonIcon: "keyboard"
                text: Translation.tr("Show the keyboard layout when there is more than one")
                checked: Config.options.lite.bar.keyboardLayout
                onCheckedChanged: {
                    if (Config.ready && checked !== Config.options.lite.bar.keyboardLayout)
                        Config.options.lite.bar.keyboardLayout = checked;
                }
            }
        }

        ContentSection {
            title: Translation.tr("Apps to add back")
            icon: "add_circle"

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
                font.pixelSize: Appearance.font.pixelSize.smaller
                text: Translation.tr("These are the desktop family's own apps. Each one is loaded only while its switch is on, and opens with its usual shortcut.")
            }

            Repeater {
                model: liteRoot.extras
                delegate: ConfigSwitch {
                    id: extraSwitch
                    required property var modelData
                    Layout.fillWidth: true
                    buttonIcon: modelData.icon
                    text: modelData.hint !== "" ? modelData.title + "  ·  " + modelData.hint : modelData.title
                    checked: Config.options.lite.extras[modelData.key]
                    onCheckedChanged: {
                        if (Config.ready && checked !== Config.options.lite.extras[modelData.key])
                            Config.options.lite.extras[modelData.key] = checked;
                    }
                }
            }
        }

        ContentSection {
            title: Translation.tr("Left out to stay light")
            icon: "do_not_disturb_on"

            Repeater {
                model: liteRoot.leftOut
                delegate: RowLayout {
                    id: item
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 12
                    MaterialSymbol {
                        text: item.modelData.icon
                        iconSize: 22
                        color: Appearance.colors.colSubtext
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            text: item.modelData.title
                            color: Appearance.colors.colOnLayer1
                            wrapMode: Text.Wrap
                        }
                        StyledText {
                            Layout.fillWidth: true
                            text: item.modelData.why
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            wrapMode: Text.Wrap
                        }
                    }
                }
            }

            RippleButtonWithIcon {
                Layout.topMargin: 6
                buttonRadius: Appearance.rounding.small
                materialIcon: "desktop_windows"
                mainText: Translation.tr("Switch to the desktop family")
                onClicked: PanelFamily.select("ii")
            }
        }
    }
}

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.settings.configs.colors
import qs.modules.settings.configs.power
import qs.modules.settings.configs.widgets

/**
 * Power & Battery, Material 3 Expressive: the pack as the hero (level slab + today's chart,
 * which opens the full battery history), the power mode as the main pane with the thermals
 * strip under it, the everyday features as tiles, and the fine print on sub-pages.
 */
Item {
    id: powerRoot
    anchors.fill: parent

    property alias contentY: root.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage

    function open(page) {
        powerRoot.activeSubPage = Qt.resolvedUrl(page);
    }

    // Live temperature on the thermals strip, only while the page is on screen
    Component.onCompleted: FanControl.watchers += 1
    Component.onDestruction: FanControl.watchers -= 1

    ContentPage {
        id: root
        anchors.fill: parent
        forceWidth: false
        opacity: subPageOverlay.slideProgress

        // ── hero ──
        BatteryHero {
            Layout.fillWidth: true
            visible: Battery.available
            onDetailsRequested: powerRoot.open("power/BatteryUsageConfig.qml")
        }

        // A desktop has no pack: say so in one line instead of an empty hero
        Rectangle {
            Layout.fillWidth: true
            visible: !Battery.available
            implicitHeight: 96
            radius: Appearance.rounding.verylarge
            color: Appearance.colors.colLayer1

            RowLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 16
                MaterialShapeWrappedMaterialSymbol {
                    text: "power"
                    iconSize: 24
                    padding: 12
                    shape: MaterialShape.Shape.Cookie7Sided
                    color: Appearance.colors.colSecondaryContainer
                    colSymbol: Appearance.colors.colOnSecondaryContainer
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    StyledText {
                        text: Translation.tr("Mains power")
                        font.family: Appearance.font.family.title
                        font.variableAxes: Appearance.font.variableAxes.titleRounded
                        font.pixelSize: Appearance.font.pixelSize.huge
                        color: Appearance.colors.colOnLayer1
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("No battery on this machine, so only the power mode and the thermals apply.")
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.WordWrap
                    }
                }
            }
        }

        // ── main pane ──
        PowerModePane {
            Layout.fillWidth: true
            onThermalsRequested: powerRoot.open("power/FanControlConfig.qml")
            onFrameworkRequested: powerRoot.open("power/FrameworkConfig.qml")
        }

        // ── feature tiles ──
        AppSettingsSection {
            Layout.topMargin: 12
            title: Translation.tr("Everyday")
            symbol: "bolt"

            Grid {
                id: tiles
                Layout.fillWidth: true
                readonly property int tileHeight: 200
                readonly property int count: (Battery.available ? 2 : 0) + 1 + (KeyboardBacklight.available ? 1 : 0)
                readonly property int maxCols: Math.max(1, Math.floor((width + spacing) / (300 + spacing)))
                columns: tiles.maxCols >= tiles.count ? tiles.count : (tiles.maxCols >= 2 ? 2 : 1)
                spacing: 12
                readonly property real tileWidth: (width - spacing * (columns - 1)) / columns

                ColorsFeatureTile {
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "coffee"
                    shapeOn: MaterialShape.Shape.Cookie12Sided
                    title: Translation.tr("Keep awake")
                    checked: Idle.inhibit
                    configurable: true
                    summary: !Idle.inhibit ? Translation.tr("Off. The screen dims and the system sleeps as usual.")
                        : (Idle.timed ? Translation.tr("On for %1 more").arg(Idle.remainingText)
                                      : Translation.tr("On until you turn it off"))
                    onToggled: value => Idle.toggleInhibit(value)
                    onConfigureRequested: powerRoot.open("power/KeepAwakeConfig.qml")
                }

                ColorsFeatureTile {
                    visible: Battery.available
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "mode_standby"
                    shapeOn: MaterialShape.Shape.Flower
                    title: Translation.tr("Automatic suspend")
                    checked: Config.options.battery.automaticSuspend
                    configurable: true
                    summary: Config.options.battery.automaticSuspend
                        ? Translation.tr("Sleeps at %1 %. Warns at %2 % and %3 %.").arg(Config.options.battery.suspend).arg(Config.options.battery.low).arg(Config.options.battery.critical)
                        : Translation.tr("Off. Warns at %1 % and %2 %, never suspends.").arg(Config.options.battery.low).arg(Config.options.battery.critical)
                    onToggled: value => Config.options.battery.automaticSuspend = value
                    onConfigureRequested: powerRoot.open("power/BatteryAlertsConfig.qml")
                }

                ColorsFeatureTile {
                    id: chargeTile
                    visible: Battery.available
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "battery_status_good"
                    shapeOn: MaterialShape.Shape.Clover4Leaf
                    title: Translation.tr("Charge finished")
                    checked: Config.options.battery.notifyCharged ?? true
                    summary: {
                        const end = Battery.chargeLimitActive ? Translation.tr("at the %1 % limit").arg(Battery.chargeLimit) : Translation.tr("at 100 %");
                        if (!checked)
                            return Translation.tr("Off. Charging ends quietly %1.").arg(end);
                        return GlobalStates.islandOwnsBattery
                            ? Translation.tr("On the island's battery banner, %1.").arg(end)
                            : Translation.tr("Notifies once per charge, %1.").arg(end);
                    }
                    onToggled: value => Config.options.battery.notifyCharged = value
                }

                ColorsFeatureTile {
                    id: kbdTile
                    visible: KeyboardBacklight.available
                    width: tiles.tileWidth
                    height: tiles.tileHeight
                    symbol: "keyboard"
                    shapeOn: MaterialShape.Shape.SoftBurst
                    title: Translation.tr("Keyboard light")
                    checked: Config.options.light.keyboardBacklight.autoOff
                    summary: checked
                        ? Translation.tr("Turns off after %1 without input, back on the next key.").arg(kbdTile.timeoutText(Config.options.light.keyboardBacklight.timeout))
                        : Translation.tr("Off. The backlight stays at your level.")
                    onToggled: value => Config.options.light.keyboardBacklight.autoOff = value

                    readonly property color colContent: checked ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnLayer1
                    function timeoutText(secs) {
                        return secs < 60 ? Translation.tr("%1 s").arg(secs) : Translation.tr("%1 min").arg(Math.round(secs / 60));
                    }

                    Repeater {
                        model: [15, 60, 300]
                        delegate: ColorsChip {
                            required property int modelData
                            label: kbdTile.timeoutText(modelData)
                            enabled: kbdTile.checked
                            chosen: Config.options.light.keyboardBacklight.timeout === modelData
                            colContent: kbdTile.colContent
                            colChosen: Appearance.colors.colPrimary
                            colOnChosen: Appearance.colors.colOnPrimary
                            onClicked: Config.options.light.keyboardBacklight.timeout = modelData
                        }
                    }
                }
            }
        }

        // ── the bar's power button (plain options, original components) ──
        ContentSection {
            Layout.topMargin: 12
            icon: "power_settings_new"
            title: Translation.tr("Power button in the bar")

            ContentSubsection {
                title: Translation.tr("Visual style")
                icon: "palette"
                ConfigSelectionArray {
                    currentValue: Config.options.bar.styles.power
                    onSelected: newValue => Config.options.bar.styles.power = String(newValue)
                    options: [
                        { displayName: Translation.tr("Default"),    icon: "style",                 value: "default" },
                        { displayName: Translation.tr("Expressive"), icon: "fluid_med",             value: "expressive" },
                        { displayName: Translation.tr("Solid"),      icon: "radio_button_checked",  value: "solid" },
                        { displayName: Translation.tr("Dot"),        icon: "fiber_manual_record",   value: "dot" }
                    ]
                }
            }

            ExpressiveColorModeSubsection {
                visible: Config.options.bar.styles.power === "expressive"
                currentValue: Config.options.bar.power.colorMode
                onSelected: newValue => Config.options.bar.power.colorMode = String(newValue)
            }
        }

        // ── laptop lid ──
        ContentSection {
            Layout.topMargin: 12
            visible: Battery.available
            icon: "laptop_chromebook"
            title: Translation.tr("Closing the lid")
            tooltip: Translation.tr("What happens when the lid is shut. Keep system awake turns Suspend into Turn screen off. The screen comes back when the lid opens.")

            ContentSubsection {
                title: Translation.tr("On a charger")
                icon: "power"
                ConfigSelectionArray {
                    currentValue: Config.options.lid.onAc
                    onSelected: newValue => Config.options.lid.onAc = String(newValue)
                    options: [
                        { displayName: Translation.tr("Turn screen off"), icon: "desktop_access_disabled", value: "blank" },
                        { displayName: Translation.tr("Suspend"),         icon: "bedtime",                value: "suspend" },
                        { displayName: Translation.tr("Do nothing"),      icon: "block",                  value: "nothing" }
                    ]
                }
            }
            ContentSubsection {
                title: Translation.tr("On battery")
                icon: "battery_android_5"
                ConfigSelectionArray {
                    currentValue: Config.options.lid.onBattery
                    onSelected: newValue => Config.options.lid.onBattery = String(newValue)
                    options: [
                        { displayName: Translation.tr("Suspend"),         icon: "bedtime",                value: "suspend" },
                        { displayName: Translation.tr("Turn screen off"), icon: "desktop_access_disabled", value: "blank" },
                        { displayName: Translation.tr("Do nothing"),      icon: "block",                  value: "nothing" }
                    ]
                }
            }
        }

        // ── when idle ──
        ContentSection {
            Layout.topMargin: 12
            icon: "timer"
            title: Translation.tr("When idle")
            tooltip: Translation.tr("What happens as you stop using the computer, each step counted from your last input. Keep system awake stops all of them. Changing a value rewrites the idle daemon's config and restarts it, which takes about a second. Locking before suspend is always on and is not a setting.")

            ContentSubsection {
                title: Translation.tr("Steps")
                icon: "hourglass_top"

                ConfigSwitch {
                    buttonIcon: "brightness_6"
                    text: Translation.tr("Dim the screen")
                    checked: Config.options.hypridle.dim.enable
                    onCheckedChanged: Config.options.hypridle.dim.enable = checked
                }
                ConfigSpinBox {
                    visible: Config.options.hypridle.dim.enable
                    icon: "timer"
                    text: Translation.tr("after (seconds)")
                    value: Config.options.hypridle.dim.seconds
                    from: 10
                    to: 7200
                    stepSize: 10
                    onValueChanged: Config.options.hypridle.dim.seconds = value
                }

                ConfigSwitch {
                    buttonIcon: "brightness_low"
                    text: Translation.tr("Lower the brightness")
                    checked: Config.options.hypridle.lowerBrightness.enable
                    onCheckedChanged: Config.options.hypridle.lowerBrightness.enable = checked
                }
                ConfigSpinBox {
                    visible: Config.options.hypridle.lowerBrightness.enable
                    icon: "timer"
                    text: Translation.tr("after (seconds)")
                    value: Config.options.hypridle.lowerBrightness.seconds
                    from: 10
                    to: 7200
                    stepSize: 10
                    onValueChanged: Config.options.hypridle.lowerBrightness.seconds = value
                }

                ConfigSwitch {
                    buttonIcon: "lock_clock"
                    text: Translation.tr("Turn the screen off once locked")
                    checked: Config.options.hypridle.screenOffLocked.enable
                    onCheckedChanged: Config.options.hypridle.screenOffLocked.enable = checked
                }
                ConfigSpinBox {
                    visible: Config.options.hypridle.screenOffLocked.enable
                    icon: "timer"
                    text: Translation.tr("after (seconds)")
                    value: Config.options.hypridle.screenOffLocked.seconds
                    from: 10
                    to: 7200
                    stepSize: 10
                    onValueChanged: Config.options.hypridle.screenOffLocked.seconds = value
                }

                ConfigSwitch {
                    buttonIcon: "lock"
                    text: Translation.tr("Lock the session")
                    checked: Config.options.hypridle.lock.enable
                    onCheckedChanged: Config.options.hypridle.lock.enable = checked
                }
                ConfigSpinBox {
                    visible: Config.options.hypridle.lock.enable
                    icon: "timer"
                    text: Translation.tr("after (seconds)")
                    value: Config.options.hypridle.lock.seconds
                    from: 10
                    to: 7200
                    stepSize: 10
                    onValueChanged: Config.options.hypridle.lock.seconds = value
                }

                ConfigSwitch {
                    buttonIcon: "desktop_access_disabled"
                    text: Translation.tr("Turn the screen off")
                    checked: Config.options.hypridle.screenOff.enable
                    onCheckedChanged: Config.options.hypridle.screenOff.enable = checked
                }
                ConfigSpinBox {
                    visible: Config.options.hypridle.screenOff.enable
                    icon: "timer"
                    text: Translation.tr("after (seconds)")
                    value: Config.options.hypridle.screenOff.seconds
                    from: 10
                    to: 7200
                    stepSize: 10
                    onValueChanged: Config.options.hypridle.screenOff.seconds = value
                }

                ConfigSwitch {
                    buttonIcon: "bedtime"
                    text: Translation.tr("Suspend")
                    checked: Config.options.hypridle.suspend.enable
                    onCheckedChanged: Config.options.hypridle.suspend.enable = checked
                }
                ConfigSpinBox {
                    visible: Config.options.hypridle.suspend.enable
                    icon: "timer"
                    text: Translation.tr("after (seconds)")
                    value: Config.options.hypridle.suspend.seconds
                    from: 10
                    to: 7200
                    stepSize: 10
                    onValueChanged: Config.options.hypridle.suspend.seconds = value
                }
                ConfigSwitch {
                    visible: Config.options.hypridle.suspend.enable
                    buttonIcon: "battery_android_5"
                    text: Translation.tr("Only on battery")
                    checked: Config.options.hypridle.suspend.onlyOnBattery
                    onCheckedChanged: Config.options.hypridle.suspend.onlyOnBattery = checked
                }
            }
        }

        // ── related ──
        Flow {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            RelatedChip {
                pageId: "bar"
                label: Translation.tr("Battery bar widget")
                sectionHighlight: Translation.tr("Widgets")
            }
            RelatedChip {
                pageId: "usageStats"
                label: Translation.tr("App usage history")
            }
        }
    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }
}

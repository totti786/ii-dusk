pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * The Phone tab's own settings page, opened from the gear in the header.
 *
 * The home of every phone option except the KDE Connect service switch, which
 * stays in Settings → Devices & Phone (and Core Policies) so the service can
 * be turned back on while this tab is empty. What the tab shows, the sidebar
 * mirror, notifications, contacts, the scrcpy connection and options, and
 * App Mode all live here only.
 *
 * Drawn in the Clock settings vocabulary (docs/design/material3-expressive.md)
 * rather than with the Settings app's cards, which nest card-in-card and
 * stretch their sliders across the narrow sidebar: titled sections of rows
 * that share one surface, a switch or stepper on the right, dashed chips for
 * choices.
 */
Item {
    id: root
    signal goBack()

    readonly property var scrcpy: Config.options.phone.scrcpy
    readonly property var appMode: Config.options.phone.scrcpy.appMode

    /** Paired devices first, then the ones asking, then whatever else is nearby. */
    readonly property var sortedDevices: {
        const rank = d => d.paired ? 0 : (d.pairState === 2 || d.pairState === 1) ? 1 : 2;
        return Array.from(KdeConnectService.devices ?? [])
            .sort((a, b) => rank(a) - rank(b) || String(a.name).localeCompare(String(b.name)));
    }

    /// Daemon plugin ids, in words. Anything not listed is shown by its id.
    readonly property var pluginLabels: ({
        "kdeconnect_battery": Translation.tr("Battery"),
        "kdeconnect_clipboard": Translation.tr("Clipboard sync"),
        "kdeconnect_connectivity_report": Translation.tr("Signal strength"),
        "kdeconnect_contacts": Translation.tr("Contacts"),
        "kdeconnect_findmyphone": Translation.tr("Find my phone"),
        "kdeconnect_lockdevice": Translation.tr("Lock device"),
        "kdeconnect_mousepad": Translation.tr("Remote input"),
        "kdeconnect_mpriscontrol": Translation.tr("Media control"),
        "kdeconnect_mprisremote": Translation.tr("Control phone media"),
        "kdeconnect_notifications": Translation.tr("Notifications"),
        "kdeconnect_pausemusic": Translation.tr("Pause media on calls"),
        "kdeconnect_ping": Translation.tr("Ping"),
        "kdeconnect_remotecommands": Translation.tr("Remote commands"),
        "kdeconnect_remotecontrol": Translation.tr("Remote control"),
        "kdeconnect_remotekeyboard": Translation.tr("Remote keyboard"),
        "kdeconnect_remotesystemvolume": Translation.tr("Phone volume"),
        "kdeconnect_runcommand": Translation.tr("Run commands"),
        "kdeconnect_screensaver_inhibit": Translation.tr("Screensaver inhibit"),
        "kdeconnect_sftp": Translation.tr("File browsing"),
        "kdeconnect_share": Translation.tr("Share files"),
        "kdeconnect_systemvolume": Translation.tr("Audio devices")
    })

    // ─── Header ─────────────────────────────────────────────
    RowLayout {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 12

        RippleButton {
            implicitWidth: 40
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
            colRipple: Appearance.colors.colSecondaryContainerActive
            onClicked: root.goBack()

            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: "arrow_back"
                iconSize: Appearance.font.pixelSize.large
                color: Appearance.colors.colOnSecondaryContainer
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Phone settings")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: KdeConnectService.activeDevice
                    ? KdeConnectService.activeDeviceDisplayName
                    : Translation.tr("KDE Connect and scrcpy")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }
        }
    }

    // ─── Body ───────────────────────────────────────────────
    StyledFlickable {
        id: flick
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: 12
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        clip: true
        contentHeight: body.implicitHeight + 16
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: body
            width: flick.width
            spacing: 18

            // ── Devices ──
            Section {
                title: Translation.tr("Devices")
                symbol: "devices"

                Repeater {
                    model: root.sortedDevices
                    delegate: DeviceRow {
                        required property var modelData
                        device: modelData
                    }
                }

                SettingRow {
                    visible: root.sortedDevices.length === 0
                    symbol: "phonelink_off"
                    title: Translation.tr("No devices found")
                    description: Translation.tr("Open KDE Connect on the phone, on the same network, then search again.")
                }
                SettingRow {
                    symbol: "refresh"
                    title: Translation.tr("Search for devices")
                    description: Translation.tr("Looks for phones on the network again.")
                    clickable: true
                    onClicked: KdeConnectService.rescanNetwork()
                }
            }

            // ── Run commands ──
            Section {
                id: commandsSection
                readonly property string deviceId: KdeConnectService.activeDeviceId
                property string editingKey: ""
                property bool editing: false

                title: Translation.tr("Commands on the phone")
                symbol: "terminal"
                visible: deviceId.length > 0

                onDeviceIdChanged: if (deviceId.length > 0) KdeConnectService.loadRunCommands(deviceId)
                Component.onCompleted: if (deviceId.length > 0) KdeConnectService.loadRunCommands(deviceId)

                Repeater {
                    model: KdeConnectService.runCommandsDeviceId === commandsSection.deviceId
                        ? KdeConnectService.runCommandList : []
                    delegate: SettingRow {
                        id: commandRow
                        required property var modelData
                        symbol: "play_circle"
                        title: modelData.name
                        description: modelData.command

                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: {
                                commandsSection.editingKey = commandRow.modelData.key;
                                nameField.text = commandRow.modelData.name;
                                commandField.text = commandRow.modelData.command;
                                commandsSection.editing = true;
                            }
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "edit"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip { text: Translation.tr("Edit") }
                        }
                        RippleButton {
                            implicitWidth: 34
                            implicitHeight: 34
                            buttonRadius: Appearance.rounding.full
                            colBackground: "transparent"
                            colBackgroundHover: Appearance.colors.colLayer3Hover
                            colRipple: Appearance.colors.colLayer3Active
                            onClicked: KdeConnectService.deleteRunCommand(commandsSection.deviceId, commandRow.modelData.key)
                            contentItem: MaterialSymbol {
                                anchors.centerIn: parent
                                horizontalAlignment: Text.AlignHCenter
                                text: "delete"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                            StyledToolTip { text: Translation.tr("Delete") }
                        }
                    }
                }

                SettingRow {
                    visible: !commandsSection.editing
                        && (KdeConnectService.runCommandsDeviceId !== commandsSection.deviceId
                            || KdeConnectService.runCommandList.length === 0)
                    symbol: "info"
                    title: Translation.tr("No commands of your own yet")
                    description: Translation.tr("They appear on the phone under KDE Connect → Run command, and run on this computer.")
                }

                // The form: one row, so it keeps the group's shape.
                SettingRow {
                    visible: commandsSection.editing
                    symbol: "edit_note"
                    title: commandsSection.editingKey.length > 0 ? Translation.tr("Edit command") : Translation.tr("New command")
                    below: ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        MaterialTextField {
                            id: nameField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Name shown on the phone")
                        }
                        MaterialTextField {
                            id: commandField
                            Layout.fillWidth: true
                            placeholderText: Translation.tr("Command, e.g. loginctl lock-session")
                            onAccepted: saveButton.clicked()
                        }
                        RowLayout {
                            Layout.alignment: Qt.AlignRight
                            spacing: 6
                            PillButton {
                                tonal: false
                                label: Translation.tr("Cancel")
                                onClicked: commandsSection.editing = false
                            }
                            PillButton {
                                id: saveButton
                                label: Translation.tr("Save")
                                enabled: nameField.text.trim().length > 0 && commandField.text.trim().length > 0
                                onClicked: {
                                    if (!saveButton.enabled) return;
                                    KdeConnectService.saveRunCommand(commandsSection.deviceId,
                                        commandsSection.editingKey, nameField.text, commandField.text);
                                    commandsSection.editing = false;
                                }
                            }
                        }
                    }
                }
                SettingRow {
                    visible: !commandsSection.editing
                    symbol: "add"
                    title: Translation.tr("Add a command")
                    clickable: true
                    onClicked: {
                        commandsSection.editingKey = "";
                        nameField.text = "";
                        commandField.text = "";
                        commandsSection.editing = true;
                    }
                }
            }

            // ── Phone tab ──
            Section {
                title: Translation.tr("Phone tab")
                symbol: "smartphone"

                ToggleRow {
                    symbol: "view_in_ar"
                    title: Translation.tr("Show Mirror / Webcam / Microphone cards")
                    checked: Config.options.phone.showPeripheralCards
                    onToggled: value => Config.options.phone.showPeripheralCards = value
                }
                ToggleRow {
                    symbol: "smart_display"
                    title: Translation.tr("Mirror the phone inside the sidebar")
                    help: Translation.tr("On, the mirror opens as a page in the Phone tab with the phone's screen drawn inside it, touch and keyboard included. Off, it opens as a separate scrcpy window like it always did.")
                    checked: Config.options.phone.scrcpy.embed.enabled
                    onToggled: value => Config.options.phone.scrcpy.embed.enabled = value
                }
                ToggleRow {
                    symbol: "notifications"
                    title: Translation.tr("Show phone notifications with desktop ones")
                    help: Translation.tr("On, phone notifications pop up and stay in the sidebar list like any other, and also show in the Phone tab. Off, they only show in the Phone tab while your phone is connected.")
                    enabled: Config.options.phone.kdeconnectEnabled
                    checked: Config.options.phone.mirrorNotificationsToDesktop
                    onToggled: value => Config.options.phone.mirrorNotificationsToDesktop = value
                }
            }

            // ── Contacts ──
            Section {
                title: Translation.tr("Contacts")
                symbol: "contacts"

                ToggleRow {
                    symbol: "contacts"
                    title: Translation.tr("Sync contacts from phone")
                    checked: Config.options.phone.contacts.enabled
                    onToggled: value => Config.options.phone.contacts.enabled = value
                }
                ToggleRow {
                    symbol: "filter_alt"
                    title: Translation.tr("Hide contacts without a name")
                    help: Translation.tr("Your phone exports every number known to any app, including spam lists and SIM imports. These arrive with no name and show up as bare numbers. Favorites are never hidden.")
                    enabled: Config.options.phone.contacts.enabled
                    checked: Config.options.phone.contacts.hideUnnamed
                    onToggled: value => Config.options.phone.contacts.hideUnnamed = value
                }
            }

            // ── Connection ──
            Section {
                title: Translation.tr("Connection")
                symbol: "sync"

                ToggleRow {
                    symbol: "wifi"
                    title: Translation.tr("Use wireless debugging")
                    checked: root.scrcpy.useWireless
                    onToggled: value => root.scrcpy.useWireless = value
                }
                ToggleRow {
                    symbol: "sync_alt"
                    title: Translation.tr("Auto-detect IP (KDE Connect)")
                    description: !root.scrcpy.useWireless ? ""
                        : root.scrcpy.autoWirelessIp
                            ? (KdeConnectService.resolvedWirelessHost !== ""
                                ? Translation.tr("Will connect to %1").arg(KdeConnectService.resolvedWirelessHost)
                                : Translation.tr("Waiting for KDE Connect to report the phone's IP…"))
                            : ""
                    enabled: root.scrcpy.useWireless
                    checked: root.scrcpy.autoWirelessIp
                    onToggled: value => root.scrcpy.autoWirelessIp = value
                }
                FieldRow {
                    symbol: "dns"
                    title: Translation.tr("Wireless IP")
                    placeholder: Translation.tr("e.g. 192.168.1.50")
                    visible: root.scrcpy.useWireless && !root.scrcpy.autoWirelessIp
                    value: root.scrcpy.wirelessIp
                    onEdited: text => root.scrcpy.wirelessIp = text
                }
                FieldRow {
                    symbol: "tag"
                    title: Translation.tr("Wireless Port")
                    placeholder: Translation.tr("Default: 5555")
                    visible: root.scrcpy.useWireless && !root.scrcpy.autoWirelessIp
                    value: root.scrcpy.wirelessPort
                    onEdited: text => root.scrcpy.wirelessPort = text
                }
                ToggleRow {
                    symbol: "push_pin"
                    title: Translation.tr("Pin ADB to port 5555")
                    description: root.scrcpy.useWireless && KdeConnectService.pinnedAdbHost !== ""
                        ? Translation.tr("Pinned to %1").arg(KdeConnectService.pinnedAdbHost) : ""
                    help: Translation.tr("Wireless debugging picks a new random port every time the phone's ADB daemon restarts — an unlock is enough — which cuts the connection. Pinning holds a fixed port that survives those restarts, until the phone reboots. Unlike wireless debugging, that port stays open on every network the phone joins; connecting still requires a computer the phone has authorised.")
                    enabled: root.scrcpy.useWireless
                    checked: root.scrcpy.pinAdbPort
                    onToggled: value => root.scrcpy.pinAdbPort = value
                }
                ToggleRow {
                    symbol: "restart_alt"
                    title: Translation.tr("Reopen windows after a drop")
                    help: Translation.tr("Reopens the same mirror or app window here once the phone answers again. Only affects windows on this machine, not what the phone is doing.")
                    checked: root.scrcpy.autoResume
                    onToggled: value => root.scrcpy.autoResume = value
                }
                ToggleRow {
                    symbol: "terminal"
                    title: Translation.tr("Show terminal window")
                    checked: root.scrcpy.showTerminal
                    onToggled: value => root.scrcpy.showTerminal = value
                }
            }

            // ── scrcpy ──
            Section {
                title: Translation.tr("scrcpy Options")
                symbol: "phone_android"

                ToggleRow {
                    symbol: "lock"
                    title: Translation.tr("Stay awake")
                    checked: root.scrcpy.stayAwake
                    onToggled: value => root.scrcpy.stayAwake = value
                }
                ToggleRow {
                    symbol: "phone_android"
                    title: Translation.tr("Turn screen off")
                    checked: root.scrcpy.turnScreenOff
                    onToggled: value => root.scrcpy.turnScreenOff = value
                }
                ToggleRow {
                    symbol: "power_settings_new"
                    title: Translation.tr("No power on device")
                    checked: root.scrcpy.noPowerOn
                    onToggled: value => root.scrcpy.noPowerOn = value
                }
                ToggleRow {
                    symbol: "volume_off"
                    title: Translation.tr("No audio forwarding")
                    checked: root.scrcpy.noAudio
                    onToggled: value => root.scrcpy.noAudio = value
                }
                ToggleRow {
                    symbol: "gesture"
                    title: Translation.tr("Show touches")
                    checked: root.scrcpy.showTouches
                    onToggled: value => root.scrcpy.showTouches = value
                }
                ToggleRow {
                    symbol: "fullscreen"
                    title: Translation.tr("Fullscreen")
                    checked: root.scrcpy.fullscreen
                    onToggled: value => root.scrcpy.fullscreen = value
                }
                ToggleRow {
                    symbol: "vertical_align_top"
                    title: Translation.tr("Always on top")
                    checked: root.scrcpy.alwaysOnTop
                    onToggled: value => root.scrcpy.alwaysOnTop = value
                }
                StepperRow {
                    symbol: "speed"
                    title: Translation.tr("Max FPS")
                    value: root.scrcpy.maxFps
                    from: 0; to: 120; stepSize: 5
                    format: v => v === 0 ? Translation.tr("Native") : String(v)
                    onMoved: v => root.scrcpy.maxFps = v
                }
                FieldRow {
                    symbol: "wifi_tethering"
                    title: Translation.tr("Bitrate")
                    placeholder: Translation.tr("e.g. 8M, 4M")
                    value: root.scrcpy.bitRate
                    onEdited: text => root.scrcpy.bitRate = text
                }
                StepperRow {
                    symbol: "aspect_ratio"
                    title: Translation.tr("Max Size (0 for unrestricted)")
                    value: root.scrcpy.maxSize
                    from: 0; to: 3840; stepSize: 120
                    format: v => v === 0 ? Translation.tr("Any") : String(v)
                    onMoved: v => root.scrcpy.maxSize = v
                }
                StepperRow {
                    symbol: "av_timer"
                    title: Translation.tr("Video Buffer (ms)")
                    value: root.scrcpy.videoBuffer
                    from: 0; to: 1000; stepSize: 10
                    onMoved: v => root.scrcpy.videoBuffer = v
                }
            }

            // ── Input, clipboard & recording ──
            Section {
                title: Translation.tr("Input, clipboard & recording")
                symbol: "keyboard"

                ToggleRow {
                    symbol: "keyboard"
                    title: Translation.tr("Hardware keyboard (UHID)")
                    help: Translation.tr("The phone sees a real keyboard: accents, dead keys and shortcuts work. Set the phone's physical keyboard layout (Settings → General management → Physical keyboard) to match this PC's. Turn off if typing does nothing on your phone.")
                    checked: (root.scrcpy.keyboardMode ?? "uhid") === "uhid"
                    onToggled: value => root.scrcpy.keyboardMode = value ? "uhid" : "sdk"
                }
                ToggleRow {
                    symbol: "content_paste"
                    title: Translation.tr("Sync the clipboard while mirroring")
                    checked: root.scrcpy.clipboardSync ?? true
                    onToggled: value => root.scrcpy.clipboardSync = value
                }
                ToggleRow {
                    symbol: "mic"
                    title: Translation.tr("Record phone audio too")
                    checked: root.scrcpy.recording.withAudio
                    onToggled: value => root.scrcpy.recording.withAudio = value
                }
                FieldRow {
                    symbol: "folder"
                    title: Translation.tr("Recordings folder")
                    placeholder: FileUtils.trimFileProtocol(Directories.videos)
                    value: root.scrcpy.recording.folder
                    onEdited: text => root.scrcpy.recording.folder = text
                }
                ToggleRow {
                    symbol: "terminal"
                    title: Translation.tr("Offer shell actions to the phone")
                    help: Translation.tr("Lists mirror, record, media, mute, lock and suspend under KDE Connect → Run command on the phone. Your own commands there are kept.")
                    checked: Config.options.phone.remoteCommands ?? true
                    onToggled: value => Config.options.phone.remoteCommands = value
                }
            }

            // ── Android App Mode ──
            Section {
                title: Translation.tr("Android App Mode (scrcpy 4.0+)")
                symbol: "apps"

                ToggleRow {
                    symbol: "apps"
                    title: Translation.tr("Enable Android App Mode")
                    help: Translation.tr("Allows launching individual Android apps directly from the II Phone panel.")
                    checked: root.appMode.enabled
                    onToggled: value => root.appMode.enabled = value
                }
                ToggleRow {
                    symbol: "wallpaper"
                    title: Translation.tr("Show real app icons")
                    help: Translation.tr("Reads each app's launcher icon off the phone when you refresh the app list, then caches it. Apps without a cached icon keep a generic Android glyph.")
                    enabled: root.appMode.enabled
                    checked: root.appMode.showAppIcons
                    onToggled: value => root.appMode.showAppIcons = value
                    extraSymbol: "delete_sweep"
                    extraTooltip: Translation.tr("Forgets every extracted icon, including the apps that failed, so the next app-list refresh reads them all again.")
                    extraEnabled: root.appMode.enabled && root.appMode.showAppIcons
                    onExtraClicked: PhoneAppIconService.clearCache()
                }
                ChoiceRow {
                    symbol: "interests"
                    title: Translation.tr("Icon shape")
                    help: Translation.tr("How the phone's launcher would cut each icon: Pixel, One UI and iOS use those launchers' measured shapes; the rest are the stock Android mask options most other brands pick from. Only affects extracted icons; the generic Android glyph keeps its own shape.")
                    visible: root.appMode.showAppIcons
                    currentValue: root.appMode.iconShape
                    onSelected: value => root.appMode.iconShape = value
                    options: [
                        { label: Translation.tr("Pixel"), icon: "circle", value: "circle" },
                        { label: Translation.tr("Samsung One UI"), icon: "rounded_corner", value: "oneui" },
                        { label: Translation.tr("iOS"), icon: "ios", value: "ios" },
                        { label: Translation.tr("Squircle"), icon: "crop_square", value: "squircle" },
                        { label: Translation.tr("Rounded square"), icon: "square", value: "roundedSquare" },
                        { label: Translation.tr("Square"), icon: "check_box_outline_blank", value: "square" },
                        { label: Translation.tr("Sharp square"), icon: "crop_din", value: "sharpSquare" },
                        { label: Translation.tr("Teardrop"), icon: "water_drop", value: "teardrop" },
                        { label: Translation.tr("Cylinder"), icon: "panorama_horizontal", value: "cylinder" }
                    ]
                }
                ToggleRow {
                    symbol: "desktop_windows"
                    title: Translation.tr("Use Virtual Secondary Display (--flex-display)")
                    help: Translation.tr("Launches apps in secondary virtual display. On Samsung Galaxy devices, this opens Samsung DeX. Disable to launch directly on main phone screen.")
                    checked: root.appMode.flexDisplay
                    onToggled: value => root.appMode.flexDisplay = value
                }
                ToggleRow {
                    symbol: "lock_open_right"
                    title: Translation.tr("Unlock the phone automatically")
                    help: Translation.tr("Dismisses the lockscreen before launching, without lighting the phone's screen when \"Turn screen off\" is on. Only gets through when the phone already trusts this situation — otherwise a small mirror opens so it can be unlocked from here.")
                    checked: root.appMode.autoUnlock
                    onToggled: value => root.appMode.autoUnlock = value
                    extraSymbol: "open_in_new"
                    extraTooltip: Translation.tr("Android gives a desktop no way to make itself trusted — the phone has to be told once. Opens Extended unlock on the phone, where this machine can be added as a trusted device. After that the lockscreen is a plain swipe, which the shell does for you.")
                    extraEnabled: KdeConnectService.adbReachable
                    onExtraClicked: KdeConnectService.openExtendedUnlockSettings()
                }
                ChoiceRow {
                    symbol: "exit_to_app"
                    title: Translation.tr("When a session ends")
                    help: Translation.tr("What the phone is left doing after you close the window. \"Keep the app\" moves it back to the phone's own screen instead of dropping it with the virtual display. Nothing runs when the window closed because the connection dropped.")
                    currentValue: root.appMode.onSessionEnd
                    onSelected: value => root.appMode.onSessionEnd = value
                    options: [
                        { label: Translation.tr("Home screen"), icon: "home", value: "home" },
                        { label: Translation.tr("Keep the app"), icon: "phonelink", value: "continue" },
                        { label: Translation.tr("Lock"), icon: "lock", value: "lock" }
                    ]
                }
                ToggleRow {
                    symbol: "keep"
                    title: Translation.tr("Keep virtual display active")
                    help: Translation.tr("Prevents virtual display from being destroyed when app window closes.")
                    enabled: root.appMode.flexDisplay
                    checked: root.appMode.keepActive
                    onToggled: value => root.appMode.keepActive = value
                }
                ToggleRow {
                    symbol: "web_asset"
                    title: Translation.tr("Show Android system decorations")
                    help: Translation.tr("Shows status bar and navigation controls inside the virtual display.")
                    enabled: root.appMode.flexDisplay
                    checked: root.appMode.systemDecorations
                    onToggled: value => root.appMode.systemDecorations = value
                }
                StepperRow {
                    symbol: "desktop_mac"
                    title: Translation.tr("Virtual Display Width")
                    enabled: root.appMode.flexDisplay
                    value: root.appMode.displayWidth
                    from: 640; to: 2560; stepSize: 80
                    onMoved: v => root.appMode.displayWidth = v
                }
                StepperRow {
                    symbol: "desktop_mac"
                    title: Translation.tr("Virtual Display Height")
                    enabled: root.appMode.flexDisplay
                    value: root.appMode.displayHeight
                    from: 480; to: 1920; stepSize: 60
                    onMoved: v => root.appMode.displayHeight = v
                }
                StepperRow {
                    symbol: "display_settings"
                    title: Translation.tr("Virtual Display Density (DPI)")
                    enabled: root.appMode.flexDisplay
                    value: root.appMode.density
                    from: 120; to: 480; stepSize: 20
                    onMoved: v => root.appMode.density = v
                }
            }
        }
    }

    // ─── Components ─────────────────────────────────────────
    /** A titled group; its rows share one surface split by 2 px gaps. */
    component Section: ColumnLayout {
        id: section
        property string title: ""
        property string symbol: ""
        default property alias rows: rowColumn.data

        Layout.fillWidth: true
        spacing: 8

        RowLayout {
            Layout.leftMargin: 8
            spacing: 8
            MaterialSymbol {
                text: section.symbol
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }
            StyledText {
                text: section.title
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colPrimary
            }
        }

        ColumnLayout {
            id: rowColumn
            Layout.fillWidth: true
            spacing: 2
        }
    }

    /**
     * One setting row. The outer corners of the first and last *visible* row
     * in a section are large and the joins small, so hiding a row keeps the
     * group's shape.
     */
    component SettingRow: Rectangle {
        id: row
        property string symbol: ""
        property string title: ""
        property string description: ""
        property string help: ""
        property bool clickable: false
        default property alias control: controlHolder.data
        property alias below: belowHolder.data
        signal clicked()

        readonly property var _siblings: parent ? parent.visibleChildren : []
        readonly property bool first: _siblings.length > 0 && _siblings[0] === row
        readonly property bool last: _siblings.length > 0 && _siblings[_siblings.length - 1] === row
        readonly property real _outer: Appearance.rounding.large
        readonly property real _inner: Appearance.rounding.verysmall

        Layout.fillWidth: true
        implicitHeight: Math.max(56, content.implicitHeight + 20)
        topLeftRadius: row.first ? row._outer : row._inner
        topRightRadius: row.first ? row._outer : row._inner
        bottomLeftRadius: row.last ? row._outer : row._inner
        bottomRightRadius: row.last ? row._outer : row._inner
        color: row.clickable && row.enabled && rowHover.hovered ? Appearance.colors.colLayer3Hover : Appearance.colors.colLayer3
        opacity: row.enabled ? 1 : 0.45

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        HoverHandler {
            id: rowHover
        }
        TapHandler {
            enabled: row.clickable
            cursorShape: Qt.PointingHandCursor
            onTapped: row.clicked()
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 14
            anchors.rightMargin: 12
            // No gap under the title while the content below it is hidden (a closed drawer).
            spacing: belowHolder.implicitHeight > 0 ? 8 : 0

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                MaterialSymbol {
                    visible: row.symbol.length > 0
                    text: row.symbol
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    StyledText {
                        Layout.fillWidth: true
                        text: row.title
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.colors.colOnLayer3
                    }
                    StyledText {
                        Layout.fillWidth: true
                        visible: row.description.length > 0
                        text: row.description
                        wrapMode: Text.WordWrap
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                Item {
                    visible: row.help.length > 0
                    implicitWidth: 22
                    implicitHeight: 22
                    Layout.alignment: Qt.AlignVCenter
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "info"
                        iconSize: Appearance.font.pixelSize.normal
                        color: infoHover.hovered ? Appearance.colors.colOnLayer3 : Appearance.colors.colSubtext
                    }
                    HoverHandler {
                        id: infoHover
                    }
                    StyledToolTip {
                        text: row.help
                        extraVisibleCondition: infoHover.hovered
                    }
                }

                RowLayout {
                    id: controlHolder
                    Layout.alignment: Qt.AlignVCenter
                    spacing: 4
                }
            }

            ColumnLayout {
                id: belowHolder
                Layout.fillWidth: true
                visible: children.length > 0
                spacing: 0
            }
        }
    }

    /** A small text button for the right side of a row. */
    component PillButton: RippleButton {
        id: pill
        property string label: ""
        property bool tonal: true
        implicitHeight: 32
        implicitWidth: pillText.implicitWidth + 24
        buttonRadius: Appearance.rounding.full
        colBackground: pill.tonal ? Appearance.colors.colSecondaryContainer : "transparent"
        colBackgroundHover: pill.tonal ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colLayer3Hover
        colRipple: pill.tonal ? Appearance.colors.colSecondaryContainerActive : Appearance.colors.colLayer3Active
        contentItem: StyledText {
            id: pillText
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: pill.label
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.DemiBold
            color: pill.tonal ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
        }
    }

    /**
     * One device: its state in words, the action that fits that state, and for a paired
     * one a drawer of per-plugin switches.
     */
    component DeviceRow: SettingRow {
        id: deviceRow
        property var device: ({})
        property bool expanded: false
        property bool confirmingUnpair: false

        readonly property bool paired: device.paired === true
        readonly property int pairState: Number(device.pairState ?? 0)
        readonly property string deviceType: String(device.type ?? "phone")

        symbol: deviceRow.deviceType === "tablet" ? "tablet"
            : deviceRow.deviceType === "desktop" ? "desktop_windows"
            : deviceRow.deviceType === "laptop" ? "laptop"
            : deviceRow.deviceType === "tv" ? "tv" : "smartphone"
        title: device.name && device.name.length > 0 ? device.name : String(device.id ?? "")
        description: {
            const parts = [];
            if (deviceRow.paired)
                parts.push(device.reachable ? Translation.tr("Paired · connected") : Translation.tr("Paired · offline"));
            else if (deviceRow.pairState === 2)
                parts.push(Translation.tr("Wants to pair"));
            else if (deviceRow.pairState === 1)
                parts.push(Translation.tr("Waiting for the phone to accept"));
            else
                parts.push(device.reachable ? Translation.tr("Nearby · not paired") : Translation.tr("Not paired"));
            if (deviceRow.paired && Number(device.charge ?? -1) >= 0)
                parts.push(`${device.charge}%${device.charging ? " ⚡" : ""}`);
            return parts.join(" · ");
        }

        Timer {
            id: confirmReset
            interval: 4000
            onTriggered: deviceRow.confirmingUnpair = false
        }

        // Someone else is asking: answer it.
        PillButton {
            visible: deviceRow.pairState === 2
            label: Translation.tr("Accept")
            onClicked: KdeConnectService.acceptPairing(deviceRow.device.id)
        }
        PillButton {
            visible: deviceRow.pairState === 2
            tonal: false
            label: Translation.tr("Decline")
            onClicked: KdeConnectService.declinePairing(deviceRow.device.id)
        }
        // We asked: let it be withdrawn.
        PillButton {
            visible: deviceRow.pairState === 1
            tonal: false
            label: Translation.tr("Cancel")
            onClicked: KdeConnectService.declinePairing(deviceRow.device.id)
        }
        PillButton {
            visible: !deviceRow.paired && deviceRow.pairState === 0
            enabled: deviceRow.device.reachable === true
            label: Translation.tr("Pair")
            onClicked: KdeConnectService.requestPairing(deviceRow.device.id)
        }
        // Forgetting a device is the one thing here that cannot be undone from this side:
        // the first press asks, the second does it.
        PillButton {
            visible: deviceRow.paired
            tonal: deviceRow.confirmingUnpair
            label: deviceRow.confirmingUnpair ? Translation.tr("Confirm") : Translation.tr("Unpair")
            onClicked: {
                if (!deviceRow.confirmingUnpair) {
                    deviceRow.confirmingUnpair = true;
                    confirmReset.restart();
                    return;
                }
                confirmReset.stop();
                deviceRow.confirmingUnpair = false;
                KdeConnectService.unpairDevice(deviceRow.device.id);
            }
        }
        RippleButton {
            visible: deviceRow.paired && (deviceRow.device.supportedPlugins ?? []).length > 0
            implicitWidth: 34
            implicitHeight: 34
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: deviceRow.expanded = !deviceRow.expanded
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: deviceRow.expanded ? "expand_less" : "expand_more"
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledToolTip {
                text: Translation.tr("Plugins")
            }
        }

        below: Flow {
            Layout.fillWidth: true
            visible: deviceRow.expanded && deviceRow.paired
            spacing: 6
            Repeater {
                model: [...(deviceRow.device.supportedPlugins ?? [])].sort((a, b) =>
                    String(root.pluginLabels[a] ?? a).localeCompare(String(root.pluginLabels[b] ?? b)))
                delegate: Rectangle {
                    id: pluginChip
                    required property string modelData
                    readonly property bool on: (deviceRow.device.enabledPlugins ?? []).includes(modelData)
                    implicitWidth: pluginRow.implicitWidth + 22
                    implicitHeight: 32
                    radius: Appearance.rounding.full
                    color: pluginChip.on ? Appearance.colors.colSecondaryContainer
                        : pluginHover.hovered ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08) : "transparent"
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    DashedBorder {
                        anchors.fill: parent
                        visible: !pluginChip.on
                        color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
                        borderWidth: 1
                        dashLength: 4
                        gapLength: 3
                        radius: Appearance.rounding.full
                    }

                    RowLayout {
                        id: pluginRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            text: pluginChip.on ? "check" : "close"
                            iconSize: Appearance.font.pixelSize.normal
                            color: pluginChip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: root.pluginLabels[pluginChip.modelData] ?? pluginChip.modelData
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: pluginChip.on ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    HoverHandler {
                        id: pluginHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: KdeConnectService.setPluginEnabled(deviceRow.device.id, pluginChip.modelData, !pluginChip.on)
                    }
                }
            }
        }
    }

    /** Boolean row: the whole row toggles, the switch mirrors it. */
    component ToggleRow: SettingRow {
        id: toggleRow
        property bool checked: false
        property string extraSymbol: ""
        property string extraTooltip: ""
        property bool extraEnabled: true
        signal toggled(bool value)
        signal extraClicked()

        clickable: true
        onClicked: toggleRow.toggled(!toggleRow.checked)

        RippleButton {
            visible: toggleRow.extraSymbol.length > 0
            implicitWidth: 34
            implicitHeight: 34
            enabled: toggleRow.extraEnabled
            opacity: enabled ? 1 : 0.4
            buttonRadius: Appearance.rounding.full
            colBackground: "transparent"
            colBackgroundHover: Appearance.colors.colLayer3Hover
            colRipple: Appearance.colors.colLayer3Active
            onClicked: toggleRow.extraClicked()
            contentItem: MaterialSymbol {
                anchors.centerIn: parent
                horizontalAlignment: Text.AlignHCenter
                text: toggleRow.extraSymbol
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnSurfaceVariant
            }
            StyledToolTip {
                text: toggleRow.extraTooltip
            }
        }
        StyledSwitch {
            checked: toggleRow.checked
            onToggled: toggleRow.toggled(checked)
        }
    }

    /** Number row: − value + with wheel support (the ClockStepper). */
    component StepperRow: SettingRow {
        id: stepRow
        property int value: 0
        property int from: 0
        property int to: 100
        property int stepSize: 1
        property var format: v => String(v)
        signal moved(int value)

        function step(delta: int): void {
            const next = Math.max(stepRow.from, Math.min(stepRow.to, stepRow.value + delta * stepRow.stepSize));
            if (next !== stepRow.value)
                stepRow.moved(next);
        }

        StepButton {
            symbol: "remove"
            enabled: stepRow.value > stepRow.from
            onClicked: stepRow.step(-1)
        }
        StyledText {
            Layout.minimumWidth: 48
            horizontalAlignment: Text.AlignHCenter
            text: stepRow.format(stepRow.value)
            font.pixelSize: Appearance.font.pixelSize.small
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer3
            WheelHandler {
                onWheel: event => stepRow.step(event.angleDelta.y > 0 ? 1 : -1)
            }
        }
        StepButton {
            symbol: "add"
            enabled: stepRow.value < stepRow.to
            onClicked: stepRow.step(1)
        }
    }

    component StepButton: RippleButton {
        id: stepButton
        property string symbol: ""
        implicitWidth: 30
        implicitHeight: 30
        opacity: enabled ? 1 : 0.4
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSecondaryContainer
        colBackgroundHover: Appearance.colors.colSecondaryContainerHover
        colRipple: Appearance.colors.colSecondaryContainerActive
        contentItem: MaterialSymbol {
            anchors.centerIn: parent
            horizontalAlignment: Text.AlignHCenter
            text: stepButton.symbol
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colOnSecondaryContainer
        }
    }

    /** Text row: the field sits under the title, full width. */
    component FieldRow: SettingRow {
        id: fieldRow
        property string value: ""
        property string placeholder: ""
        signal edited(string text)

        below: MaterialTextField {
            Layout.fillWidth: true
            placeholderText: fieldRow.placeholder
            text: fieldRow.value
            onTextChanged: if (text !== fieldRow.value) fieldRow.edited(text)
        }
    }

    /** Choice row: dashed chips, the chosen one filled (ClockFormChip). */
    component ChoiceRow: SettingRow {
        id: choiceRow
        property var options: []
        property var currentValue: null
        signal selected(var value)

        below: Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: choiceRow.options
                delegate: Rectangle {
                    id: chip
                    required property var modelData
                    readonly property bool chosen: choiceRow.currentValue === modelData.value
                    implicitWidth: chipRow.implicitWidth + 22
                    implicitHeight: 32
                    radius: Appearance.rounding.full
                    color: chip.chosen ? Appearance.colors.colSecondaryContainer
                        : chipHover.hovered ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.08) : "transparent"
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }

                    DashedBorder {
                        anchors.fill: parent
                        visible: !chip.chosen
                        color: ColorUtils.applyAlpha(Appearance.colors.colOutline, 0.8)
                        borderWidth: 1
                        dashLength: 4
                        gapLength: 3
                        radius: Appearance.rounding.full
                    }

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: 4
                        MaterialSymbol {
                            visible: (chip.modelData.icon ?? "").length > 0
                            text: chip.modelData.icon ?? ""
                            iconSize: Appearance.font.pixelSize.normal
                            fill: chip.chosen ? 1 : 0
                            color: chip.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                        StyledText {
                            text: chip.modelData.label
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: chip.chosen ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnSurfaceVariant
                        }
                    }

                    HoverHandler {
                        id: chipHover
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        onTapped: choiceRow.selected(chip.modelData.value)
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.settings.configs.dictation

/**
 * Dictation — speech typed into whatever window has focus.
 *
 * The page is honest about the two things that can be missing: voxtype itself,
 * which nothing here installs, and the speech model, which is a download this
 * page can actually perform. Everything else only becomes reachable once those
 * two are in place, so the switch never promises something that cannot happen.
 */
ContentPage {
    id: page
    forceWidth: false

    readonly property bool installed: DictationService.installed
    readonly property bool ready: DictationService.available

    function refreshHex(): void {
        if (DictationService.useHex)
            HexSettings.refresh();
    }

    Component.onCompleted: {
        page.refreshHex();
        if (!DictationService.useHex)
            VoxtypeSettings.refresh();
    }

    // The binary is looked up after login, and Hex's catalogue can only be read
    // while it runs: ask again when either changes with the page open.
    Connections {
        target: DictationService
        function onHexBinChanged() { page.refreshHex(); }
        function onUseHexChanged() {
            if (!DictationService.useHex)
                VoxtypeSettings.refresh();
        }
        function onHexStateChanged() {
            if (DictationService.hexState === "idle")
                page.refreshHex();
        }
    }

    function linuxFamilyFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "Arch Linux";
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "Fedora / RHEL";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "Debian / Ubuntu";
        return SystemInfo.distroName && SystemInfo.distroName !== "Unknown" ? SystemInfo.distroName : "Linux";
    }

    /**
     * Voxtype publishes an AUR package and prebuilt .deb/.rpm archives, so the
     * honest instruction differs per distro rather than being one command with
     * a swapped package manager.
     */
    function installCommandFor(value: string): string {
        const distro = String(value || "").toLowerCase();
        if (["arch", "artix", "manjaro", "endeavouros", "cachyos"].indexOf(distro) >= 0)
            return "yay -S voxtype-bin";
        if (["fedora", "rhel", "centos", "rocky", "almalinux"].indexOf(distro) >= 0)
            return "# Grab the latest .rpm from https://voxtype.io/download/\n" +
                "sudo dnf install ./voxtype-*.rpm";
        if (["debian", "ubuntu", "linuxmint", "pop", "popos", "zorin", "elementary", "kali", "raspbian"].indexOf(distro) >= 0)
            return "# Grab the latest .deb from https://voxtype.io/download/\n" +
                "sudo apt install ./voxtype_*.deb";
        return "# Download a build for your distro from https://voxtype.io/download/";
    }

    readonly property string linuxFamily: page.linuxFamilyFor(SystemInfo.distroId)
    readonly property string installCommand: page.installCommandFor(SystemInfo.distroId)

    KeyboardShortcutBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        text: Translation.tr("Hold to dictate, release to type")
        keys: ["Alt", "Space"]
    }
    KeyboardShortcutBox {
        Layout.fillWidth: true
        Layout.bottomMargin: 8
        text: Translation.tr("Press once to start, again to stop")
        keys: ["Ctrl", "Alt", "Space"]
    }

    // ── Setup ────────────────────────────────────────────────────────────────
    ContentSection {
        visible: !page.installed && !DictationService.useHex
        icon: "download"
        title: Translation.tr("Install Voxtype")

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Dictation runs on Voxtype, a local speech-to-text daemon. Speech is transcribed on this machine and typed into the window you are already working in — nothing is sent anywhere. Install it, then press Check again.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
        }

        HelperCodeBox {
            Layout.fillWidth: true
            Layout.topMargin: 4
            topLeftRadius: Appearance.rounding.large
            topRightRadius: Appearance.rounding.large
            bottomLeftRadius: Appearance.rounding.large
            bottomRightRadius: Appearance.rounding.large
            icon: "terminal"
            title: Translation.tr("Install voxtype · %1").arg(page.linuxFamily)
            text: Translation.tr("Run this in a terminal, then press Check again below.")
            codeSnippet: page.installCommand
            snippetWrapMode: Text.Wrap
        }

        RippleButtonWithIcon {
            Layout.topMargin: 4
            materialIcon: "refresh"
            mainText: Translation.tr("Check again")
            onClicked: DictationService.redetect()
        }
    }

    // ── Main switch and status ───────────────────────────────────────────────
    ContentSection {
        icon: "mic"
        title: Translation.tr("Dictation")

        ConfigSwitch {
            buttonIcon: "keyboard_voice"
            text: Translation.tr("Type what I say into the focused window")
            checked: Config.options.dictation.enabled
            enabled: page.installed || DictationService.hexInstalled
            onCheckedChanged: {
                Config.options.dictation.enabled = checked;
            }
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: Appearance.colors.colSubtext
            text: Translation.tr("Hold Alt + Space to dictate. Press Ctrl + Alt + Space to start or stop hands-free dictation.")
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 8

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: page.ready ? "check_circle" : "info"
                iconSize: Appearance.font.pixelSize.large
                color: page.ready ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: DictationService.engaged ? DictationService.statusLabel : page.ready
                        ? (DictationService.useHex ? Translation.tr("Ready — Hex.")
                            : Translation.tr("Ready — %1.").arg(DictationService.modelLabel))
                        : Translation.tr("Not ready yet")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: !page.ready
                    text: DictationService.unavailableReason()
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: page.installed && !DictationService.bridgeInstalled && !DictationService.useHex
                    text: Translation.tr("The voxtype-audio-bridge helper is missing, so the notch shows a pulse instead of your voice's waveform. Dictation itself is unaffected.")
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: DictationService.lastError.length > 0
                    text: DictationService.lastError
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colError
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 4
            text: DictationService.useHex
                ? Translation.tr("The shell starts Hex when you first press the dictation shortcut.")
                : Translation.tr("The daemon runs for as long as the shell does, and stops when this switch is off.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // ── Which program listens ────────────────────────────────────────────────
    ContentSection {
        icon: "hearing"
        title: Translation.tr("Engine")

        ConfigSelectionArray {
            currentValue: DictationService.activeEngine
            onSelected: newValue => {
                Config.options.dictation.engine = newValue;
            }
            options: [
                {
                    displayName: Translation.tr("Hex"),
                    icon: "bolt",
                    value: "hex"
                },
                {
                    displayName: Translation.tr("Voxtype"),
                    icon: "graphic_eq",
                    value: "voxtype"
                }
            ]
        }

        StyledText {
            Layout.fillWidth: true
            text: DictationService.useHex
                ? Translation.tr("Hex transcribes on this machine and pastes the text itself. Its model, microphone and text settings are below.")
                : DictationService.engine === "hex"
                    ? Translation.tr("Hex was not found, so Voxtype is being used.")
                    : Translation.tr("Voxtype runs OpenAI's Whisper locally. It knows many languages and can translate to English, but it waits until you stop before transcribing, which takes longer on this machine.")
            wrapMode: Text.Wrap
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }

    // ── Hex's own settings ───────────────────────────────────────────────────
    HexSections {
        Layout.fillWidth: true
        visible: DictationService.useHex
    }

    HexMoreSection {
        visible: DictationService.useHex
    }

    // ── Voxtype's own settings ───────────────────────────────────────────────
    VoxtypeSections {
        Layout.fillWidth: true
        visible: page.installed && !DictationService.useHex
    }

    VoxtypeMoreSection {
        visible: page.installed && !DictationService.useHex && VoxtypeSettings.loaded
    }

    // ── Both engines ─────────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed || DictationService.useHex
        icon: "settings_voice"
        title: Translation.tr("While dictating")

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Stop listening after (seconds)")
            value: Config.options.dictation.maxDurationSecs
            from: 10
            to: 600
            stepSize: 10
            onValueChanged: {
                Config.options.dictation.maxDurationSecs = value;
            }
        }
    }

    // ── Where it shows ───────────────────────────────────────────────────────
    ContentSection {
        visible: page.installed || DictationService.useHex
        icon: "visibility"
        title: Translation.tr("Showing it")

        ConfigSwitch {
            visible: DictationService.useHex
            buttonIcon: "dock_to_bottom"
            text: Translation.tr("Show Hex's icon in the system tray")
            checked: !TrayService.isHidden("hex")
            onCheckedChanged: TrayService.setHidden("hex", !checked)
        }

        ConfigSwitch {
            visible: !DictationService.useHex
            buttonIcon: "dock_to_bottom"
            text: Translation.tr("Show Voxtype's icon in the system tray")
            checked: Config.options.dictation.voxtypeTrayIcon
            onCheckedChanged: Config.options.dictation.voxtypeTrayIcon = checked
        }

        ConfigSwitch {
            buttonIcon: "space_bar"
            text: Translation.tr("Microphone in the bar while dictating")
            checked: Config.options.dictation.showIndicator
            onCheckedChanged: {
                Config.options.dictation.showIndicator = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "mic"
            text: Translation.tr("Keep it there while idle, as a button")
            checked: Config.options.dictation.alwaysShowIndicator
            enabled: Config.options.dictation.showIndicator
            onCheckedChanged: {
                Config.options.dictation.alwaysShowIndicator = checked;
            }
            StyledToolTip {
                text: Translation.tr("Click the microphone to start dictating, and again to finish — the same thing the keybind does.")
            }
        }

        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr("Waveform in the dynamic island")
            checked: Config.options.dictation.showInIsland
            onCheckedChanged: {
                Config.options.dictation.showInIsland = checked;
            }
        }
    }
}

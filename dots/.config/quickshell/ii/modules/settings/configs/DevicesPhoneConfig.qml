import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Item {
    id: root
    anchors.fill: parent

    property alias contentY: page.contentY
    property alias activeSubPage: subPageOverlay.activeSubPage
    property int loadStage: 0

    Component.onCompleted: Qt.callLater(() => root.loadStage = 1)

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false
        // Fade the parent content while a sub-page slides in so its switches
        // cannot remain visible behind the loaded page.
        opacity: subPageOverlay.slideProgress
        visible: opacity > 0

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            isLast: true
            materialIcon: "mobile_share"
            text: Translation.tr("Ways to share files with your phone:\n\n• KDE Connect: Drag files into the Phone tab in Sidebar Policies, drop files onto the Dynamic Island, use the 'Send file' toggle inside Phone in Sidebar Policies, or use More Actions in Search (Ctrl+K).\n\n• LocalSend: Use More Actions in Search (Ctrl+K), drop files onto the Dynamic Island, use the LocalSend Quick Toggle, or drag files onto the Clock widget in the bar.\n\n• Quick Share: Android phones nearby, no pairing. Drop files onto the Dynamic Island or the Send tile, or use the Quick Share tile to let a phone send to this computer.")
        }

    ContentSection {
        icon: "smartphone"
        title: Translation.tr("Phone")
        visible: Config.options.policies.phone !== 0

        ConfigSwitch {
            buttonIcon: "sync"
            text: Translation.tr("Enable KDE Connect Service")
            checked: Config.options.phone.kdeconnectEnabled
            onCheckedChanged: {
                Config.options.phone.kdeconnectEnabled = checked;
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            materialIcon: "settings"
            text: Translation.tr("Everything else about the phone — cards, the sidebar mirror, notifications, contacts, scrcpy and App Mode — lives in the Phone tab of Sidebar Policies, behind the gear in its header.")
        }
    }

    ProgressiveSectionLoader {
        source: Qt.resolvedUrl("sections/PhoneBluetoothImagesSection.qml")
        active: root.loadStage >= 1
        estimatedHeight: 620
        showSkeleton: true
        sectionTitle: Translation.tr("Bluetooth Device Images")
        prioritizeOnViewport: true
        prioritizeOnSearch: true
    }

    ContentSection {
        icon: "share"
        title: Translation.tr("LocalSend")

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            materialIcon: LocalSend.available ? "verified" : "download"
            text: LocalSend.available
                ? Translation.tr("Backend: official localsend-cli %1 (Rust, from github.com/localsend/localsend). Sending and receiving are driven through a pseudo-terminal bridge (services/localsend_bridge.py) that only reads the CLI's screen and writes keystrokes — it never touches file bytes itself, so file integrity always comes straight from the official implementation.").arg(LocalSend.cliVersion || "?")
                : Translation.tr("The official localsend-cli was not found. It replaced a now-deprecated, unaffiliated third-party Python package that corrupted received files once LocalSend moved to protocol v2.2. The official binary is a prebuilt download from localsend/localsend's GitHub releases — no Rust toolchain needed on x86_64/aarch64 Linux or macOS.")

            RippleButtonWithIcon {
                visible: !LocalSend.available && !LocalSend.installing
                materialIcon: "download"
                mainText: Translation.tr("Install")
                colBackground: Appearance.colors.colTertiary
                colText: Appearance.colors.colOnTertiary
                onClicked: LocalSend.installOfficialCli()
            }

            RowLayout {
                visible: LocalSend.installing
                spacing: 8
                MaterialLoadingIndicator {
                    loading: true
                    implicitSize: 20
                }
                StyledText {
                    text: Translation.tr("Installing\u2026")
                    color: Appearance.colors.colOnTertiaryContainer
                }
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            visible: LocalSend.installError !== ""
            materialIcon: "error"
            text: LocalSend.installError
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: LocalSend.installLog !== ""
            icon: "terminal"
            title: Translation.tr("Install log")
            codeSnippet: LocalSend.installLog.trim()
            snippetWrapMode: Text.Wrap
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: !LocalSend.available
            icon: "terminal"
            title: Translation.tr("Or install manually")
            text: Translation.tr("Downloads the prebuilt binary matching your architecture from GitHub releases; prints cargo build instructions instead if none is published yet for it.")
            codeSnippet: "bash ~/.config/quickshell/ii/scripts/localsend/install_localsend_cli.sh"
            snippetWrapMode: Text.WrapAnywhere
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: LocalSend.available && LocalSend.pyteChecked && !LocalSend.pyteAvailable
            icon: "warning"
            title: Translation.tr("Missing Python package: pyte")
            text: Translation.tr("Only needed to send files: it reads the CLI's on-screen device list to pick a target. Receiving already works without it.")
            codeSnippet: "pip install --user pyte"
            snippetWrapMode: Text.WrapAnywhere
        }

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Auto-start")
            checked: Config.options.localsend.autoStart
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.autoStart = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "notifications"
            text: Translation.tr("Show notifications")
            checked: Config.options.localsend.showNotifications
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.showNotifications = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "branding_watermark"
            text: Translation.tr("Prefer popup over notification")
            checked: Config.options.localsend.preferPopupOverNotification
            enabled: LocalSend.available
            onCheckedChanged: {
                Config.options.localsend.preferPopupOverNotification = checked;
            }
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download path")
            text: Config.options.localsend.downloadPath
            wrapMode: TextEdit.Wrap
            enabled: LocalSend.available
            onTextChanged: {
                Config.options.localsend.downloadPath = text;
            }
        }
    }

    ContentSection {
        icon: "send_to_mobile"
        title: Translation.tr("Quick Share")

        ConfigSwitch {
            buttonIcon: "power_settings_new"
            text: Translation.tr("Enable Quick Share")
            checked: Config.options.quickShare.enable
            onCheckedChanged: {
                if (Config.options.quickShare.enable !== checked)
                    Config.options.quickShare.enable = checked;
            }
        }

        // The daemon is compiled here, once, the first time Quick Share is turned on.
        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            visible: QuickShareService.enabled && (QuickShareService.building || !QuickShareService.binaryExists)
            materialIcon: QuickShareService.helperBuild.buildResult === "failed" ? "error"
                : !QuickShareService.helperBuild.cargoAvailable ? "download" : "construction"
            text: QuickShareService.building
                    ? Translation.tr("Building the Quick Share service from source (first time, about two minutes)… %1").arg(QuickShareService.helperBuild.progressText)
                : QuickShareService.helperBuild.buildResult === "failed"
                    ? Translation.tr("The build failed, so Quick Share is not running.")
                : !QuickShareService.helperBuild.cargoAvailable
                    ? Translation.tr("Quick Share's background service is compiled from source here, and the Rust toolchain is not installed.")
                : Translation.tr("The Quick Share service has not been built yet.")

            RippleButtonWithIcon {
                visible: !QuickShareService.building && QuickShareService.helperBuild.cargoAvailable
                materialIcon: QuickShareService.helperBuild.buildResult === "failed" ? "refresh" : "build"
                mainText: QuickShareService.helperBuild.buildResult === "failed" ? Translation.tr("Retry") : Translation.tr("Build now")
                colBackground: Appearance.colors.colTertiary
                colText: Appearance.colors.colOnTertiary
                onClicked: QuickShareService.helperBuild.build()
            }
            MaterialLoadingIndicator {
                visible: QuickShareService.building
                loading: QuickShareService.building
                implicitSize: 20
            }
        }

        StyledProgressBar {
            Layout.fillWidth: true
            visible: QuickShareService.building
            value: QuickShareService.helperBuild.progress
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: QuickShareService.helperBuild.buildResult === "failed"
            icon: "error"
            title: Translation.tr("Build output")
            codeSnippet: QuickShareService.helperBuild.buildOutput.split("\n").slice(-12).join("\n")
            snippetWrapMode: Text.WrapAnywhere
        }

        HelperCodeBox {
            Layout.fillWidth: true
            visible: QuickShareService.enabled && !QuickShareService.binaryExists && !QuickShareService.helperBuild.cargoAvailable
            icon: "terminal"
            title: Translation.tr("Install Rust, then build")
            codeSnippet: "yay -S --needed rust\n" + Directories.rustHelpersScriptPath + " build ii-quickshare"
            snippetWrapMode: Text.WrapAnywhere
        }

        // Built from older source (after an update): keeps running, just without the newest fixes.
        NoticeBox {
            Layout.fillWidth: true
            visible: QuickShareService.binaryExists && QuickShareService.helperBuild.outdated && !QuickShareService.building
            materialIcon: "update"
            text: QuickShareService.helperBuild.state === "stale"
                ? Translation.tr("The running service was built from older source than the one installed now.")
                : Translation.tr("This service has no build record, so it may be behind its source.")

            RippleButtonWithIcon {
                visible: QuickShareService.helperBuild.cargoAvailable
                materialIcon: "refresh"
                mainText: Translation.tr("Rebuild")
                colBackground: Appearance.colors.colTertiary
                colText: Appearance.colors.colOnTertiary
                onClicked: QuickShareService.helperBuild.build()
            }
        }

        NoticeBox {
            Layout.fillWidth: true
            isFirst: true
            isLast: true
            materialIcon: !QuickShareService.enabled ? "block"
                : QuickShareService.errorText !== "" ? "error"
                : QuickShareService.linked ? "check_circle" : "sync_problem"
            text: !QuickShareService.enabled ? Translation.tr("Off. This computer is invisible and the Quick Share background service is not running.")
                : QuickShareService.errorText !== "" ? Translation.tr("Error: %1").arg(QuickShareService.errorText)
                : !QuickShareService.linked ? Translation.tr("Starting the Quick Share service…")
                : QuickShareService.visibility === "invisible" ? Translation.tr("Running. Hidden: Android phones can't send here until you make this computer visible (Quick Share tile, or the island).")
                : QuickShareService.visibility === "visible" ? Translation.tr("Running. Visible to everyone nearby.")
                : Translation.tr("Running. Visible for 10 minutes.")
        }

        MaterialTextArea {
            Layout.fillWidth: true
            placeholderText: Translation.tr("Download folder (empty: ~/Downloads)")
            text: Config.options.quickShare.downloadDir
            wrapMode: TextEdit.Wrap
            enabled: Config.options.quickShare.enable
            onTextChanged: {
                if (Config.options.quickShare.downloadDir !== text)
                    Config.options.quickShare.downloadDir = text;
            }
        }
    }

    }

    ConfigSubPageHost {
        id: subPageOverlay
        anchors.fill: parent
        z: 10
    }

}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Face ID settings: configure Face ID unlock behavior, view enrolled faces,
 * install Gaze, and test face recognition powered by Gaze.
 */
Item {
    id: subPageRoot
    anchors.fill: parent

    property bool showBackButton: false
    signal goBack

    readonly property var faceIdOptions: Config.options.lock.security.faceId

    function launchInTerminal(cmd: string): void {
        const terminal = (Config.options.apps && Config.options.apps.terminal) || "kitty -1";
        Quickshell.execDetached(["bash", "-c", `${terminal} -e bash -c "${cmd}; echo; echo 'Press Enter to exit...'; read" &`]);
    }

    Component.onCompleted: FaceId.refresh()

    ContentPage {
        id: page
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: subPageRoot.showBackButton
            spacing: 12

            RippleButton {
                implicitWidth: implicitHeight
                implicitHeight: 40
                topLeftRadius: Appearance.rounding.full
                topRightRadius: Appearance.rounding.full
                bottomLeftRadius: Appearance.rounding.full
                bottomRightRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: subPageRoot.goBack()

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }

            StyledText {
                text: Translation.tr("Face ID")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        // ── Camera & Daemon status ──────────────────────────────────────────
        ContentSection {
            icon: "videocam"
            title: Translation.tr("Camera & Service")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: statusLayout.implicitHeight + 28
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: statusLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    spacing: 14

                    MaterialSymbol {
                        text: FaceId.available ? "face" : "videocam_off"
                        iconSize: 34
                        fill: 1
                        color: FaceId.available ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: FaceId.available
                                ? Translation.tr("Face ID ready (Gaze)")
                                : !FaceId.probed
                                    ? Translation.tr("Checking Gaze service…")
                                    : !FaceId.gazeInstalled
                                        ? Translation.tr("Gaze not installed")
                                        : !FaceId.daemonRunning
                                            ? Translation.tr("Gaze daemon not running")
                                            : !FaceId.cameraAvailable
                                                ? Translation.tr("No camera detected")
                                                : Translation.tr("No face profiles enrolled")
                            font.pixelSize: Appearance.font.pixelSize.small
                            font.weight: Font.DemiBold
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledText {
                            Layout.fillWidth: true
                            wrapMode: Text.WordWrap
                            text: FaceId.available
                                ? Translation.tr("Camera active · %1 face profiles enrolled in Gaze").arg(FaceId.enrolledCount)
                                : !FaceId.gazeInstalled
                                    ? Translation.tr("Gaze is required for Face ID. See the setup guide below to install it.")
                                    : !FaceId.daemonRunning
                                        ? Translation.tr("Ensure gazed.service is running: sudo systemctl enable --now gazed.service")
                                        : !FaceId.cameraAvailable
                                            ? Translation.tr("Make sure your webcam is plugged in and supported by V4L2/GStreamer.")
                                            : Translation.tr("Enroll a face profile using the setup guide below to enable Face ID.")
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            color: Appearance.colors.colSubtext
                        }
                    }

                    RippleButton {
                        implicitWidth: 36
                        implicitHeight: 36
                        buttonRadius: Appearance.rounding.full
                        enabled: !FaceId.verifying
                        onClicked: FaceId.refresh()

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "refresh"
                            iconSize: 20
                            color: Appearance.colors.colOnLayer2
                        }

                        StyledToolTip {
                            text: Translation.tr("Re-check camera and enrolled face profiles")
                        }
                    }
                }
            }
        }

        // ── Installation & Setup Guide ──────────────────────────────────────
        ContentSection {
            icon: "download"
            title: Translation.tr("Installation & Setup")
            collapsible: true
            expanded: !FaceId.available

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Face ID uses Gaze, an open-source face recognition PAM service for Linux. Gaze operates locally on your machine with no external network requests.")
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
                icon: "download"
                title: Translation.tr("1. Install Gaze (AUR)")
                text: Translation.tr("Install the Gaze package from the AUR using your package manager:")
                codeSnippet: "yay -S gaze-bin"
                snippetWrapMode: Text.Wrap
                actionText: Translation.tr("Install in terminal")
                actionIcon: "terminal"
                onActionClicked: subPageRoot.launchInTerminal("yay -S gaze-bin || paru -S gaze-bin")
            }

            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "play_arrow"
                title: Translation.tr("2. Enable & start Gaze service")
                text: Translation.tr("Start the background daemon so Gaze is available for authentication and D-Bus requests:")
                codeSnippet: "sudo systemctl enable --now gazed.service"
                snippetWrapMode: Text.Wrap
                actionText: Translation.tr("Enable service")
                actionIcon: "terminal"
                onActionClicked: subPageRoot.launchInTerminal("sudo systemctl enable --now gazed.service")
            }

            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "face"
                title: Translation.tr("3. Enroll your face")
                text: Translation.tr("Run the face enrollment wizard in a terminal. Look into your camera while Gaze captures multi-angle facial templates:")
                codeSnippet: "gaze add-face $(whoami)"
                snippetWrapMode: Text.Wrap
                actionText: Translation.tr("Enroll in terminal")
                actionIcon: "face"
                onActionClicked: subPageRoot.launchInTerminal("gaze add-face $(whoami)")
            }

            HelperCodeBox {
                Layout.fillWidth: true
                Layout.topMargin: 4
                topLeftRadius: Appearance.rounding.large
                topRightRadius: Appearance.rounding.large
                bottomLeftRadius: Appearance.rounding.large
                bottomRightRadius: Appearance.rounding.large
                icon: "check_circle"
                title: Translation.tr("4. Verify recognition")
                text: Translation.tr("Test authentication directly in the terminal to verify the model recognizes you:")
                codeSnippet: "gaze auth"
                snippetWrapMode: Text.Wrap
                actionText: Translation.tr("Test in terminal")
                actionIcon: "terminal"
                onActionClicked: subPageRoot.launchInTerminal("gaze auth")
            }

            RippleButtonWithIcon {
                Layout.topMargin: 4
                materialIcon: "refresh"
                mainText: Translation.tr("Check status again")
                onClicked: FaceId.refresh()
            }
        }

        // ── Unlock behavior ────────────────────────────────────────────────
        ContentSection {
            icon: "lock_open"
            title: Translation.tr("Unlock")

            ConfigSwitch {
                buttonIcon: "face"
                text: Translation.tr("Unlock with Face ID")
                checked: subPageRoot.faceIdOptions.enable
                enabled: FaceId.probed && FaceId.supported
                onCheckedChanged: {
                    if (FaceId.supported)
                        subPageRoot.faceIdOptions.enable = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Enable Face ID authentication on the lock screen.")
                }
            }

            ConfigSwitch {
                buttonIcon: "visibility"
                text: Translation.tr("Show Face ID indicator on lock screen")
                checked: subPageRoot.faceIdOptions.showIndicator
                enabled: subPageRoot.faceIdOptions.enable
                onCheckedChanged: {
                    subPageRoot.faceIdOptions.showIndicator = checked;
                }
                StyledToolTip {
                    text: Translation.tr("Show the Face ID icon next to the password field on the lock screen.")
                }
            }

            NoticeBox {
                Layout.fillWidth: true
                materialIcon: "keyboard_return"
                text: Translation.tr("Face ID is triggered on the lock screen when you press Enter/Return with an empty password field, or when clicking the face badge.")
            }
        }

        // ── Enrolled face profiles ──────────────────────────────────────────
        ContentSection {
            icon: "groups"
            title: Translation.tr("Enrolled profiles")

            NoticeBox {
                Layout.fillWidth: true
                visible: FaceId.probed && !FaceId.hasEnrolled
                materialIcon: "info"
                text: Translation.tr("No face enrolled yet. Run 'gaze add-face $(whoami)' in a terminal to enroll your face.")
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: FaceId.hasEnrolled

                Repeater {
                    model: FaceId.enrolled

                    delegate: Rectangle {
                        required property string modelData
                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: Appearance.rounding.small
                        color: Appearance.colors.colLayer2

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 16
                            spacing: 12

                            MaterialSymbol {
                                text: "face"
                                iconSize: 22
                                color: Appearance.colors.colPrimary
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.Medium
                                color: Appearance.colors.colOnLayer2
                            }

                            MaterialSymbol {
                                text: "check_circle"
                                iconSize: 18
                                color: Appearance.colors.colPrimary
                            }
                        }
                    }
                }

                RippleButtonWithIcon {
                    Layout.topMargin: 4
                    materialIcon: "add"
                    mainText: Translation.tr("Enroll another face profile")
                    onClicked: subPageRoot.launchInTerminal("gaze add-face $(whoami)")
                }
            }
        }

        // ── Test Face ID ───────────────────────────────────────────────────
        ContentSection {
            icon: "check_circle"
            title: Translation.tr("Test recognition")

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: testLayout.implicitHeight + 24
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                RowLayout {
                    id: testLayout
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 16

                    RippleButton {
                        implicitHeight: 40
                        implicitWidth: testButtonRow.implicitWidth + 28
                        buttonRadius: Appearance.rounding.full
                        enabled: FaceId.available && !FaceId.verifying
                        colBackground: Appearance.colors.colPrimary
                        colBackgroundHover: Appearance.colors.colPrimaryHover
                        colRipple: Appearance.colors.colPrimaryActive
                        onClicked: FaceId.startAuth()

                        contentItem: RowLayout {
                            id: testButtonRow
                            anchors.centerIn: parent
                            spacing: 8

                            MaterialSymbol {
                                text: FaceId.verifying ? "sync" : "face"
                                iconSize: 20
                                color: Appearance.colors.colOnPrimary
                            }

                            StyledText {
                                text: FaceId.verifying ? Translation.tr("Scanning…") : Translation.tr("Test Face ID")
                                font.pixelSize: Appearance.font.pixelSize.small
                                font.weight: Font.DemiBold
                                color: Appearance.colors.colOnPrimary
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: FaceId.verifying
                            ? Translation.tr("Looking at camera…")
                            : FaceId.lastResult === "success"
                                ? Translation.tr("✓ Face recognized successfully!")
                                : FaceId.lastResult === "failure"
                                    ? Translation.tr("✗ Face not recognized")
                                    : FaceId.lastResult === "timeout"
                                        ? Translation.tr("✗ Verification timed out")
                                        : Translation.tr("Click to test your camera and face recognition.")
                        color: FaceId.lastResult === "success"
                            ? Appearance.colors.colPrimary
                            : FaceId.lastResult !== ""
                                ? Appearance.colors.colError
                                : Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.small
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}

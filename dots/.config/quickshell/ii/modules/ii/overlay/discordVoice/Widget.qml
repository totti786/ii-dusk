pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

Rectangle {
    id: root
    readonly property int avatarLimit: Config.options.overlay.discordVoice.maxAvatars
    readonly property real participantAvatarSize: Config.options.overlay.discordVoice.avatarSize
    readonly property string participantBackground: Config.options.overlay.discordVoice.participantBackground
    readonly property real participantBackgroundOpacity: Config.options.overlay.discordVoice.participantBackgroundOpacity
    readonly property bool blurEnabled: Config.options.overlay.discordVoice.blurEnabled
    readonly property bool autoResize: Config.options.overlay.discordVoice.autoResize
    readonly property real backgroundOpacity: 0.85
    readonly property string layoutMode: Config.options.overlay.discordVoice.layoutMode
    readonly property bool columnMode: layoutMode === "column"
    readonly property bool gridMode: layoutMode === "grid"
    property bool namesOnLeft: false
    readonly property bool companionReady: DiscordVoiceActivity.backend === "vencord"
    // Detected by the service, which also decides whether the bridge runs at all.
    readonly property bool isVencordClient: DiscordVoiceActivity.isVencordClient
    readonly property bool showPttIndicator: Config.options.overlay.discordVoice.pttIndicator

    // Per-user volume: tapping someone opens their card. It lives only while the
    // overlay is open (a pinned overlay over a game takes no clicks anyway) and
    // closes by itself when that person leaves.
    property string selectedUserId: ""
    readonly property var selectedParticipant: selectedUserId === "" ? null
        : (DiscordVoiceActivity.participants.find(user => String(user?.id ?? "") === selectedUserId) ?? null)
    readonly property bool canAdjustUsers: GlobalStates.overlayOpen && DiscordVoiceActivity.supportsUserVoice
    readonly property bool sliderActive: volumeCard.sliderPressed
    onSelectedParticipantChanged: if (selectedParticipant === null) selectedUserId = ""
    onCanAdjustUsersChanged: if (!canAdjustUsers) selectedUserId = ""

    readonly property real maxContentWidth: 720
    readonly property int visibleParticipants: Math.min(avatarLimit, DiscordVoiceActivity.participantCount)

    readonly property real effectiveAvatarSize: gridMode
        ? (visibleParticipants <= 1 ? Math.max(72, root.participantAvatarSize * 1.5)
            : (visibleParticipants <= 4 ? Math.max(56, root.participantAvatarSize * 1.2)
            : root.participantAvatarSize))
        : root.participantAvatarSize

    readonly property real participantCellWidth: columnMode
        ? Math.max(176, effectiveAvatarSize + 116 + 8)
        : Math.max(effectiveAvatarSize,
            (gridMode ? 96 : 76) + (participantBackground === "name" ? 16 : 0))
    readonly property real participantStride: participantCellWidth
        + (columnMode ? 6 : (gridMode ? 12 : 16))
    readonly property int participantColumns: {
        if (columnMode) return 1;
        if (gridMode) {
            if (visibleParticipants <= 1) return 1;
            if (visibleParticipants <= 2) return 2;
            if (visibleParticipants <= 4) return 2;
            if (visibleParticipants <= 6) return 3;
            if (visibleParticipants <= 9) return 3;
            return 4;
        }
        return Math.max(1, Math.min(visibleParticipants,
            Math.floor((maxContentWidth + 16) / participantStride)))
    }
    readonly property real participantGridWidth: participantColumns > 0
        ? participantColumns * participantStride
            - (columnMode ? 6 : (gridMode ? 12 : 16))
        : 0

    implicitWidth: Math.max(
        root.autoResize ? content.implicitWidth + 12 * 2 : (columnMode ? 256 : 344),
        participantGridWidth + 12 * 2)
    implicitHeight: content.implicitHeight + 24
    width: implicitWidth
    height: implicitHeight
    radius: Appearance.rounding.verylarge
    color: root.blurEnabled
        ? ColorUtils.transparentize(Appearance.colors.colLayer1, 1 - root.backgroundOpacity)
        : "transparent"
    border.width: 0

    function beginAuthorization() {
        DiscordVoiceActivity.authorizeAfterFocusRelease();
        GlobalStates.overlayOpen = false;
    }

    property string installMessage: ""

    Process {
        id: installProcess
        command: ["bash", `${Directories.scriptPath}/discordVoice/vencord-companion/install.sh`]
        stdout: SplitParser { onRead: data => console.log("[DiscordVoice Companion Install]", data) }
        stderr: SplitParser { onRead: data => {
            console.warn("[DiscordVoice Companion Install Error]", data);
            root.installMessage = data.trim();
        }}
        onStarted: {
            root.installMessage = "";
        }
        onExited: (code, status) => {
            if (code === 0) {
                root.installMessage = "Installed! Restart your Discord client.";
                DiscordVoiceActivity.recheck();
            } else if (!root.installMessage) {
                root.installMessage = "Failed (exit code " + code + ")";
            }
        }
    }

    ColumnLayout {
        id: content
        anchors {
            top: parent.top
            left: parent.left
            right: parent.right
            margins: 12
        }
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            DiscordGlyph {
                implicitSize: 36
                iconSize: 20
                color: Appearance.colors.colPrimaryContainer
                iconColor: Appearance.colors.colOnPrimaryContainer
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2
                StyledText {
                    id: channelName
                    Layout.fillWidth: true
                    text: DiscordVoiceActivity.channel?.name || (DiscordVoiceActivity.status === "auth_required"
                        ? "Connect Discord" : "No voice channel")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    text: DiscordVoiceActivity.inVoice
                        ? `${DiscordVoiceActivity.participantCount} participant${DiscordVoiceActivity.participantCount === 1 ? "" : "s"}`
                        : (DiscordVoiceActivity.errorMessage || "Discord voice overlay")
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    elide: Text.ElideRight
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                }
            }

            RowLayout {
                visible: DiscordVoiceActivity.inVoice
                spacing: 0

                RippleButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordVoiceActivity.setMuted(!DiscordVoiceActivity.muted)
                    contentItem: MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        text: DiscordVoiceActivity.muted ? "mic_off" : "mic"
                        shape: DiscordVoiceActivity.muted ? MaterialShape.Shape.SoftBurst : MaterialShape.Shape.Cookie4Sided
                        implicitSize: 46
                        iconSize: 21
                        fill: DiscordVoiceActivity.muted ? 1 : 0
                        color: DiscordVoiceActivity.muted ? Appearance.colors.colErrorContainer : Appearance.colors.colSecondaryContainer
                        colSymbol: DiscordVoiceActivity.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnSecondaryContainer
                        scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
                        Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack } }
                    }
                    StyledToolTip { text: DiscordVoiceActivity.muted ? "Unmute" : "Mute" }
                }

                RippleButton {
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordVoiceActivity.setDeafened(!DiscordVoiceActivity.deafened)
                    contentItem: MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        text: DiscordVoiceActivity.deafened ? "headset_off" : "headphones"
                        shape: DiscordVoiceActivity.deafened ? MaterialShape.Shape.Boom : MaterialShape.Shape.Clover4Leaf
                        implicitSize: 46
                        iconSize: 21
                        fill: DiscordVoiceActivity.deafened ? 1 : 0
                        color: DiscordVoiceActivity.deafened ? Appearance.colors.colErrorContainer : Appearance.colors.colTertiaryContainer
                        colSymbol: DiscordVoiceActivity.deafened ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnTertiaryContainer
                        scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
                        Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack } }
                    }
                    StyledToolTip { text: DiscordVoiceActivity.deafened ? "Undeafen" : "Deafen" }
                }

                RippleButton {
                    visible: DiscordVoiceActivity.supportsInputMode
                    implicitWidth: 48
                    implicitHeight: 48
                    buttonRadius: Appearance.rounding.full
                    colBackground: "transparent"
                    colBackgroundHover: Appearance.colors.colLayer1Hover
                    onClicked: DiscordVoiceActivity.togglePushToTalk()
                    contentItem: MaterialShapeWrappedMaterialSymbol {
                        anchors.centerIn: parent
                        text: DiscordVoiceActivity.pushToTalk ? "touch_app" : "graphic_eq"
                        shape: DiscordVoiceActivity.pushToTalk ? MaterialShape.Shape.Pill : MaterialShape.Shape.Cookie6Sided
                        implicitSize: 46
                        iconSize: 21
                        fill: DiscordVoiceActivity.pushToTalk ? 1 : 0
                        color: DiscordVoiceActivity.pushToTalk ? Appearance.colors.colPrimaryContainer : Appearance.colors.colSecondaryContainer
                        colSymbol: DiscordVoiceActivity.pushToTalk ? Appearance.colors.colOnPrimaryContainer : Appearance.colors.colOnSecondaryContainer
                        scale: parent?.down ? 0.88 : (parent?.hovered ? 1.08 : 1)
                        Behavior on scale { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Easing.OutBack } }
                    }
                    StyledToolTip {
                        text: DiscordVoiceActivity.pushToTalk
                            ? Translation.tr("Push to talk is on · switch to voice activity")
                            : Translation.tr("Voice activity is on · switch to push to talk")
                    }
                }
            }
        }

        // Push-to-talk state for a pinned overlay over a game: lit while your
        // key is held and Discord is sending your voice.
        Rectangle {
            id: pttChip
            readonly property bool transmitting: DiscordVoiceActivity.selfSpeaking && !DiscordVoiceActivity.muted
            visible: root.showPttIndicator && DiscordVoiceActivity.inVoice && DiscordVoiceActivity.pushToTalk
            Layout.fillWidth: true
            implicitHeight: pttRow.implicitHeight + 12
            radius: Appearance.rounding.full
            color: transmitting ? Appearance.colors.colPrimary
                : (DiscordVoiceActivity.muted ? Appearance.colors.colErrorContainer : Appearance.colors.colLayer2)
            Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
            readonly property color contentColor: transmitting ? Appearance.colors.colOnPrimary
                : (DiscordVoiceActivity.muted ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnLayer2)

            RowLayout {
                id: pttRow
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 24)
                spacing: 6
                MaterialSymbol {
                    text: DiscordVoiceActivity.muted ? "mic_off" : (pttChip.transmitting ? "mic" : "touch_app")
                    iconSize: Appearance.font.pixelSize.large
                    fill: pttChip.transmitting ? 1 : 0
                    color: pttChip.contentColor
                }
                StyledText {
                    Layout.fillWidth: true
                    text: DiscordVoiceActivity.muted ? Translation.tr("Push to talk · muted")
                        : (pttChip.transmitting ? Translation.tr("Transmitting")
                        : (DiscordVoiceActivity.pttShortcut !== ""
                            ? Translation.tr("Hold %1 to talk").arg(DiscordVoiceActivity.pttShortcut)
                            : Translation.tr("Push to talk")))
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: pttChip.transmitting ? Font.DemiBold : Font.Normal
                    color: pttChip.contentColor
                    elide: Text.ElideRight
                }
            }
        }

        GridLayout {
            visible: DiscordVoiceActivity.participantCount > 0
            Layout.fillWidth: root.columnMode || root.gridMode
            Layout.alignment: Qt.AlignHCenter
            columns: root.participantColumns
            rowSpacing: 6
            columnSpacing: root.columnMode ? 6 : (root.gridMode ? 12 : 16)
            Repeater {
                model: DiscordVoiceActivity.participantModel
                ParticipantAvatar {
                    id: participantDelegate
                    required property int index
                    visible: index < root.avatarLimit
                    avatarSize: root.effectiveAvatarSize
                    showName: true
                    maxNameWidth: root.columnMode ? 116 : (root.gridMode ? 96 : 76)
                    backgroundMode: root.participantBackground
                    backgroundOpacity: root.participantBackgroundOpacity
                    horizontalLayout: root.columnMode
                    nameOnLeft: root.namesOnLeft
                    Layout.fillWidth: root.columnMode || root.gridMode
                    Layout.fillHeight: root.gridMode

                    readonly property string userId: String(participant?.id ?? "")
                    readonly property bool adjustable: root.canAdjustUsers && userId !== "" && userId !== DiscordVoiceActivity.selfId
                    readonly property bool selected: userId !== "" && userId === root.selectedUserId

                    Rectangle {
                        z: -1
                        anchors.fill: parent
                        radius: Appearance.rounding.large
                        color: participantDelegate.selected ? Appearance.colors.colSecondaryContainer
                            : (participantHover.hovered && participantDelegate.adjustable
                                ? ColorUtils.transparentize(Appearance.colors.colSecondaryContainer, 0.6) : "transparent")
                        Behavior on color { ColorAnimation { duration: Appearance.animation.elementMoveFast.duration } }
                    }
                    HoverHandler {
                        id: participantHover
                        enabled: participantDelegate.adjustable
                        cursorShape: Qt.PointingHandCursor
                    }
                    TapHandler {
                        enabled: participantDelegate.adjustable
                        onTapped: root.selectedUserId = participantDelegate.selected ? "" : participantDelegate.userId
                    }
                }
            }
        }

        ParticipantVolumeCard {
            id: volumeCard
            Layout.fillWidth: true
            participant: root.selectedParticipant
            visible: root.selectedParticipant !== null
            onCloseRequested: root.selectedUserId = ""
        }

        // Join/leave and DM/mention notices, newest last, like Discord's own
        // overlay. Which kinds get queued is decided by the service's options.
        ColumnLayout {
            visible: DiscordVoiceActivity.noticeModel.count > 0
            Layout.fillWidth: true
            spacing: 4
            Repeater {
                model: DiscordVoiceActivity.noticeModel
                VoiceNotice {
                    Layout.fillWidth: true
                }
            }
        }

        RippleButton {
            // The running companion is proof enough: the install-time client
            // check can miss a Vesktop outside PATH (e.g. /opt/Vesktop).
            visible: DiscordVoiceActivity.companionOutdated
            enabled: !installProcess.running
            Layout.fillWidth: true
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: Appearance.colors.colSecondaryContainer
            onClicked: {
                root.installMessage = "Installing...";
                installProcess.running = true;
            }
            StyledText {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 24)
                text: installProcess.running ? Translation.tr("Updating Companion…")
                    : (root.installMessage !== "" ? root.installMessage : Translation.tr("Update Companion"))
                color: Appearance.colors.colOnSecondaryContainer
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledToolTip {
                text: Translation.tr("Per-user volume and the push-to-talk switch need the newer companion build. Close Vesktop while it installs.")
            }
        }

        RippleButton {
            visible: DiscordVoiceActivity.status === "auth_required" || DiscordVoiceActivity.status === "authorizing" || (!root.companionReady && root.isVencordClient)
            enabled: DiscordVoiceActivity.status !== "authorizing" && !installProcess.running
            Layout.fillWidth: true
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            colBackground: {
                if (root.companionReady) return Appearance.colors.colPrimary;
                if (root.isVencordClient && !root.companionReady) return Appearance.colors.colError;
                return Appearance.colors.colPrimary;
            }
            onClicked: {
                if (root.companionReady || !root.isVencordClient)
                    root.beginAuthorization();
                else {
                    root.installMessage = "Installing...";
                    installProcess.running = true;
                }
            }
            StyledText {
                anchors.centerIn: parent
                text: {
                    if (installProcess.running) return "Installing Companion…";
                    if (root.installMessage !== "") return root.installMessage;
                    if (DiscordVoiceActivity.status === "authorizing") return "Waiting for Discord…";
                    if (root.isVencordClient && !root.companionReady) return "Install Companion";
                    return "Authorize Discord";
                }
                color: Appearance.colors.colOnPrimary
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            StyledToolTip {
                visible: root.installMessage !== ""
                text: root.installMessage
            }
        }

        StyledText {
            visible: root.isVencordClient && !root.companionReady
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Make sure Discord/Vesktop is closed during installation")
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            wrapMode: Text.WordWrap
        }
    }
}

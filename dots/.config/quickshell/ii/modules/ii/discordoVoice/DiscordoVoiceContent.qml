pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "chat"

/**
 * Compact Discordo Voice control surface.
 *
 * The helper owns the call. This view is a picker and a set of explicit controls,
 * so closing the window never disconnects an active call.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property var svc: DiscordoVoiceService
    readonly property bool compact: root.width < ClockStyle.compactMax
    readonly property bool canAct: !root.svc.operationBusy && !root.svc.helperChecking
    readonly property bool connected: root.svc.connected
    readonly property bool joined: root.svc.joined
    readonly property bool hasGuildSelection: String(root.svc.selectedGuildId || "").length > 0

    // Sign-in: the panel replaces the page while the account is missing, refused or being changed
    property bool changingAccount: false
    property bool accountMenuOpen: false
    property bool confirmSignOut: false
    // The audio panel, and the person whose volume is being set
    property bool audioOpen: false
    property string volumeUserId: ""
    // While in a call, the guild and channel lists replace the stage when this is on
    property bool browsing: false
    // Seven controls with words do not fit under about 1100 px: icons then
    readonly property bool dockIcons: root.width < 1100
    onJoinedChanged: {
        if (!root.joined)
            root.browsing = false;
    }
    // Moving to another channel from the lists lands on the new call
    Connections {
        target: root.svc
        function onJoinedChannelIdChanged() {
            root.browsing = false;
        }
    }

    function deviceModel(names, fallback): var {
        const list = [{ "display": fallback, "value": "" }];
        for (const d of names)
            list.push({ "display": d.label, "value": d.name });
        return list;
    }

    function deviceIndex(model, value): int {
        for (let i = 0; i < model.length; ++i) {
            if (model[i].value === value)
                return i;
        }
        // A device that is saved but gone: show the default, which is what the helper uses
        return 0;
    }
    readonly property bool canChat: root.connected && !root.showAuth && root.svc.messagesSupported
    readonly property bool chatPage: root.canChat && GlobalStates.discordoPage === "chat"

    readonly property bool showAuth: root.changingAccount || (!root.connected && root.svc.needsSignIn)
    readonly property string bannerText: root.svc.errorMessage.length > 0 ? root.svc.errorMessage
        : root.svc.shareMessage.length > 0 ? root.svc.shareMessage
        : root.svc.cameraMessage.length > 0 ? root.svc.cameraMessage
        : root.svc.authNotice.length > 0 ? root.svc.authNotice : root.svc.statusMessage

    function closeAccountMenu(): void {
        root.accountMenuOpen = false;
        root.confirmSignOut = false;
    }

    // Server filter: shown once the list is long enough to need one
    property string guildFilter: ""
    readonly property var visibleGuilds: {
        const q = root.guildFilter.trim().toLowerCase();
        const all = root.svc.guilds;
        return q.length === 0 ? all : all.filter(g => String(g?.name ?? "").toLowerCase().indexOf(q) >= 0);
    }

    property real nowMs: Date.now()
    readonly property string callElapsed: {
        const s = Math.max(0, Math.floor((root.nowMs - root.svc.joinedAt) / 1000));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), sec = s % 60;
        const mm = (h > 0 && m < 10 ? "0" : "") + m, ss = (sec < 10 ? "0" : "") + sec;
        return (h > 0 ? h + ":" : "") + mm + ":" + ss;
    }
    Timer {
        interval: 1000
        repeat: true
        running: root.joined
        triggeredOnStart: true
        onTriggered: root.nowMs = Date.now()
    }

    readonly property string selectedGuildName: root.guildNameForId(root.svc.selectedGuildId)
    readonly property string connectionTitle: {
        if (root.svc.connectionState === "connecting" || root.svc.connectionState === "starting")
            return Translation.tr("Connecting to Discordo");
        if (root.svc.authRequired)
            return Translation.tr("Sign in to Discordo Voice");
        if (!root.svc.helperAvailable)
            return Translation.tr("Discordo Voice helper needed");
        if (root.svc.authState === "offline")
            return Translation.tr("Can't reach Discord");
        return Translation.tr("Join a voice channel");
    }
    readonly property string connectionText: {
        if (root.svc.connectionState === "connecting" || root.svc.connectionState === "starting")
            return Translation.tr("Connecting securely, then loading your servers.");
        if (root.svc.authRequired)
            return Translation.tr("Sign in with the Discordo client, then come back here to connect.");
        if (!root.svc.helperAvailable)
            return Translation.tr("Build the pinned Discordo Voice helper to browse your channels.");
        if (root.svc.authState === "offline")
            return Translation.tr("Check your connection, then try again. Your sign-in is still saved.");
        if (root.svc.authState === "rate_limited")
            return Translation.tr("Discord asked to slow down. Try again in a minute.");
        if (root.svc.signedIn && root.svc.authUser)
            return Translation.tr("Signed in as %1. Closing this window never disconnects an active call.").arg(root.svc.authUser.name);
        return Translation.tr("Connect with your saved Discordo sign-in. Closing this window never disconnects an active call.");
    }

    readonly property string connectionActionLabel: {
        if (root.svc.connectionState === "connecting" || root.svc.connectionState === "starting")
            return Translation.tr("Connecting…");
        if (!root.svc.helperAvailable)
            return Translation.tr("Build helper");
        if (root.svc.authRequired)
            return Translation.tr("Sign in");
        return Translation.tr("Connect");
    }
    readonly property string connectionActionSymbol: {
        if (!root.svc.helperAvailable)
            return "build";
        if (root.svc.authRequired)
            return "login";
        return "link";
    }

    readonly property string stateLabel: {
        switch (root.svc.connectionState) {
        case "connected": return Translation.tr("Connected");
        case "connecting": return Translation.tr("Connecting…");
        case "auth_required": return Translation.tr("Sign-in required");
        case "missing": return Translation.tr("Voice helper is missing");
        case "error": return Translation.tr("Connection needs attention");
        case "starting": return Translation.tr("Starting helper…");
        default: return Translation.tr("Ready to connect");
        }
    }

    function guildNameForId(guildId): string {
        const id = String(guildId || "");
        if (id.length === 0)
            return Translation.tr("Choose a server");
        const guild = root.svc.guilds.find(item => String(item?.id ?? "") === id);
        return String(guild?.name || Translation.tr("Unnamed server"));
    }

    function connectAction(): void {
        if (root.connected)
            root.svc.disconnect();
        else if (root.svc.authRequired)
            root.svc.signIn();
        else if (root.svc.helperAvailable)
            root.svc.connect();
    }

    function channelIsCurrent(modelData): bool {
        return root.joined && String(modelData?.id ?? "") === String(root.svc.joinedChannelId ?? "");
    }

    function channelActionLabel(modelData): string {
        if (root.channelIsCurrent(modelData))
            return Translation.tr("Joined");
        if (modelData?.can_join !== true)
            return Translation.tr("Unavailable");
        return root.joined ? Translation.tr("Switch") : Translation.tr("Join");
    }

    Component.onCompleted: {
        root.forceActiveFocus();
        root.svc.checkAuth(false);
    }

    // Back from the Discordo terminal client: see whether a sign-in was saved
    Connections {
        target: root.Window.window
        function onActiveChanged() {
            if (root.Window.window && root.Window.window.active && root.svc.awaitingTerminalSignIn)
                root.svc.checkAuth(true);
        }
    }

    Connections {
        target: root.svc
        function onAuthNoticeChanged() {
            if (root.svc.authNotice.length > 0 && root.svc.signedIn)
                root.changingAccount = false;
        }
    }

    Timer {
        interval: 5000
        running: root.svc.authNotice.length > 0
        onTriggered: root.svc.authNotice = ""
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Escape || (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q))) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.paneGap

        ClockTopBar {
            Layout.fillWidth: true
            title: root.chatPage ? Translation.tr("Discordo Chat") : Translation.tr("Discordo Voice")
            subtitle: root.connected
                ? root.joined
                    ? Translation.tr("%1 · %2").arg(root.stateLabel).arg(root.svc.joinedChannelName)
                    : root.hasGuildSelection
                        ? Translation.tr("%1 · %2").arg(root.stateLabel).arg(root.selectedGuildName)
                        : root.stateLabel
                : root.stateLabel
            onCloseRequested: root.closeRequested()

            Rectangle {
                id: accountChip
                visible: root.svc.signedIn && !root.showAuth
                implicitHeight: 40
                implicitWidth: chipRow.implicitWidth + 16
                radius: height / 2
                color: chipHover.hovered || root.accountMenuOpen ? ClockStyle.colSurfaceHover : "transparent"
                Accessible.role: Accessible.Button
                Accessible.name: Translation.tr("Account: %1").arg(root.svc.authUser ? root.svc.authUser.name : "")

                Behavior on color {
                    ColorAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                }

                RowLayout {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: ClockStyle.gapSmall

                    DiscordoAvatar {
                        size: 28
                        source: root.svc.authUser ? root.svc.authUser.avatar : ""
                        name: root.svc.authUser ? root.svc.authUser.name : ""
                    }
                    StyledText {
                        visible: !root.compact
                        Layout.maximumWidth: 140
                        text: root.svc.authUser ? root.svc.authUser.name : ""
                        elide: Text.ElideRight
                        color: ClockStyle.colOnBackground
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.Medium
                    }
                }

                HoverHandler { id: chipHover }
                TapHandler {
                    onTapped: {
                        root.confirmSignOut = false;
                        root.accountMenuOpen = !root.accountMenuOpen;
                    }
                }
            }

            ClockButton {
                visible: root.canChat
                label: Translation.tr("Voice")
                symbol: "graphic_eq"
                variant: root.chatPage ? "tonal" : "filled"
                iconOnly: root.compact
                Accessible.name: Translation.tr("Voice calls")
                onClicked: GlobalStates.discordoPage = "voice"
            }

            ClockButton {
                visible: root.canChat
                label: DiscordoChatService.totalMentions > 0
                    ? Translation.tr("Chat · %1").arg(DiscordoChatService.totalMentions) : Translation.tr("Chat")
                symbol: "forum"
                variant: root.chatPage ? "filled" : "tonal"
                iconOnly: root.compact
                Accessible.name: DiscordoChatService.totalMentions > 0
                    ? Translation.tr("Chat, %1 mentions").arg(DiscordoChatService.totalMentions) : Translation.tr("Discord chat")
                onClicked: GlobalStates.discordoPage = "chat"
            }

            ClockIconButton {
                visible: root.connected
                symbol: "refresh"
                tooltip: Translation.tr("Refresh server list")
                enabled: root.canAct
                Accessible.name: Translation.tr("Refresh Discordo server list")
                onClicked: root.svc.requestGuilds()
            }

            ClockIconButton {
                visible: root.connected
                symbol: "power_settings_new"
                tooltip: Translation.tr("Disconnect Discordo Voice")
                colIcon: ClockStyle.colError
                enabled: root.canAct
                Accessible.name: Translation.tr("Disconnect Discordo Voice")
                onClicked: root.svc.disconnect()
            }

            ClockButton {
                visible: !root.connected && !root.showAuth
                label: root.svc.authState === "offline" ? Translation.tr("Try again") : root.connectionActionLabel
                symbol: root.connectionActionSymbol
                variant: "filled"
                enabled: root.canAct && (root.svc.authRequired || root.svc.helperAvailable)
                Accessible.name: label
                onClicked: root.svc.authState === "offline" ? root.svc.checkAuth(true) : root.connectAction()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            visible: root.bannerText.length > 0
            radius: ClockStyle.radiusNormal
            color: root.svc.errorMessage.length > 0
                ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gap
                anchors.rightMargin: ClockStyle.gap
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: root.svc.errorMessage.length > 0 ? "error_outline" : "info"
                    iconSize: ClockStyle.iconNormal
                    fill: 1
                    color: root.svc.errorMessage.length > 0
                        ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.bannerText
                    color: root.svc.errorMessage.length > 0
                        ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer
                    elide: Text.ElideRight
                    font.pixelSize: ClockStyle.textSmall
                }
            }
        }

        DiscordoVoiceAuth {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.showAuth
            compact: root.compact
            changing: root.changingAccount
            onCancelRequested: {
                root.svc.cancelQr();
                root.changingAccount = false;
            }
        }

        // The disconnected state gets one compact, actionable hero. Connected browsing starts
        // directly at the panes so the useful list area remains generous at 680 × 520.
        ClockHero {
            Layout.fillWidth: true
            visible: !root.connected && !root.showAuth
            compact: true
            symbol: root.svc.authRequired ? "lock_open"
                : root.svc.connectionState === "connecting" || root.svc.connectionState === "starting"
                    ? "sync" : "headset_mic"
            shape: root.svc.authRequired ? MaterialShape.Shape.Clover4Leaf
                : MaterialShape.Shape.Cookie9Sided
            title: root.connectionTitle
            text: root.connectionText
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120
            visible: !root.connected && !root.showAuth

            ClockBadge {
                anchors.centerIn: parent
                visible: !root.svc.operationBusy && !root.svc.helperChecking && !root.svc.authChecking
                    && root.svc.connectionState !== "connecting" && root.svc.connectionState !== "starting"
                size: 64
                text: root.svc.authRequired ? "lock" : "headset_mic"
                shape: root.svc.authRequired ? MaterialShape.Shape.Clover4Leaf
                    : MaterialShape.Shape.Cookie9Sided
                color: ClockStyle.colSurfaceHigh
                colSymbol: ClockStyle.colOnSurfaceVariant
            }

            ColumnLayout {
                width: Math.min(parent.width - ClockStyle.gapHuge * 2, 240)
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                visible: root.svc.operationBusy || root.svc.helperChecking || root.svc.authChecking
                    || root.svc.connectionState === "connecting" || root.svc.connectionState === "starting"
                spacing: ClockStyle.gapSmall

                MaterialLoadingIndicator {
                    Layout.alignment: Qt.AlignHCenter
                    implicitSize: 56
                    color: ClockStyle.colPrimaryContainer
                    shapeColor: ClockStyle.colOnPrimaryContainer
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: root.stateLabel
                    color: ClockStyle.colOnBackground
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textLarge
                }
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.chatPage
            active: root.chatPage
            sourceComponent: DiscordoChatView {
                onCloseRequested: GlobalStates.discordoPage = "voice"
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.connected && !root.showAuth && !root.chatPage
            spacing: ClockStyle.paneGap

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !root.joined || root.browsing
                spacing: ClockStyle.paneGap

                ClockPane {
                    id: guildPane
                    Layout.fillHeight: true
                    Layout.preferredWidth: root.compact
                        ? 196 : Math.min(260, Math.max(196, parent.width * 0.29))
                    Layout.minimumWidth: 188
                    title: Translation.tr("Servers")
                    symbol: "dns"
                    shape: MaterialShape.Shape.Cookie9Sided

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Pick a server to browse its voice rooms")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }

                    ClockFormField {
                        visible: root.svc.guilds.length > 6
                        symbol: "search"
                        placeholder: Translation.tr("Find a server")
                        implicitHeight: 44
                        onTextChanged: root.guildFilter = text
                    }

                    Item {
                        id: guildListHost
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 96
                        implicitHeight: 180
                        clip: true

                        ListView {
                            id: guildList
                            anchors.fill: parent
                            visible: root.svc.guilds.length > 0
                            clip: true
                            spacing: ClockStyle.gapSmall
                            model: root.visibleGuilds
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: RippleButton {
                                required property var modelData
                                width: guildList.width
                                implicitHeight: ClockStyle.rowHeight
                                buttonRadius: ClockStyle.radiusNormal
                                buttonRadiusPressed: ClockStyle.radiusSmall
                                interactionScale: 1
                                scaleBehaviorEnabled: false
                                enabled: root.canAct
                                colBackground: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                    ? ClockStyle.colActiveCard : ClockStyle.colSurfaceHigh
                                colBackgroundHover: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                    ? ClockStyle.colActiveCardHover : ClockStyle.colSurfaceHover
                                colRipple: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                    ? ClockStyle.colPrimaryContainerActive : ClockStyle.colSurfaceActive
                                Accessible.name: Translation.tr("Select server %1").arg(
                                    String(modelData.name || Translation.tr("Unnamed server")))
                                onClicked: root.svc.requestChannels(String(modelData.id || ""))

                                contentItem: RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: ClockStyle.gapSmall
                                    anchors.rightMargin: ClockStyle.gapSmall
                                    spacing: ClockStyle.gapSmall

                                    ClockBadge {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        size: 36
                                        shape: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                            ? ClockStyle.morphOf(MaterialShape.Shape.Cookie4Sided)
                                            : MaterialShape.Shape.Cookie4Sided
                                        text: "dns"
                                        color: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                            ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                                        colSymbol: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                            ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(modelData.name || Translation.tr("Unnamed server"))
                                        elide: Text.ElideRight
                                        color: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                            ? ClockStyle.colOnActiveCard : ClockStyle.colOnSurface
                                        font.pixelSize: ClockStyle.textNormal
                                        font.weight: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                            ? Font.DemiBold : Font.Medium
                                    }

                                    MaterialSymbol {
                                        visible: String(modelData?.id ?? "") === root.svc.selectedGuildId
                                        text: "check"
                                        iconSize: ClockStyle.iconSmall
                                        fill: 1
                                        color: ClockStyle.colOnActiveCard
                                    }
                                }
                            }
                        }

                        ClockEmptyState {
                            anchors.centerIn: parent
                            visible: root.svc.guilds.length === 0
                                && !root.svc.operationBusy && !root.svc.helperChecking
                            shapeSize: 72
                            symbol: "dns"
                            shape: "Cookie4Sided"
                            title: Translation.tr("No servers yet")
                            subtitle: Translation.tr("Refresh after connecting to Discordo.")
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: root.svc.guilds.length === 0
                                && (root.svc.operationBusy || root.svc.helperChecking)
                            spacing: ClockStyle.gapSmall

                            MaterialLoadingIndicator {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 42
                                color: ClockStyle.colPrimaryContainer
                                shapeColor: ClockStyle.colOnPrimaryContainer
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Loading servers…")
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }
                }

                ClockPane {
                    id: channelPane
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 300
                    title: root.hasGuildSelection
                        ? Translation.tr("Voice · %1").arg(root.selectedGuildName)
                        : Translation.tr("Choose a server")
                    symbol: "headset_mic"
                    shape: MaterialShape.Shape.SoftBurst
                    count: root.hasGuildSelection ? root.svc.channels.length : -1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.hasGuildSelection
                            ? Translation.tr("Choose a room to join or switch into")
                            : Translation.tr("Your voice rooms appear here")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                        elide: Text.ElideRight
                    }

                    Item {
                        id: channelListHost
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.minimumHeight: 96
                        implicitHeight: 180
                        clip: true

                        ListView {
                            id: channelList
                            anchors.fill: parent
                            visible: root.hasGuildSelection && root.svc.channels.length > 0
                            clip: true
                            spacing: ClockStyle.gapSmall
                            model: root.svc.channels
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                required property var modelData
                                width: channelList.width
                                implicitHeight: 60
                                radius: ClockStyle.radiusNormal
                                color: root.channelIsCurrent(modelData)
                                    ? ClockStyle.colActiveCard : ClockStyle.colSurfaceHigh
                                Accessible.name: Translation.tr("%1 voice channel, %2").arg(
                                    String(modelData.name || Translation.tr("Voice channel")))
                                    .arg(root.channelActionLabel(modelData))

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: ClockStyle.gapSmall
                                    anchors.rightMargin: ClockStyle.gapSmall
                                    spacing: ClockStyle.gapSmall

                                    ClockBadge {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 36
                                        Layout.preferredHeight: 36
                                        size: 36
                                        shape: root.channelIsCurrent(modelData)
                                            ? ClockStyle.morphOf(MaterialShape.Shape.Clover4Leaf)
                                            : MaterialShape.Shape.Clover4Leaf
                                        text: root.channelIsCurrent(modelData) ? "headset_mic" : "volume_up"
                                        color: root.channelIsCurrent(modelData)
                                            ? ClockStyle.colPrimary : ClockStyle.colSecondaryContainer
                                        colSymbol: root.channelIsCurrent(modelData)
                                            ? ClockStyle.colOnPrimary : ClockStyle.colOnSecondaryContainer
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: String(modelData.name || Translation.tr("Voice channel"))
                                            elide: Text.ElideRight
                                            color: root.channelIsCurrent(modelData)
                                                ? ClockStyle.colOnActiveCard : ClockStyle.colOnSurface
                                            font.pixelSize: ClockStyle.textNormal
                                            font.weight: root.channelIsCurrent(modelData)
                                                ? Font.DemiBold : Font.Medium
                                        }

                                        StyledText {
                                            Layout.fillWidth: true
                                            text: Translation.tr("%1 connected").arg(root.channelIsCurrent(modelData)
                                                ? root.svc.participants.length : Number(modelData.user_count || 0))
                                            elide: Text.ElideRight
                                            color: root.channelIsCurrent(modelData)
                                                ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                                            font.pixelSize: ClockStyle.textSmall
                                        }
                                    }

                                    Item {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 112
                                        Layout.minimumWidth: 112
                                        Layout.maximumWidth: 112
                                        Layout.preferredHeight: ClockStyle.buttonHeight

                                        ClockButton {
                                            anchors.fill: parent
                                            visible: !root.channelIsCurrent(modelData) && modelData.can_join === true
                                            label: root.joined ? Translation.tr("Switch") : Translation.tr("Join")
                                            symbol: root.joined ? "swap_horiz" : "login"
                                            variant: "tonal"
                                            enabled: root.canAct
                                            Accessible.name: Translation.tr("%1 %2").arg(
                                                root.joined ? Translation.tr("Switch to") : Translation.tr("Join"))
                                                .arg(String(modelData.name || Translation.tr("voice channel")))
                                            onClicked: {
                                                if (!root.channelIsCurrent(modelData))
                                                    root.svc.join(String(modelData.guild_id), String(modelData.id));
                                            }
                                        }

                                        Rectangle {
                                            anchors.fill: parent
                                            visible: root.channelIsCurrent(modelData)
                                            radius: ClockStyle.pill(ClockStyle.buttonHeight)
                                            color: Qt.alpha(ClockStyle.colOnActiveCard, 0.14)
                                            Accessible.name: Translation.tr("Joined")

                                            RowLayout {
                                                anchors.centerIn: parent
                                                spacing: ClockStyle.gapTiny

                                                MaterialSymbol {
                                                    text: "check"
                                                    iconSize: ClockStyle.iconSmall
                                                    fill: 1
                                                    color: ClockStyle.colOnActiveCard
                                                }

                                                StyledText {
                                                    text: Translation.tr("Joined")
                                                    color: ClockStyle.colOnActiveCard
                                                    font.pixelSize: ClockStyle.textSmall
                                                    font.weight: Font.DemiBold
                                                }
                                            }
                                        }

                                        StyledText {
                                            anchors.fill: parent
                                            visible: !root.channelIsCurrent(modelData) && modelData.can_join !== true
                                            text: Translation.tr("Unavailable")
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            color: ClockStyle.colOnSurfaceVariant
                                            font.pixelSize: ClockStyle.textSmall
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }
                        }

                        ClockEmptyState {
                            anchors.centerIn: parent
                            visible: root.hasGuildSelection && root.svc.channels.length === 0
                                && !root.svc.channelLoading && !root.svc.operationBusy
                            shapeSize: 72
                            symbol: root.hasGuildSelection ? "headset_off" : "touch_app"
                            shape: "SoftBurst"
                            title: root.hasGuildSelection
                                ? Translation.tr("No joinable rooms") : Translation.tr("Choose a server")
                            subtitle: root.hasGuildSelection
                                ? Translation.tr("This server has no voice channel you can join.")
                                : Translation.tr("Select a server on the left to load its rooms.")
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: root.svc.channelLoading || (root.hasGuildSelection
                                && root.svc.channels.length === 0 && root.svc.operationBusy)
                            spacing: ClockStyle.gapSmall

                            MaterialLoadingIndicator {
                                Layout.alignment: Qt.AlignHCenter
                                implicitSize: 42
                                color: ClockStyle.colPrimaryContainer
                                shapeColor: ClockStyle.colOnPrimaryContainer
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: Translation.tr("Loading voice rooms…")
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }
                }
            }

            // Everyone in the call, with their cameras
            DiscordoCallStage {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 120
                visible: root.joined && !root.browsing
                active: root.joined && !root.browsing && GlobalStates.discordoVoiceOpen
                participants: root.svc.participants
                speakingIds: root.svc.speakingIds
                remoteVideo: root.svc.remoteVideo
                audioSupported: root.svc.audioSupported
                onVolumeRequested: userId => root.volumeUserId = root.volumeUserId === userId ? "" : userId
            }

            // One dock owns the active call: who and where, the voice controls, and
            // everyone in the room. It is as tall as its content (the people wrap onto more
            // rows as the room fills), so nothing collapses or hides.
            Rectangle {
                id: callDock
                Layout.fillWidth: true
                visible: root.joined
                Layout.preferredHeight: dockColumn.implicitHeight + ClockStyle.gap * 2
                radius: ClockStyle.radiusCard
                color: ClockStyle.colActiveCard

                ColumnLayout {
                    id: dockColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: ClockStyle.gap
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gapSmall

                        ClockBadge {
                            Layout.alignment: Qt.AlignVCenter
                            size: 44
                            shape: MaterialShape.Shape.Cookie9Sided
                            text: "headset_mic"
                            color: ClockStyle.colPrimary
                            colSymbol: ClockStyle.colOnPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                text: root.svc.joinedChannelName
                                elide: Text.ElideRight
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("%1 · %2 in call · %3").arg(
                                    root.guildNameForId(root.svc.joinedGuildId)).arg(root.svc.participants.length)
                                    .arg(root.callElapsed)
                                elide: Text.ElideRight
                                color: ClockStyle.colOnActiveCard
                                opacity: 0.78
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }

                        ClockButton {
                            label: root.browsing ? Translation.tr("Back to call") : Translation.tr("Channels")
                            symbol: root.browsing ? "grid_view" : "forum"
                            variant: root.browsing ? "filled" : "tonal"
                            iconOnly: root.dockIcons
                            Accessible.name: root.browsing
                                ? Translation.tr("Back to the call") : Translation.tr("Browse servers and channels")
                            onClicked: root.browsing = !root.browsing
                        }

                        ClockButton {
                            label: root.svc.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                            symbol: root.svc.muted ? "mic_off" : "mic"
                            variant: root.svc.muted ? "filled" : "tonal"
                            danger: root.svc.muted
                            iconOnly: root.dockIcons
                            enabled: root.canAct
                            Accessible.name: root.svc.muted
                                ? Translation.tr("Unmute microphone") : Translation.tr("Mute microphone")
                            onClicked: root.svc.toggleMute()
                        }

                        ClockButton {
                            label: root.svc.deafened ? Translation.tr("Undeafen") : Translation.tr("Deafen")
                            symbol: root.svc.deafened ? "headset_off" : "headphones"
                            variant: root.svc.deafened ? "filled" : "tonal"
                            danger: root.svc.deafened
                            iconOnly: root.dockIcons
                            enabled: root.canAct
                            Accessible.name: root.svc.deafened
                                ? Translation.tr("Restore voice audio") : Translation.tr("Deafen voice audio")
                            onClicked: root.svc.toggleDeafen()
                        }

                        ClockButton {
                            visible: root.svc.videoSupported
                            label: root.svc.shareState === "live" ? Translation.tr("Stop sharing")
                                : root.svc.shareState === "picking" ? Translation.tr("Choose a screen…")
                                : root.svc.shareState === "starting" ? Translation.tr("Starting…") : Translation.tr("Share screen")
                            symbol: root.svc.shareState === "live" ? "stop_screen_share" : "screen_share"
                            variant: root.svc.shareState === "live" ? "filled" : "tonal"
                            danger: root.svc.shareState === "live"
                            iconOnly: root.dockIcons
                            enabled: root.svc.shareState === "idle" || root.svc.shareState === "live"
                            Accessible.name: root.svc.shareState === "live"
                                ? Translation.tr("Stop sharing your screen") : Translation.tr("Share your screen")
                            onClicked: root.svc.shareState === "live" ? root.svc.stopShare() : root.svc.startShare(Persistent.states.discordoVoice.sharePreset, true)
                        }

                        ClockButton {
                            visible: root.svc.cameraSupported
                            label: root.svc.cameraState === "live" ? Translation.tr("Stop camera")
                                : root.svc.cameraState === "starting" ? Translation.tr("Starting…") : Translation.tr("Camera")
                            symbol: root.svc.cameraState === "live" ? "videocam_off" : "videocam"
                            variant: root.svc.cameraState === "live" ? "filled" : "tonal"
                            danger: root.svc.cameraState === "live"
                            iconOnly: root.dockIcons
                            enabled: root.svc.cameraState === "idle" || root.svc.cameraState === "live"
                            Accessible.name: root.svc.cameraState === "live"
                                ? Translation.tr("Turn your camera off") : Translation.tr("Turn your camera on")
                            onClicked: root.svc.cameraState === "live" ? root.svc.stopCamera() : root.svc.startCamera(Persistent.states.discordoVoice.cameraPreset)
                        }

                        ClockButton {
                            visible: root.svc.audioSupported
                            label: Translation.tr("Audio")
                            symbol: "tune"
                            variant: root.audioOpen ? "filled" : "tonal"
                            iconOnly: true
                            Accessible.name: Translation.tr("Audio settings")
                            onClicked: {
                                root.audioOpen = !root.audioOpen;
                                if (root.audioOpen)
                                    root.svc.refreshAudioDevices();
                            }
                        }

                        ClockButton {
                            label: Translation.tr("Leave")
                            symbol: "logout"
                            variant: "text"
                            danger: true
                            iconOnly: root.dockIcons
                            enabled: root.canAct
                            Accessible.name: Translation.tr("Leave voice channel")
                            onClicked: root.svc.leave()
                        }
                    }

                    // Audio: devices, microphone level and gate
                    ColumnLayout {
                        id: audioPanel
                        Layout.fillWidth: true
                        visible: root.audioOpen && (root.svc.audioSupported || root.svc.videoSupported || root.svc.cameraSupported)
                        spacing: ClockStyle.gapSmall

                        readonly property var outputModel: root.deviceModel(root.svc.audioOutputs, Translation.tr("Default speakers"))
                        readonly property var qualityModel: [
                            { "value": "480p30", "display": "480p · 30 fps" },
                            { "value": "720p30", "display": "720p · 30 fps" },
                            { "value": "720p60", "display": "720p · 60 fps" },
                            { "value": "1080p30", "display": "1080p · 30 fps" },
                            { "value": "1080p60", "display": "1080p · 60 fps" },
                            { "value": "1440p30", "display": "1440p · 30 fps" },
                            { "value": "1440p60", "display": "1440p · 60 fps" },
                            { "value": "2160p30", "display": "4K · 30 fps" },
                            { "value": "2160p60", "display": "4K · 60 fps" }
                        ]
                        readonly property var cameraModel: [
                            { "value": "480p30", "display": "Camera 480p · 30 fps" },
                            { "value": "720p30", "display": "Camera 720p · 30 fps" },
                            { "value": "1080p30", "display": "Camera 1080p · 30 fps" }
                        ]
                        readonly property var inputModel: root.deviceModel(root.svc.audioInputs, Translation.tr("Default microphone"))

                        StyledComboBox {
                            Layout.fillWidth: true
                            buttonIcon: "speaker"
                            model: audioPanel.outputModel
                            textRole: "display"
                            currentIndex: root.deviceIndex(audioPanel.outputModel, root.svc.audioOutput)
                            Accessible.name: Translation.tr("Output device")
                            onActivated: index => root.svc.setAudio({ "output": audioPanel.outputModel[index].value })
                        }

                        StyledComboBox {
                            Layout.fillWidth: true
                            buttonIcon: "mic"
                            model: audioPanel.inputModel
                            textRole: "display"
                            currentIndex: root.deviceIndex(audioPanel.inputModel, root.svc.audioInput)
                            Accessible.name: Translation.tr("Input device")
                            onActivated: index => root.svc.setAudio({ "input": audioPanel.inputModel[index].value })
                        }

                        StyledComboBox {
                            Layout.fillWidth: true
                            visible: root.svc.videoSupported
                            buttonIcon: "screen_share"
                            model: audioPanel.qualityModel
                            textRole: "display"
                            currentIndex: Math.max(0, audioPanel.qualityModel.findIndex(q => q.value === Persistent.states.discordoVoice.sharePreset))
                            Accessible.name: Translation.tr("Screen share quality")
                            onActivated: index => Persistent.states.discordoVoice.sharePreset = audioPanel.qualityModel[index].value
                        }

                        StyledComboBox {
                            Layout.fillWidth: true
                            visible: root.svc.cameraSupported
                            buttonIcon: "videocam"
                            model: audioPanel.cameraModel
                            textRole: "display"
                            currentIndex: Math.max(0, audioPanel.cameraModel.findIndex(q => q.value === Persistent.states.discordoVoice.cameraPreset))
                            Accessible.name: Translation.tr("Camera quality")
                            onActivated: index => Persistent.states.discordoVoice.cameraPreset = audioPanel.cameraModel[index].value
                        }

                        ClockFormToggle {
                            visible: root.svc.cameraSupported
                            symbol: "flip"
                            label: Translation.tr("Flip for others")
                            description: Translation.tr("Your own tile is mirrored with its button. This flips what they see, from the next time your camera starts.")
                            checked: Persistent.states.discordoVoice.mirrorSent
                            onToggled: value => Persistent.states.discordoVoice.mirrorSent = value
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.preferredWidth: 110
                                text: Translation.tr("Mic level")
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textSmall
                            }
                            StyledSlider {
                                Layout.fillWidth: true
                                from: 0
                                to: 200
                                stepSize: 5
                                value: root.svc.micGain
                                stopIndicatorValues: [100]
                                tooltipContent: `${Math.round(value)}%`
                                onMoved: root.svc.setAudio({ "micGain": value })
                            }
                            StyledText {
                                Layout.preferredWidth: 44
                                horizontalAlignment: Text.AlignRight
                                text: root.svc.micGain + "%"
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.preferredWidth: 110
                                text: Translation.tr("Mic sensitivity")
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textSmall
                            }
                            // Further left opens the gate for quieter sound
                            StyledSlider {
                                Layout.fillWidth: true
                                from: -80
                                to: -10
                                stepSize: 1
                                value: root.svc.sensitivityDb
                                stopIndicatorValues: []
                                tooltipContent: `${Math.round(value)} dB`
                                onMoved: root.svc.setAudio({ "sensitivityDb": value })
                            }
                            StyledText {
                                Layout.preferredWidth: 44
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(root.svc.sensitivityDb) + " dB"
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }

                        ClockFormToggle {
                            visible: root.svc.audioSupported
                            symbol: "notifications_active"
                            label: Translation.tr("Join and leave sounds")
                            description: Translation.tr("A short chime when someone joins or leaves, and when you do. Not played while you are deafened.")
                            checked: root.svc.joinSounds
                            onToggled: value => root.svc.setAudio({ "joinSounds": value })
                        }

                        // Sound that comes in ahead of the picture: hold it back while you watch someone's video
                        RowLayout {
                            Layout.fillWidth: true
                            visible: root.svc.videoSupported
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.preferredWidth: 110
                                text: Translation.tr("Lip-sync delay")
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textSmall
                            }
                            StyledSlider {
                                Layout.fillWidth: true
                                from: 0
                                to: 240
                                stepSize: 20
                                value: root.svc.videoSyncMs
                                stopIndicatorValues: [80]
                                tooltipContent: `${Math.round(value)} ms`
                                onMoved: root.svc.setAudio({ "videoSyncMs": value })
                            }
                            StyledText {
                                Layout.preferredWidth: 44
                                horizontalAlignment: Text.AlignRight
                                text: root.svc.videoSyncMs + " ms"
                                color: ClockStyle.colOnActiveCard
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }

                    // One person's volume, opened from their tile
                    RowLayout {
                        id: volumeRow
                        readonly property var person: {
                            for (const p of root.svc.participants) {
                                if (String(p.id) === root.volumeUserId)
                                    return p;
                            }
                            return null;
                        }
                        readonly property int percent: root.svc.userVolume(root.volumeUserId)
                        Layout.fillWidth: true
                        visible: root.svc.audioSupported && volumeRow.person !== null
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            Layout.preferredWidth: 110
                            text: String(volumeRow.person?.name || Translation.tr("Participant"))
                            elide: Text.ElideRight
                            color: ClockStyle.colOnActiveCard
                            font.pixelSize: ClockStyle.textSmall
                        }
                        StyledSlider {
                            Layout.fillWidth: true
                            from: 0
                            to: 200
                            stepSize: 5
                            value: volumeRow.percent
                            stopIndicatorValues: [100]
                            tooltipContent: `${Math.round(value)}%`
                            onMoved: root.svc.setUserVolume(root.volumeUserId, value)
                        }
                        StyledText {
                            Layout.preferredWidth: 44
                            horizontalAlignment: Text.AlignRight
                            text: volumeRow.percent + "%"
                            color: ClockStyle.colOnActiveCard
                            font.pixelSize: ClockStyle.textSmall
                        }
                        ClockButton {
                            label: Translation.tr("Reset")
                            symbol: "restart_alt"
                            variant: "text"
                            iconOnly: true
                            enabled: volumeRow.percent !== 100
                            Accessible.name: Translation.tr("Reset volume")
                            onClicked: root.svc.setUserVolume(root.volumeUserId, 100)
                        }
                    }
                }
            }
        }
    }

    // ── Account menu ─────────────────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        z: 20
        visible: root.accountMenuOpen
        onClicked: root.closeAccountMenu()
    }

    StyledRectangularShadow {
        target: accountMenu
        visible: accountMenu.visible
    }

    Rectangle {
        id: accountMenu
        z: 21
        visible: root.accountMenuOpen && root.svc.signedIn
        anchors {
            top: parent.top
            right: parent.right
            topMargin: ClockStyle.topBarHeight + ClockStyle.gapTiny
            rightMargin: ClockStyle.paneGap
        }
        width: Math.min(340, root.width - ClockStyle.paneGap * 2)
        implicitHeight: menuColumn.implicitHeight + ClockStyle.gapLarge * 2
        height: implicitHeight
        radius: ClockStyle.radiusCard
        color: ClockStyle.colSheet

        ColumnLayout {
            id: menuColumn
            anchors {
                fill: parent
                margins: ClockStyle.gapLarge
            }
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                DiscordoAvatar {
                    size: 52
                    source: root.svc.authUser ? root.svc.authUser.avatar : ""
                    name: root.svc.authUser ? root.svc.authUser.name : ""
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: root.svc.authUser ? root.svc.authUser.name : ""
                        elide: Text.ElideRight
                        color: ClockStyle.colOnBackground
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textLarge
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.svc.authChecking ? Translation.tr("Checking with Discord…")
                            : Translation.tr("Signed in · checked %1").arg(Qt.formatTime(new Date(root.svc.authCheckedAt), "HH:mm"))
                        elide: Text.ElideRight
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.svc.authAppliesAfterCall
                wrapMode: Text.WordWrap
                text: Translation.tr("The change applies once you leave the call.")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.svc.authProblem !== null && root.svc.authProblem.action === "remove"
                wrapMode: Text.WordWrap
                text: root.svc.authProblem ? root.svc.authProblem.message : ""
                color: ClockStyle.colError
                font.pixelSize: ClockStyle.textSmall
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !root.confirmSignOut
                spacing: ClockStyle.gapTiny

                ClockButton {
                    Layout.fillWidth: true
                    variant: "text"
                    symbol: "refresh"
                    label: Translation.tr("Check again")
                    enabled: !root.svc.authChecking
                    onClicked: root.svc.checkAuth(true)
                }
                ClockButton {
                    Layout.fillWidth: true
                    variant: "text"
                    symbol: "switch_account"
                    label: Translation.tr("Change account")
                    onClicked: {
                        root.closeAccountMenu();
                        root.changingAccount = true;
                    }
                }
                ClockButton {
                    Layout.fillWidth: true
                    variant: "text"
                    danger: true
                    symbol: "logout"
                    label: Translation.tr("Sign out")
                    enabled: !root.svc.authBusy
                    onClicked: root.confirmSignOut = true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.confirmSignOut
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: Translation.tr("Sign out of Discordo Voice? The saved sign-in is shared with the Discordo client, so it is signed out too.")
                    color: ClockStyle.colOnBackground
                    font.pixelSize: ClockStyle.textNormal
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    ClockButton {
                        Layout.fillWidth: true
                        variant: "text"
                        label: Translation.tr("Cancel")
                        onClicked: root.confirmSignOut = false
                    }
                    ClockButton {
                        Layout.fillWidth: true
                        variant: "filled"
                        danger: true
                        symbol: "logout"
                        label: Translation.tr("Sign out")
                        enabled: !root.svc.authBusy
                        onClicked: {
                            root.svc.removeToken();
                            root.closeAccountMenu();
                        }
                    }
                }
            }
        }
    }
}

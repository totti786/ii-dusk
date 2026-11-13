pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Window
import Quickshell
import Quickshell.Io

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.discordoVoice
import "DiscordMarkdown.js" as Md

/**
 * Discord text chat: servers on the left, their channels (or your direct chats) beside them, and the open
 * conversation with its composer. The helper owns the connection; this is the face of DiscordoChatService.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property var svc: DiscordoChatService
    readonly property var voice: DiscordoVoiceService
    readonly property bool dmMode: root.svc.guildId === "0" || root.svc.guildId === ""
    readonly property bool compact: root.width < 760

    property var replyTarget: null
    property var editTarget: null
    property bool pingReply: true
    property var attachments: []
    property bool emojiOpen: false
    property string emojiMessage: ""
    property string panel: ""   // "", "pins", "search"
    property string channelFilter: ""
    property bool stuck: true
    property bool olderPending: false
    property real olderHeight: 0
    property real olderY: 0

    readonly property var guildChannels: root.svc.channelsByGuild
    readonly property var channelList: root.dmMode ? root.svc.dms : (root.guildChannels[root.svc.guildId] ?? [])

    readonly property var currentChannel: {
        const id = root.svc.channelId;
        if (root.dmMode)
            return root.svc.dms.find(d => String(d.id) === id) ?? null;
        const list = root.svc.channelsByGuild[root.svc.guildId] ?? [];
        return list.find(c => String(c.id) === id) ?? null;
    }
    readonly property string channelTitle: root.currentChannel
        ? (root.dmMode ? String(root.currentChannel.name) : "# " + String(root.currentChannel.name)) : ""
    readonly property bool canSend: root.dmMode || !root.currentChannel || root.currentChannel.can_send !== false

    function guildName(id): string {
        const g = root.voice.guilds.find(x => String(x.id) === String(id));
        return g ? String(g.name) : "";
    }

    function startReply(m): void {
        root.editTarget = null;
        root.replyTarget = { "id": String(m.id), "author": String(m.author.name) };
        composer.forceActiveFocus();
    }

    function startEdit(m): void {
        root.replyTarget = null;
        root.editTarget = { "id": String(m.id) };
        composer.text = String(m.content);
        composer.forceActiveFocus();
        composer.cursorPosition = composer.length;
    }

    function cancelCompose(): void {
        if (root.editTarget)
            composer.text = "";
        root.replyTarget = null;
        root.editTarget = null;
        root.emojiOpen = false;
        root.panel = "";
    }

    function submit(): void {
        const text = composer.text;
        if (root.editTarget) {
            if (text.trim().length > 0)
                root.svc.editMessage(root.editTarget.id, text);
            root.editTarget = null;
            composer.text = "";
            return;
        }
        if (text.trim().length === 0 && root.attachments.length === 0)
            return;
        root.svc.sendMessage(text, root.replyTarget ? root.replyTarget.id : "", root.pingReply, root.attachments);
        composer.text = "";
        root.replyTarget = null;
        root.attachments = [];
        root.stuck = true;
    }

    function editLast(): void {
        const model = root.svc.messageModel;
        for (let i = model.count - 1; i >= 0; --i) {
            if (model.get(i).mine === true) {
                root.startEdit(model.get(i));
                return;
            }
        }
    }

    function addFiles(paths): void {
        const next = root.attachments.slice();
        for (const p of paths) {
            const path = String(p).replace(/^file:\/\//, "");
            if (path.length > 0 && next.indexOf(path) < 0 && next.length < 10)
                next.push(path);
        }
        root.attachments = next;
    }

    function jumpTo(id): void {
        const model = root.svc.messageModel;
        for (let i = 0; i < model.count; ++i) {
            if (String(model.get(i).id) === String(id)) {
                list.positionViewAtIndex(i, ListView.Center);
                root.stuck = false;
                return;
            }
        }
    }

    Process {
        id: picker
        command: ["zenity", "--file-selection", "--multiple", "--separator=\n", "--title=" + Translation.tr("Attach files")]
        stdout: StdioCollector {
            onStreamFinished: root.addFiles(text.split("\n").filter(s => s.length > 0))
        }
    }

    Timer {
        id: readTimer
        interval: 600
        onTriggered: if (root.stuck && root.svc.chatFocused) root.svc.markRead()
    }

    Connections {
        target: root.svc.messageModel
        function onRowsInserted(parent, first, last) {
            if (first === 0 && root.olderPending) {
                Qt.callLater(() => {
                    list.contentY = root.olderY + (list.contentHeight - root.olderHeight);
                    root.olderPending = false;
                });
            } else if (root.stuck) {
                Qt.callLater(() => list.positionViewAtEnd());
                readTimer.restart();
            }
        }
        function onModelReset() {
            root.stuck = true;
        }
    }

    Connections {
        target: root.svc
        function onHistoryReadyChanged() {
            if (root.svc.historyReady) {
                root.stuck = true;
                Qt.callLater(() => list.positionViewAtEnd());
            }
        }
        function onChannelIdChanged() {
            root.replyTarget = null;
            root.editTarget = null;
            root.panel = "";
            composer.text = "";
            root.attachments = [];
        }
    }

    Component.onCompleted: {
        root.svc.connectIfNeeded();
        if (root.svc.ready)
            root.svc.refreshLists();
        const target = GlobalStates.discordoChatTarget;
        if (target !== "") {
            root.svc.openChannel(target, GlobalStates.discordoChatTargetGuild);
            GlobalStates.discordoChatTarget = "";
        } else if (root.svc.channelId !== "" && root.svc.ready) {
            root.svc.openChannel(root.svc.channelId, root.svc.guildId);
        }
        if (root.svc.guildId !== "" && root.svc.guildId !== "0" && root.svc.ready)
            root.svc.selectGuild(root.svc.guildId);
    }

    Connections {
        target: GlobalStates
        function onDiscordoChatTargetChanged() {
            if (GlobalStates.discordoChatTarget !== "") {
                root.svc.openChannel(GlobalStates.discordoChatTarget, GlobalStates.discordoChatTargetGuild);
                GlobalStates.discordoChatTarget = "";
            }
        }
    }

    // The service skips a toast for the channel on screen, but only while this window has the focus
    Binding {
        target: DiscordoChatService
        property: "windowFocused"
        value: root.Window.active
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    // Not usable: say why instead of showing empty panes
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.svc.supported || !root.voice.connected
        width: Math.min(parent.width - 48, 360)
        spacing: ClockStyle.gap

        ClockBadge {
            Layout.alignment: Qt.AlignHCenter
            size: 64
            text: !root.svc.supported && root.voice.connected ? "block" : root.voice.authRequired ? "lock" : "forum"
            shape: MaterialShape.Shape.Cookie9Sided
            color: ClockStyle.colSurfaceHigh
            colSymbol: ClockStyle.colOnSurfaceVariant
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: ClockStyle.colOnBackground
            font.family: ClockStyle.fontTitle
            font.variableAxes: ClockStyle.axesTitle
            font.pixelSize: ClockStyle.textLarge
            text: !root.svc.supported && root.voice.connected ? Translation.tr("Chat needs the Rust helper")
                : root.voice.authRequired ? Translation.tr("Sign in first")
                : root.voice.connectionState === "connecting" || root.voice.connectionState === "starting" ? Translation.tr("Connecting to Discord")
                : Translation.tr("Not connected")
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.Wrap
            color: ClockStyle.colSubtext
            text: root.voice.authRequired ? Translation.tr("Open Discordo Voice and sign in; chat uses the same account.")
                : Translation.tr("Chat shares the connection of Discordo Voice.")
        }
        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            visible: !root.voice.connected && !root.voice.authRequired
            label: Translation.tr("Connect")
            onClicked: root.svc.connectIfNeeded()
        }
        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.voice.authRequired
            label: Translation.tr("Open Discordo Voice")
            onClicked: GlobalStates.openDiscordoVoiceApp()
        }
    }

    RowLayout {
        anchors.fill: parent
        visible: root.svc.supported && root.voice.connected
        spacing: ClockStyle.paneGap

        // ── Servers ─────────────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: 72
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            ListView {
                id: rail
                anchors { fill: parent; topMargin: 10; bottomMargin: 10 }
                spacing: 8
                clip: true
                model: [{ "id": "0", "name": Translation.tr("Direct messages"), "icon": "", "dm": true }].concat(root.voice.guilds)
                delegate: Item {
                    id: serverItem
                    required property var modelData
                    readonly property bool current: String(modelData.id) === (root.dmMode ? "0" : root.svc.guildId)
                    readonly property var badge: root.svc.guildBadge(modelData.id)
                    width: rail.width
                    height: 48

                    Rectangle {
                        anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                        width: 4
                        height: serverItem.current ? 28 : (serverItem.badge.unread ? 8 : 0)
                        radius: 2
                        color: ClockStyle.colOnSurface
                        Behavior on height { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }
                    }

                    Rectangle {
                        anchors.centerIn: parent
                        width: 46
                        height: 46
                        radius: serverItem.current ? 14 : 23
                        color: serverItem.modelData.dm ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
                        clip: true
                        Behavior on radius { NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve } }

                        MaterialSymbol {
                            visible: serverItem.modelData.dm === true
                            anchors.centerIn: parent
                            text: "forum"
                            iconSize: 24
                            color: ClockStyle.colOnPrimaryContainer
                        }
                        Image {
                            id: serverPicture
                            visible: false
                            anchors.fill: parent
                            asynchronous: true
                            source: serverItem.modelData.dm !== true ? String(serverItem.modelData.icon ?? "") : ""
                            sourceSize: Qt.size(96, 96)
                            fillMode: Image.PreserveAspectCrop
                        }
                        Item {
                            id: serverMask
                            anchors.fill: parent
                            visible: false
                            layer.enabled: true
                            Rectangle {
                                anchors.fill: parent
                                radius: parent.parent.radius
                            }
                        }
                        MultiEffect {
                            anchors.fill: parent
                            source: serverPicture
                            visible: serverPicture.status === Image.Ready
                            maskEnabled: true
                            maskSource: serverMask
                        }
                        StyledText {
                            visible: serverItem.modelData.dm !== true && String(serverItem.modelData.icon ?? "").length === 0
                            anchors.centerIn: parent
                            text: String(serverItem.modelData.name).split(/\s+/).map(w => w.charAt(0)).join("").slice(0, 3).toUpperCase()
                            color: ClockStyle.colOnSurfaceVariant
                            font.weight: Font.DemiBold
                        }
                    }

                    Rectangle {
                        visible: serverItem.badge.mentions > 0
                        anchors { right: parent.right; bottom: parent.bottom; rightMargin: 4; bottomMargin: 0 }
                        implicitWidth: Math.max(18, mentionText.implicitWidth + 8)
                        implicitHeight: 18
                        radius: 9
                        color: ClockStyle.colError
                        StyledText {
                            id: mentionText
                            anchors.centerIn: parent
                            text: serverItem.badge.mentions > 99 ? "99+" : String(serverItem.badge.mentions)
                            color: ClockStyle.colOnError
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.channelFilter = "";
                            root.svc.selectGuild(serverItem.modelData.id);
                        }
                    }
                    StyledToolTip {
                        text: String(serverItem.modelData.name)
                        extraVisibleCondition: false
                    }
                }
            }
        }

        // ── Channels or direct chats ─────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: root.compact ? 190 : 250
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    Layout.margins: 12
                    spacing: 8
                    StyledText {
                        Layout.fillWidth: true
                        text: root.dmMode ? Translation.tr("Direct messages") : root.guildName(root.svc.guildId)
                        color: ClockStyle.colOnSurface
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textLarge
                        elide: Text.ElideRight
                    }
                    ClockIconButton {
                        symbol: root.svc.keepConnected ? "notifications_active" : "notifications_off"
                        toggled: root.svc.keepConnected
                        size: 32
                        iconSize: 18
                        tooltip: root.svc.keepConnected ? Translation.tr("Notifications on: stays connected") : Translation.tr("Turn on notifications for DMs and mentions")
                        onClicked: root.svc.setNotices(!root.svc.keepConnected)
                    }
                }

                ListView {
                    id: channels
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.channelList
                    delegate: Item {
                        id: channelItem
                        required property var modelData
                        readonly property bool category: modelData.category === true
                        readonly property bool current: String(modelData.id) === root.svc.channelId
                        readonly property bool dim: modelData.muted === true && modelData.mentions === 0
                        width: channels.width
                        height: category ? 30 : 38

                        Rectangle {
                            visible: !channelItem.category
                            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 1; bottomMargin: 1 }
                            radius: height / 2
                            color: channelItem.current ? ClockStyle.colSecondaryContainer
                                : cmouse.containsMouse ? ClockStyle.colSurfaceHover : "transparent"
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: channelItem.category ? 14 : 18; rightMargin: 16 }
                            spacing: 8

                            MaterialSymbol {
                                visible: channelItem.category
                                text: "expand_more"
                                iconSize: 14
                                color: ClockStyle.colSubtext
                            }
                            DiscordoAvatar {
                                visible: root.dmMode
                                size: 26
                                source: root.dmMode ? String(channelItem.modelData.avatar ?? "") : ""
                                name: root.dmMode ? String(channelItem.modelData.name) : ""
                            }
                            MaterialSymbol {
                                visible: !root.dmMode && !channelItem.category
                                text: "tag"
                                iconSize: 18
                                color: channelItem.current ? ClockStyle.colOnSecondaryContainer : ClockStyle.colSubtext
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: String(channelItem.modelData.name)
                                elide: Text.ElideRight
                                color: channelItem.category ? ClockStyle.colSubtext
                                    : channelItem.current ? ClockStyle.colOnSecondaryContainer
                                    : channelItem.dim ? ClockStyle.colSubtext
                                    : (channelItem.modelData.unread ? ClockStyle.colOnSurface : ClockStyle.colOnSurfaceVariant)
                                font.weight: channelItem.modelData.unread || channelItem.category ? Font.DemiBold : Font.Normal
                                font.pixelSize: channelItem.category ? ClockStyle.textSmall : ClockStyle.textNormal
                                font.capitalization: channelItem.category ? Font.AllUppercase : Font.MixedCase
                            }
                            Rectangle {
                                visible: channelItem.modelData.mentions > 0
                                implicitWidth: Math.max(18, pillText.implicitWidth + 8)
                                implicitHeight: 18
                                radius: 9
                                color: ClockStyle.colError
                                StyledText {
                                    id: pillText
                                    anchors.centerIn: parent
                                    text: String(channelItem.modelData.mentions)
                                    color: ClockStyle.colOnError
                                    font.pixelSize: 10
                                    font.weight: Font.Bold
                                }
                            }
                            Rectangle {
                                visible: channelItem.modelData.unread === true && !(channelItem.modelData.mentions > 0) && !channelItem.dim
                                width: 8
                                height: 8
                                radius: 4
                                color: ClockStyle.colOnSurface
                            }
                        }

                        MouseArea {
                            id: cmouse
                            visible: !channelItem.category
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.svc.openChannel(channelItem.modelData.id, root.dmMode ? "0" : root.svc.guildId)
                        }
                    }
                }

                StyledText {
                    visible: channels.count === 0
                    Layout.fillWidth: true
                    Layout.margins: 16
                    wrapMode: Text.Wrap
                    color: ClockStyle.colSubtext
                    text: root.dmMode ? Translation.tr("No direct messages yet.")
                        : root.guildChannels[root.svc.guildId] === undefined ? Translation.tr("Loading channels…")
                        : Translation.tr("No channels you can read here.")
                }
            }
        }

        // ── The conversation ─────────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 56
                color: "transparent"

                RowLayout {
                    anchors { fill: parent; leftMargin: 16; rightMargin: 10 }
                    spacing: 6
                    StyledText {
                        Layout.fillWidth: true
                        text: root.channelTitle.length > 0 ? root.channelTitle : Translation.tr("Choose a channel")
                        color: ClockStyle.colOnBackground
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textLarge
                        elide: Text.ElideRight
                    }
                    ClockFormField {
                        id: searchField
                        visible: root.panel === "search"
                        Layout.preferredWidth: 220
                        implicitHeight: 40
                        symbol: "search"
                        placeholder: Translation.tr("Search this channel")
                        onAccepted: root.svc.search(text)
                        input.onAccepted: root.svc.search(text)
                    }
                    ClockIconButton {
                        symbol: "search"
                        toggled: root.panel === "search"
                        tooltip: Translation.tr("Search")
                        enabled: root.svc.channelId !== ""
                        onClicked: {
                            root.panel = root.panel === "search" ? "" : "search";
                            if (root.panel === "search")
                                searchField.focusInput();
                        }
                    }
                    ClockIconButton {
                        symbol: "keep"
                        toggled: root.panel === "pins"
                        tooltip: Translation.tr("Pinned messages")
                        enabled: root.svc.channelId !== ""
                        onClicked: {
                            root.panel = root.panel === "pins" ? "" : "pins";
                            if (root.panel === "pins")
                                root.svc.loadPins();
                        }
                    }
                    ClockIconButton {
                        symbol: "mark_chat_read"
                        tooltip: Translation.tr("Mark as read")
                        enabled: root.svc.channelId !== ""
                        onClicked: root.svc.markRead()
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    clip: true
                    model: root.svc.messageModel
                    boundsBehavior: Flickable.StopAtBounds
                    cacheBuffer: 2000
                    reuseItems: false
                    bottomMargin: 8
                    ScrollBar.vertical: ScrollBar {}

                    onContentYChanged: {
                        root.stuck = contentHeight - contentY - height < 60;
                        if (contentY < 120 && !root.olderPending && root.svc.hasMore && !root.svc.loadingHistory && root.svc.historyReady) {
                            root.olderPending = true;
                            root.olderHeight = contentHeight;
                            root.olderY = contentY;
                            root.svc.loadOlder();
                        }
                    }
                    onContentHeightChanged: if (root.stuck && !root.olderPending) Qt.callLater(() => list.positionViewAtEnd())

                    delegate: DiscordoMessage {
                        width: list.width
                        previous: index > 0 ? root.svc.messageModel.get(index - 1) : null
                        onReplyRequested: m => root.startReply(m)
                        onEditRequested: m => root.startEdit(m)
                        onJumpRequested: id => root.jumpTo(id)
                        onReactRequested: (id, anchor) => {
                            root.emojiMessage = id;
                            root.emojiOpen = true;
                        }
                    }
                }

                MaterialLoadingIndicator {
                    anchors.centerIn: parent
                    visible: root.svc.loadingHistory && root.svc.messageModel.count === 0
                    implicitSize: 56
                    color: ClockStyle.colPrimaryContainer
                    shapeColor: ClockStyle.colOnPrimaryContainer
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: !root.svc.loadingHistory && root.svc.historyReady && root.svc.messageModel.count === 0
                    text: Translation.tr("No messages here yet.")
                    color: ClockStyle.colSubtext
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: root.svc.channelId === ""
                    text: Translation.tr("Pick a channel or a conversation.")
                    color: ClockStyle.colSubtext
                }

                // Back to the newest messages
                ClockIconButton {
                    visible: !root.stuck && root.svc.messageModel.count > 0
                    anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                    symbol: "keyboard_double_arrow_down"
                    filled: true
                    colBackground: ClockStyle.colPrimaryContainer
                    colBackgroundHover: ClockStyle.colPrimaryContainerHover
                    colIcon: ClockStyle.colOnPrimaryContainer
                    onClicked: {
                        list.positionViewAtEnd();
                        root.stuck = true;
                        root.svc.markRead();
                    }
                }

                // Pins and search results
                Rectangle {
                    visible: root.panel !== ""
                    anchors { top: parent.top; right: parent.right; bottom: parent.bottom; margins: 10 }
                    width: Math.min(360, parent.width - 20)
                    radius: ClockStyle.radiusNormal
                    color: ClockStyle.colSheet
                    border.width: 1
                    border.color: ClockStyle.colOutline

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 6
                        StyledText {
                            text: root.panel === "pins" ? Translation.tr("Pinned messages") : Translation.tr("Search results")
                            color: ClockStyle.colOnSurface
                            font.weight: Font.DemiBold
                        }
                        ListView {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 6
                            model: root.panel === "pins" ? root.svc.pins : root.svc.searchResults
                            delegate: Rectangle {
                                id: hit
                                required property var modelData
                                width: ListView.view.width
                                implicitHeight: hitCol.implicitHeight + 16
                                radius: ClockStyle.radiusSmall
                                color: hitMouse.containsMouse ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh
                                ColumnLayout {
                                    id: hitCol
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 2
                                    StyledText {
                                        text: hit.modelData.author.name + "  ·  " + Md.formatTime(hit.modelData.timestamp)
                                        color: ClockStyle.colSubtext
                                        font.pixelSize: ClockStyle.textSmall
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: hit.modelData.content.length > 0 ? Md.plain(hit.modelData.content) : (hit.modelData.attachments.length > 0 ? Translation.tr("(attachment)") : "")
                                        color: ClockStyle.colOnSurface
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 5
                                        elide: Text.ElideRight
                                    }
                                }
                                MouseArea {
                                    id: hitMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.jumpTo(hit.modelData.id)
                                }
                            }
                        }
                        StyledText {
                            visible: (root.panel === "pins" ? root.svc.pins : root.svc.searchResults).length === 0
                            text: root.panel === "search" && root.svc.searching ? Translation.tr("Searching…") : Translation.tr("Nothing to show.")
                            color: ClockStyle.colSubtext
                        }
                    }
                }

                DiscordoEmojiPicker {
                    visible: root.emojiOpen
                    anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
                    onPicked: emoji => {
                        if (root.emojiMessage !== "")
                            root.svc.react(root.emojiMessage, emoji, true);
                        else
                            composer.insert(composer.cursorPosition, emoji);
                        root.emojiOpen = false;
                        root.emojiMessage = "";
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 18
                visible: root.svc.typingNames.length > 0
                text: root.svc.typingNames.length === 1 ? Translation.tr("%1 is typing…").arg(root.svc.typingNames[0])
                    : root.svc.typingNames.length < 4 ? Translation.tr("%1 are typing…").arg(root.svc.typingNames.join(", "))
                    : Translation.tr("Several people are typing…")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                visible: root.svc.errorMessage.length > 0
                implicitHeight: 30
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colErrorContainer
                StyledText {
                    anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                    verticalAlignment: Text.AlignVCenter
                    text: root.svc.errorMessage
                    color: ClockStyle.colOnErrorContainer
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }
            }

            // Replying / editing / files
            Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 12
                Layout.topMargin: 4
                visible: root.replyTarget !== null || root.editTarget !== null || root.attachments.length > 0
                implicitHeight: bar.implicitHeight + 10
                radius: ClockStyle.radiusSmall
                color: ClockStyle.colSurfaceHigh
                ColumnLayout {
                    id: bar
                    anchors { fill: parent; margins: 5; leftMargin: 10; rightMargin: 6 }
                    spacing: 2
                    RowLayout {
                        visible: root.replyTarget !== null || root.editTarget !== null
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            text: root.editTarget ? Translation.tr("Editing message") : Translation.tr("Replying to %1").arg(root.replyTarget ? root.replyTarget.author : "")
                            color: ClockStyle.colOnSurfaceVariant
                            font.pixelSize: ClockStyle.textSmall
                        }
                        ClockIconButton {
                            visible: root.replyTarget !== null
                            symbol: "alternate_email"
                            toggled: root.pingReply
                            size: 26
                            iconSize: 16
                            tooltip: root.pingReply ? Translation.tr("Pings them") : Translation.tr("Won't ping them")
                            onClicked: root.pingReply = !root.pingReply
                        }
                        ClockIconButton {
                            symbol: "close"
                            size: 26
                            iconSize: 16
                            onClicked: root.cancelCompose()
                        }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        visible: root.attachments.length > 0
                        Repeater {
                            model: root.attachments
                            delegate: Rectangle {
                                id: fileTag
                                required property string modelData
                                required property int index
                                implicitWidth: Math.min(220, tagRow.implicitWidth + 16)
                                implicitHeight: 26
                                radius: 13
                                color: ClockStyle.colPrimaryContainer
                                RowLayout {
                                    id: tagRow
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 4 }
                                    spacing: 4
                                    MaterialSymbol { text: "attach_file"; iconSize: 14; color: ClockStyle.colOnPrimaryContainer }
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: fileTag.modelData.split("/").pop()
                                        elide: Text.ElideMiddle
                                        color: ClockStyle.colOnPrimaryContainer
                                        font.pixelSize: ClockStyle.textSmall
                                    }
                                    ClockIconButton {
                                        symbol: "close"
                                        size: 22
                                        iconSize: 14
                                        colIcon: ClockStyle.colOnPrimaryContainer
                                        onClicked: root.attachments = root.attachments.filter((p, i) => i !== fileTag.index)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.margins: 12
                implicitHeight: Math.max(48, Math.min(160, composer.contentHeight + 22))
                radius: Math.min(height / 2, ClockStyle.radiusExtraLarge)
                color: ClockStyle.colField
                opacity: root.canSend ? 1 : 0.5

                DropArea {
                    anchors.fill: parent
                    onDropped: drop => { if (drop.hasUrls) root.addFiles(drop.urls); }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                    spacing: 2
                    ClockIconButton {
                        Layout.alignment: Qt.AlignBottom
                        symbol: "add_circle"
                        size: 36
                        tooltip: Translation.tr("Attach files")
                        enabled: root.canSend && root.svc.channelId !== ""
                        onClicked: picker.running = true
                    }
                    ScrollView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        TextArea {
                            id: composer
                            enabled: root.canSend && root.svc.channelId !== ""
                            placeholderText: !root.canSend ? Translation.tr("You can't send messages here")
                                : root.channelTitle.length > 0 ? Translation.tr("Message %1").arg(root.channelTitle) : ""
                            placeholderTextColor: ClockStyle.colSubtext
                            color: ClockStyle.colOnSurface
                            selectionColor: ClockStyle.colPrimary
                            selectedTextColor: ClockStyle.colOnPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: ClockStyle.textNormal
                            wrapMode: TextEdit.Wrap
                            background: null
                            verticalAlignment: TextEdit.AlignVCenter
                            topPadding: 12
                            bottomPadding: 10
                            leftPadding: 6

                            onTextChanged: if (text.length > 0 && !root.editTarget) root.svc.sendTyping()

                            Keys.onPressed: event => {
                                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                    root.submit();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Escape) {
                                    root.cancelCompose();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_Up && composer.text.length === 0) {
                                    root.editLast();
                                    event.accepted = true;
                                } else if (event.key === Qt.Key_V && (event.modifiers & Qt.ControlModifier)) {
                                    // an image on the clipboard goes as a file
                                    pasteImage.running = true;
                                }
                            }
                        }
                    }
                    ClockIconButton {
                        Layout.alignment: Qt.AlignBottom
                        symbol: "mood"
                        size: 36
                        tooltip: Translation.tr("Emoji")
                        enabled: root.canSend
                        onClicked: {
                            root.emojiMessage = "";
                            root.emojiOpen = !root.emojiOpen;
                        }
                    }
                    ClockIconButton {
                        Layout.alignment: Qt.AlignBottom
                        symbol: "send"
                        size: 36
                        filled: true
                        colIcon: ClockStyle.colPrimary
                        tooltip: Translation.tr("Send")
                        enabled: root.canSend && root.svc.channelId !== ""
                        onClicked: root.submit()
                    }
                }
            }
        }
        }
    }

    // wl-paste writes an image on the clipboard to a file, which is then attached; text pastes as usual
    Process {
        id: pasteImage
        command: ["bash", "-c", "t=$(wl-paste --list-types 2>/dev/null | grep -m1 '^image/') || exit 0; "
            + "ext=${t#image/}; f=\"${XDG_RUNTIME_DIR:-/tmp}/discordo-paste-$(date +%s%N).$ext\"; "
            + "wl-paste --type \"$t\" > \"$f\" && echo \"$f\""]
        stdout: StdioCollector {
            onStreamFinished: root.addFiles(text.split("\n").filter(s => s.length > 0))
        }
    }

    Keys.onEscapePressed: root.cancelCompose()
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.discordoVoice

/**
 * A Discord voice call.
 *
 * Contracted, it is only ever on screen for the join (see DiscordVoiceSource): the
 * channel's name and how many are in it. The rest of the call is a glance beside the
 * clock or in a bubble, drawn by the resting face and AuxiliaryBubbleContent; this file's
 * expanded face is that bubble's card - who is in the call, and Mute and Deafen.
 *
 * The activity facade routes the standalone Discordo helper and the legacy desktop
 * bridge without waking the latter for a standalone applet window.
 */
Item {
    id: root
    anchors.fill: parent

    property bool isExpanded: false

    readonly property color voiceColor: Appearance.colors.colPrimaryContainer
    /** Example data from the Settings preview (IslandPreviewStage); null on the island. */
    property var sample: null
    readonly property var channel: root.sample ? root.sample.channel : DiscordVoiceActivity.channel
    readonly property var participants: root.sample ? root.sample.participants : (DiscordVoiceActivity.participants ?? [])
    readonly property bool standaloneJoined: !root.sample && DiscordVoiceActivity.standaloneJoined
    readonly property bool muted: root.sample ? root.sample.muted === true : DiscordVoiceActivity.muted
    readonly property bool deafened: root.sample ? root.sample.deafened === true : DiscordVoiceActivity.deafened
    // Three rows when the speaker's video takes the room
    readonly property int maxRows: root.showPreview ? 3 : 5
    readonly property var shownRows: root.participants.slice(0, root.maxRows)
    readonly property int hiddenCount: Math.max(0, root.participants.length - root.maxRows)
    readonly property real cardMargin: 14
    readonly property real headerHeight: 40
    readonly property real headerGap: 10
    readonly property real rowHeight: 36
    readonly property real moreHeight: 20
    readonly property real listActionsGap: 12
    readonly property real controlHeight: 40
    readonly property real footerGap: 8
    readonly property real footerHeight: 34
    readonly property bool showFooter: !root.sample && root.standaloneJoined
    readonly property real preferredExpandedHeight: 2 * root.cardMargin + root.headerHeight
        + root.headerGap + (root.showPreview ? root.previewHeight + root.headerGap : 0) + root.shownRows.length * root.rowHeight
        + (root.hiddenCount > 0 ? root.moreHeight : 0) + root.listActionsGap
        + root.controlHeight + (root.showFooter ? root.footerGap + root.footerHeight : 0)

    readonly property string callStatus: root.sample ? Translation.tr("Preview")
        : DiscordVoiceActivity.connected ? Translation.tr("Connected") : Translation.tr("Voice call")

    // ── Video of whoever is talking ──────────────────────────────────────────
    // Only people with a camera on can be shown. The one talking now is; when nobody with a camera talks, the
    // last one stays (so the picture does not blink away between sentences), and with no camera on at all the
    // card is what it always was. Someone new takes over after the current person has been up for 1.5 s.
    readonly property var videoPeople: root.sample ? [] : root.participants.filter(person => person.self !== true && DiscordVoiceActivity.videoUrl(person) !== "")
    property string shownId: ""
    property double switchedAt: 0
    readonly property var shownPerson: root.videoPeople.find(person => String(person.id) === root.shownId) ?? null
    readonly property bool showPreview: root.shownPerson !== null
    readonly property real previewHeight: Math.round(((root.width > 0 ? root.width : 300) - 2 * root.cardMargin) * 9 / 16)

    function pickShown(): void {
        const people = root.videoPeople;
        if (people.length === 0) {
            root.shownId = "";
            return;
        }
        const current = people.find(person => String(person.id) === root.shownId);
        const talking = people.filter(person => person.speaking === true);
        let want = current ? String(current.id) : String(people[0].id);
        if (talking.length > 0 && !talking.some(person => String(person.id) === want))
            want = String(talking[0].id);
        if (want === root.shownId)
            return;
        if (!current || Date.now() - root.switchedAt >= 1500) {
            root.shownId = want;
            root.switchedAt = Date.now();
        } else {
            dwell.restart();
        }
    }

    onParticipantsChanged: root.pickShown()
    onVideoPeopleChanged: root.pickShown()
    Component.onCompleted: root.pickShown()

    Timer {
        id: dwell
        interval: 600
        onTriggered: root.pickShown()
    }

    function participantName(participant) {
        return String(participant?.nick ?? participant?.name ?? Translation.tr("Participant"));
    }

    function countText(count) {
        return count === 1 ? Translation.tr("1 in call") : Translation.tr("%1 in call").arg(count);
    }

    // ── Contracted: the join ─────────────────────────────────────────────────
    RowLayout {
        visible: !root.isExpanded
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 16
        spacing: 10

        Rectangle {
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: Math.max(22, Math.min(30, root.height - 10))
            implicitHeight: implicitWidth
            radius: width / 2
            color: root.voiceColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: "headset_mic"
                fill: 1
                iconSize: Math.round(parent.width * 0.58)
                color: Appearance.colors.colOnPrimaryContainer
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            text: Translation.tr("%1 · %2").arg(root.channel?.name ?? Translation.tr("Voice channel"))
                .arg(root.countText(root.participants.length))
            elide: Text.ElideRight
            maximumLineCount: 1
            font.family: Appearance.font.family.title
            font.pixelSize: Appearance.font.pixelSize.smaller
            font.weight: Font.Bold
            color: Appearance.colors.colOnLayer0
        }
    }

    // ── Expanded, in the bubble's card: who is here ──────────────────────────
    // One mask for every avatar in the list: they are all the same circle.
    Rectangle {
        id: avatarMask
        width: 26
        height: 26
        radius: 13
        visible: false
        layer.enabled: root.isExpanded
    }

    ColumnLayout {
        visible: root.isExpanded
        anchors.fill: parent
        anchors.margins: root.cardMargin
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.headerHeight
            spacing: 10

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: "headset_mic"
                fill: 1
                iconSize: 22
                color: Appearance.colors.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.channel?.name ?? Translation.tr("Voice channel")
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.family: Appearance.font.family.title
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.Bold
                    color: Appearance.colors.colOnLayer0
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.callStatus
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignVCenter
                text: root.countText(root.participants.length)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnSurfaceVariant
            }
        }

        Item {
            Layout.preferredHeight: root.headerGap
        }

        // The speaker's camera. Pressing it opens the call window. Plays only while the card is open.
        DiscordoVideoTile {
            visible: root.showPreview
            Layout.fillWidth: true
            Layout.preferredHeight: root.previewHeight
            name: root.shownPerson ? root.participantName(root.shownPerson) : ""
            avatarUrl: root.shownPerson ? DiscordVoiceActivity.avatarUrl(root.shownPerson, 128) : ""
            videoUrl: root.shownPerson ? DiscordVoiceActivity.videoUrl(root.shownPerson) : ""
            speaking: root.shownPerson?.speaking === true
            muted: root.shownPerson?.muted === true
            deafened: root.shownPerson?.deafened === true
            // The call window already plays these streams when it is open
            active: root.isExpanded && root.showPreview && !GlobalStates.discordoVoiceOpen
            onClicked: DiscordVoiceActivity.openApplet()
        }

        Item {
            visible: root.showPreview
            Layout.preferredHeight: root.headerGap
        }

        Repeater {
            model: root.shownRows

            RowLayout {
                id: row
                required property var modelData
                readonly property bool speaking: row.modelData?.speaking === true
                Layout.fillWidth: true
                Layout.preferredHeight: root.rowHeight
                spacing: 10

                // The avatar, in a ring that lights while they talk.
                Rectangle {
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 15
                    color: "transparent"
                    border.width: 2
                    border.color: row.speaking ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

                    Rectangle {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        radius: 13
                        color: Appearance.colors.colLayer2
                        visible: avatarImage.status !== Image.Ready

                        StyledText {
                            anchors.centerIn: parent
                            text: root.participantName(row.modelData).charAt(0).toUpperCase()
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnLayer2
                        }
                    }

                    Image {
                        id: avatarImage
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        source: DiscordVoiceActivity.avatarUrl(row.modelData, 64)
                        sourceSize: Qt.size(48, 48)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: false
                    }

                    MultiEffect {
                        anchors.fill: avatarImage
                        source: avatarImage
                        visible: avatarImage.status === Image.Ready
                        maskEnabled: true
                        maskSource: avatarMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Rectangle {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        width: 8
                        height: 8
                        radius: 4
                        visible: row.speaking
                        color: Appearance.colors.colPrimary
                        border.width: 2
                        border.color: Appearance.colors.colLayer1
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: root.participantName(row.modelData)
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: row.speaking ? Font.Bold : Font.DemiBold
                    color: Appearance.colors.colOnLayer0
                }

                MaterialSymbol {
                    Layout.alignment: Qt.AlignVCenter
                    visible: row.modelData?.deaf === true || row.modelData?.deafened === true
                        || row.modelData?.mute === true || row.modelData?.muted === true
                    text: row.modelData?.deaf === true || row.modelData?.deafened === true
                        ? "headset_off" : "mic_off"
                    iconSize: 16
                    color: Appearance.colors.colError
                }
            }
        }

        StyledText {
            visible: root.hiddenCount > 0
            Layout.preferredHeight: root.moreHeight
            text: Translation.tr("+%1 more").arg(root.hiddenCount)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }

        Item {
            Layout.preferredHeight: root.listActionsGap
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: root.controlHeight
            spacing: 8

            CallToggle {
                Layout.fillWidth: true
                enabled: !root.sample && !DiscordVoiceActivity.operationBusy
                primary: true
                glyph: root.muted ? "mic_off" : "mic"
                label: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
                engaged: root.muted
                onClicked: DiscordVoiceActivity.setMuted(!DiscordVoiceActivity.muted)
            }

            CallToggle {
                Layout.fillWidth: true
                enabled: !root.sample && !DiscordVoiceActivity.operationBusy
                primary: true
                glyph: root.deafened ? "headset_off" : "headphones"
                label: root.deafened ? Translation.tr("Undeafen") : Translation.tr("Deafen")
                engaged: root.deafened
                onClicked: DiscordVoiceActivity.setDeafened(!DiscordVoiceActivity.deafened)
            }
        }

        Item {
            visible: root.showFooter
            Layout.preferredHeight: root.footerGap
        }

        RowLayout {
            visible: root.showFooter
            Layout.fillWidth: true
            Layout.preferredHeight: root.footerHeight
            spacing: 8

            CallToggle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.footerHeight
                quiet: true
                glyph: "tune"
                label: Translation.tr("Channels")
                engaged: false
                Accessible.name: Translation.tr("Open Discordo Voice channels")
                onClicked: DiscordVoiceActivity.openChannels()
            }

            CallToggle {
                Layout.fillWidth: true
                Layout.preferredHeight: root.footerHeight
                quiet: true
                visible: root.showFooter
                glyph: "logout"
                label: Translation.tr("Leave")
                danger: true
                Accessible.name: Translation.tr("Leave voice channel")
                onClicked: DiscordVoiceActivity.leave()
            }
        }
    }

    /** A pill that turns red while its thing is switched off, like Discord's own. */
    component CallToggle: RippleButton {
        id: toggle
        property string glyph: ""
        property string label: ""
        property bool engaged: false
        property bool danger: false
        property bool primary: false
        property bool quiet: false
        readonly property color foreground: toggle.danger ? Appearance.colors.colError
            : toggle.engaged ? Appearance.colors.colOnErrorContainer
            : toggle.primary ? Appearance.colors.colOnPrimaryContainer
            : toggle.quiet ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colOnLayer2

        implicitHeight: toggle.quiet ? 34 : 40
        buttonRadius: Appearance.rounding.full
        scaleBehaviorEnabled: false
        colBackground: toggle.danger ? "transparent"
            : toggle.engaged ? Appearance.colors.colErrorContainer
            : toggle.primary ? Appearance.colors.colPrimaryContainer
            : toggle.quiet ? Appearance.colors.colLayer1 : Appearance.colors.colLayer2
        colBackgroundHover: toggle.danger ? Appearance.colors.colErrorContainerHover
            : toggle.engaged ? Appearance.colors.colErrorContainerHover
            : toggle.primary ? Appearance.colors.colPrimaryContainerHover
            : toggle.quiet ? Appearance.colors.colLayer1Hover
            : Appearance.colors.colLayer2Hover
        colRipple: toggle.danger ? Appearance.colors.colErrorContainerActive
            : toggle.engaged ? Appearance.colors.colErrorContainerActive
            : toggle.primary ? Appearance.colors.colPrimaryContainerActive
            : toggle.quiet ? Appearance.colors.colLayer1Active : Appearance.colors.colLayer2Active

        contentItem: Item {
            implicitWidth: toggleRow.implicitWidth
            implicitHeight: toggleRow.implicitHeight

            Row {
                id: toggleRow
                anchors.centerIn: parent
                spacing: 6

                MaterialSymbol {
                    anchors.verticalCenter: parent.verticalCenter
                    text: toggle.glyph
                    fill: 1
                    iconSize: 18
                    color: toggle.foreground
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: toggle.label
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: toggle.foreground
                }
            }
        }
    }
}

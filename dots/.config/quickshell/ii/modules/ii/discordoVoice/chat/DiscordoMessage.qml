pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.discordoVoice
import ".."
import "DiscordMarkdown.js" as Md

/** One message in the feed: header (or none when it continues the one above), text, files, embeds, reactions. */
Item {
    id: root

    required property var model
    required property int index
    /// The message above, for grouping and the day divider; null for the first
    property var previous: null

    signal replyRequested(var message)
    signal editRequested(var message)
    signal reactRequested(string messageId, Item anchor)
    signal jumpRequested(string messageId)

    readonly property var svc: DiscordoChatService
    readonly property bool hasReply: root.model.reply !== null && root.model.reply !== undefined
    readonly property bool system: Number(root.model.type) !== 0 && Number(root.model.type) !== 19
    readonly property bool newDay: root.previous === null || Md.dayLabel(root.previous.timestamp) !== Md.dayLabel(root.model.timestamp)
    readonly property bool grouped: !root.newDay && root.previous !== null && !root.hasReply && !root.system
        && Number(root.previous.type) === 0
        && String(root.previous.author.id) === String(root.model.author.id)
        && (Date.parse(root.model.timestamp) - Date.parse(root.previous.timestamp)) < 7 * 60000
    readonly property bool jumbo: Md.isJumbo(root.model.content)
    property bool revealSpoilers: false
    property bool hovered: hover.hovered || toolbarHover.hovered
    readonly property real textWidth: Math.max(120, width - 56 - 24)

    implicitHeight: column.implicitHeight + (grouped ? 1 : 6)

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4
        radius: ClockStyle.radiusSmall
        color: root.model.mentions_me ? Qt.rgba(ClockStyle.colTertiary.r, ClockStyle.colTertiary.g, ClockStyle.colTertiary.b, 0.12)
            : root.hovered ? ClockStyle.colSurfaceHover : "transparent"
        Rectangle {
            visible: root.model.mentions_me
            width: 3
            height: parent.height
            radius: 2
            color: ClockStyle.colTertiary
        }
    }

    HoverHandler {
        id: hover
    }

    ColumnLayout {
        id: column
        anchors { left: parent.left; right: parent.right; top: parent.top; leftMargin: 12; rightMargin: 12 }
        spacing: 2

        // The day
        RowLayout {
            visible: root.newDay
            Layout.fillWidth: true
            Layout.topMargin: 6
            Layout.bottomMargin: 6
            spacing: 10
            Rectangle { Layout.fillWidth: true; height: 1; color: ClockStyle.colOutline }
            StyledText {
                text: Md.dayLabel(root.model.timestamp)
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }
            Rectangle { Layout.fillWidth: true; height: 1; color: ClockStyle.colOutline }
        }

        // Who this answers
        RowLayout {
            visible: root.hasReply
            Layout.fillWidth: true
            Layout.leftMargin: 44
            spacing: 6
            MaterialSymbol {
                text: "subdirectory_arrow_right"
                iconSize: 16
                color: ClockStyle.colSubtext
            }
            StyledText {
                text: root.hasReply ? "@" + root.model.reply.author : ""
                color: ClockStyle.colOnSurfaceVariant
                font.pixelSize: ClockStyle.textSmall
                font.weight: Font.DemiBold
            }
            StyledText {
                Layout.fillWidth: true
                text: root.hasReply ? (root.model.reply.text.length > 0 ? Md.plain(root.model.reply.text) : Translation.tr("Original message")) : ""
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
            TapHandler {
                enabled: root.hasReply
                onTapped: root.jumpRequested(String(root.model.reply.id))
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            // Picture, or the time when this continues the message above
            Item {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 36
                Layout.preferredHeight: root.grouped ? 14 : 36
                DiscordoAvatar {
                    visible: !root.grouped
                    size: 36
                    source: String(root.model.author.avatar)
                    name: String(root.model.author.name)
                }
                StyledText {
                    visible: root.grouped && root.hovered
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Md.formatTime(root.model.timestamp).slice(-5)
                    color: ClockStyle.colSubtext
                    font.pixelSize: 10
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: 3

                RowLayout {
                    visible: !root.grouped
                    spacing: 8
                    StyledText {
                        text: String(root.model.author.name)
                        color: root.model.mine ? ClockStyle.colPrimary : ClockStyle.colOnSurface
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        visible: root.model.author.bot === true
                        radius: 4
                        color: ClockStyle.colPrimaryContainer
                        implicitWidth: botText.implicitWidth + 8
                        implicitHeight: botText.implicitHeight + 2
                        StyledText {
                            id: botText
                            anchors.centerIn: parent
                            text: "APP"
                            color: ClockStyle.colOnPrimaryContainer
                            font.pixelSize: 10
                            font.weight: Font.Bold
                        }
                    }
                    StyledText {
                        text: Md.formatTime(root.model.timestamp)
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                    MaterialSymbol {
                        visible: root.model.pinned === true
                        text: "keep"
                        iconSize: 14
                        color: ClockStyle.colSubtext
                    }
                }

                StyledText {
                    visible: root.system
                    Layout.fillWidth: true
                    text: Translation.tr("System message")
                    color: ClockStyle.colSubtext
                    font.italic: true
                }

                StyledText {
                    id: body
                    visible: !root.system && String(root.model.content).length > 0
                    Layout.fillWidth: true
                    textFormat: Text.RichText
                    wrapMode: Text.Wrap
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textNormal + (root.jumbo ? 0 : 0)
                    lineHeight: 1.1
                    text: Md.render(root.model.content, {
                        "link": String(ClockStyle.colPrimary), "mention": String(ClockStyle.colPrimary), "channel": String(ClockStyle.colPrimary),
                        "codeBg": String(ClockStyle.colSurfaceHighest), "quote": String(ClockStyle.colSubtext),
                        "spoilerBg": String(ClockStyle.colSurfaceHighest), "reveal": root.revealSpoilers
                    }) + (root.model.edited ? ' <span style="color:' + ClockStyle.colSubtext + '; font-size:small;">(' + Translation.tr("edited") + ")</span>" : "")
                    onLinkActivated: link => Qt.openUrlExternally(link)
                    TapHandler {
                        onTapped: root.revealSpoilers = !root.revealSpoilers
                    }
                }

                // Pictures and files
                Repeater {
                    model: root.model.attachments ?? []
                    delegate: Item {
                        id: att
                        required property var modelData
                        readonly property bool image: String(modelData.type).indexOf("image/") === 0
                        readonly property bool hidden: modelData.spoiler === true && !root.revealSpoilers
                        readonly property real ratio: modelData.width > 0 ? modelData.height / modelData.width : 0.6
                        readonly property real frameWidth: Math.min(root.textWidth, 420, Math.max(120, modelData.width))
                        implicitWidth: image ? frameWidth : Math.min(root.textWidth, 340)
                        implicitHeight: image ? Math.min(frameWidth * ratio, 320) : 48

                        Rectangle {
                            id: frame
                            visible: att.image
                            anchors.fill: parent
                            radius: ClockStyle.radiusLarge
                            color: ClockStyle.colSurfaceHigh
                            Image {
                                id: shot
                                visible: false
                                anchors.fill: parent
                                asynchronous: true
                                fillMode: Image.PreserveAspectCrop
                                source: att.image ? String(att.modelData.proxy || att.modelData.url)
                                    + (String(att.modelData.proxy).indexOf("?") >= 0 ? "&" : "?")
                                    + "width=" + Math.round(att.frameWidth * 2) + "&height=" + Math.round(att.implicitHeight * 2) : ""
                                sourceSize: Qt.size(att.frameWidth * 2, att.implicitHeight * 2)
                            }
                            Item {
                                id: shotMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: frame.radius
                                }
                            }
                            MultiEffect {
                                anchors.fill: parent
                                source: shot
                                visible: shot.status === Image.Ready && !att.hidden
                                maskEnabled: true
                                maskSource: shotMask
                            }
                            Rectangle {
                                anchors.fill: parent
                                visible: att.hidden
                                radius: frame.radius
                                color: ClockStyle.colSurfaceHighest
                                StyledText {
                                    anchors.centerIn: parent
                                    text: Translation.tr("Spoiler - click to reveal")
                                    color: ClockStyle.colSubtext
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: att.hidden ? root.revealSpoilers = true : Qt.openUrlExternally(String(att.modelData.url))
                            }
                        }

                        Rectangle {
                            visible: !att.image
                            anchors.fill: parent
                            radius: ClockStyle.radiusSmall
                            color: ClockStyle.colSurfaceHigh
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10
                                MaterialSymbol {
                                    text: String(att.modelData.type).indexOf("video/") === 0 ? "movie"
                                        : String(att.modelData.type).indexOf("audio/") === 0 ? "audio_file" : "draft"
                                    iconSize: 24
                                    color: ClockStyle.colPrimary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        text: String(att.modelData.name)
                                        color: ClockStyle.colPrimary
                                        elide: Text.ElideMiddle
                                    }
                                    StyledText {
                                        text: Md.humanSize(Number(att.modelData.size))
                                        color: ClockStyle.colSubtext
                                        font.pixelSize: ClockStyle.textSmall
                                    }
                                }
                                MaterialSymbol {
                                    text: "download"
                                    iconSize: 20
                                    color: ClockStyle.colOnSurfaceVariant
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Qt.openUrlExternally(String(att.modelData.url))
                            }
                        }
                    }
                }

                Repeater {
                    model: root.model.embeds ?? []
                    delegate: DiscordoEmbed {
                        required property var modelData
                        embed: modelData
                        maxWidth: Math.min(root.textWidth, 440)
                    }
                }

                Repeater {
                    model: root.model.stickers ?? []
                    delegate: Image {
                        required property var modelData
                        source: String(modelData.url)
                        width: 140
                        height: 140
                        sourceSize: Qt.size(280, 280)
                        asynchronous: true
                        fillMode: Image.PreserveAspectFit
                    }
                }

                Flow {
                    visible: (root.model.reactions ?? []).length > 0
                    Layout.fillWidth: true
                    spacing: 4
                    Repeater {
                        model: root.model.reactions ?? []
                        delegate: Rectangle {
                            id: chip
                            required property var modelData
                            implicitWidth: row.implicitWidth + 14
                            implicitHeight: 24
                            radius: 8
                            color: modelData.me ? ClockStyle.colPrimaryContainer : ClockStyle.colSurfaceHigh
                            border.width: modelData.me ? 1 : 0
                            border.color: ClockStyle.colPrimary
                            RowLayout {
                                id: row
                                anchors.centerIn: parent
                                spacing: 5
                                Image {
                                    visible: String(chip.modelData.emoji.url).length > 0
                                    Layout.preferredWidth: 16
                                    Layout.preferredHeight: 16
                                    source: String(chip.modelData.emoji.url)
                                    sourceSize: Qt.size(32, 32)
                                    asynchronous: true
                                }
                                StyledText {
                                    visible: String(chip.modelData.emoji.url).length === 0
                                    text: String(chip.modelData.emoji.name)
                                    font.pixelSize: 14
                                }
                                StyledText {
                                    text: String(chip.modelData.count)
                                    color: chip.modelData.me ? ClockStyle.colOnPrimaryContainer : ClockStyle.colOnSurfaceVariant
                                    font.pixelSize: ClockStyle.textSmall
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.svc.react(root.model.id, root.svc.reactionKey(chip.modelData.emoji), !chip.modelData.me)
                            }
                        }
                    }
                }
            }
        }
    }

    // Quick actions, over the top right corner while the pointer is on the message
    Rectangle {
        id: toolbar
        visible: root.hovered && !root.system
        anchors { right: parent.right; top: parent.top; rightMargin: 14; topMargin: root.newDay ? 28 : -6 }
        radius: ClockStyle.radiusNormal
        color: ClockStyle.colSheet
        border.width: 1
        border.color: ClockStyle.colOutline
        implicitWidth: tools.implicitWidth + 8
        implicitHeight: 30
        z: 5
        HoverHandler {
            id: toolbarHover
        }
        RowLayout {
            id: tools
            anchors.centerIn: parent
            spacing: 0
            ClockIconButton {
                symbol: "add_reaction"
                size: 28
                iconSize: 18
                tooltip: Translation.tr("React")
                onClicked: root.reactRequested(String(root.model.id), toolbar)
            }
            ClockIconButton {
                symbol: "reply"
                size: 28
                iconSize: 18
                tooltip: Translation.tr("Reply")
                onClicked: root.replyRequested(root.model)
            }
            ClockIconButton {
                visible: root.model.mine === true
                symbol: "edit"
                size: 28
                iconSize: 18
                tooltip: Translation.tr("Edit")
                onClicked: root.editRequested(root.model)
            }
            ClockIconButton {
                symbol: "content_copy"
                size: 28
                iconSize: 18
                tooltip: Translation.tr("Copy text")
                onClicked: Quickshell.clipboardText = Md.plain(root.model.content)
            }
            ClockIconButton {
                visible: root.model.mine === true
                symbol: "delete"
                size: 28
                iconSize: 18
                tooltip: Translation.tr("Delete")
                onClicked: root.svc.deleteMessage(root.model.id)
            }
        }
    }
}

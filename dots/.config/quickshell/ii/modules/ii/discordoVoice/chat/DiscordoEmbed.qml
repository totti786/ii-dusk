pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "DiscordMarkdown.js" as Md

/** A link or bot embed: coloured bar, provider and author, title, text, fields, picture, footer. */
Rectangle {
    id: root

    required property var embed
    property real maxWidth: 420

    readonly property color bar: root.embed.color > 0 ? Qt.color("#" + Number(root.embed.color).toString(16).padStart(6, "0")) : ClockStyle.colOutline
    readonly property string picture: String(root.embed.image || "")
    readonly property string thumb: String(root.embed.thumbnail || "")
    readonly property bool videoOnly: String(root.embed.kind) === "gifv" || String(root.embed.kind) === "image"

    // A bare image or gif link is just the picture, without a card
    color: root.videoOnly ? "transparent" : ClockStyle.colSurfaceHigh
    radius: ClockStyle.radiusSmall
    implicitWidth: root.videoOnly ? Math.min(root.maxWidth, 360) : root.maxWidth
    implicitHeight: root.videoOnly ? soloImage.implicitHeight : card.implicitHeight + 16

    Rectangle {
        visible: !root.videoOnly
        width: 4
        height: parent.height
        radius: 2
        color: root.bar
    }

    Image {
        id: soloImage
        visible: root.videoOnly
        width: parent.width
        asynchronous: true
        fillMode: Image.PreserveAspectFit
        source: root.videoOnly ? (root.picture || root.thumb || String(root.embed.url || "")) : ""
        height: status === Image.Ready ? Math.min(width * (sourceSize.height / Math.max(1, sourceSize.width)), 300) : 0
    }

    ColumnLayout {
        id: card
        visible: !root.videoOnly
        x: 14
        y: 8
        width: parent.width - 24
        spacing: 4

        StyledText {
            visible: text.length > 0
            Layout.fillWidth: true
            text: String(root.embed.provider || "")
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            elide: Text.ElideRight
        }
        StyledText {
            visible: text.length > 0
            Layout.fillWidth: true
            text: String(root.embed.author || "")
            color: ClockStyle.colOnSurface
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
        StyledText {
            visible: text.length > 0
            Layout.fillWidth: true
            textFormat: Text.StyledText
            text: String(root.embed.url || "").length > 0
                ? '<a href="' + root.embed.url + '" style="color:' + ClockStyle.colPrimary + '">' + Md.plain(root.embed.title).replace(/</g, "&lt;") + "</a>"
                : Md.plain(root.embed.title).replace(/</g, "&lt;")
            onLinkActivated: link => Qt.openUrlExternally(link)
            color: ClockStyle.colOnSurface
            font.weight: Font.DemiBold
            wrapMode: Text.Wrap
        }
        StyledText {
            visible: text.length > 0
            Layout.fillWidth: true
            textFormat: Text.RichText
            text: Md.render(root.embed.description, { "link": ClockStyle.colPrimary, "codeBg": ClockStyle.colSurfaceHighest })
            onLinkActivated: link => Qt.openUrlExternally(link)
            color: ClockStyle.colOnSurfaceVariant
            font.pixelSize: ClockStyle.textSmall
            wrapMode: Text.Wrap
        }
        Flow {
            Layout.fillWidth: true
            spacing: 12
            visible: root.embed.fields && root.embed.fields.length > 0
            Repeater {
                model: root.embed.fields ?? []
                ColumnLayout {
                    id: field
                    required property var modelData
                    width: modelData.inline ? Math.floor((card.width - 24) / 3) : card.width
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: field.modelData.name
                        color: ClockStyle.colOnSurface
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.DemiBold
                        wrapMode: Text.Wrap
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: field.modelData.value
                        color: ClockStyle.colOnSurfaceVariant
                        font.pixelSize: ClockStyle.textSmall
                        wrapMode: Text.Wrap
                    }
                }
            }
        }
        Image {
            visible: root.picture.length > 0 && status !== Image.Error
            Layout.fillWidth: true
            Layout.preferredHeight: status === Image.Ready ? Math.min(width * (sourceSize.height / Math.max(1, sourceSize.width)), 260) : 0
            asynchronous: true
            fillMode: Image.PreserveAspectFit
            horizontalAlignment: Image.AlignLeft
            source: root.picture
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Qt.openUrlExternally(root.picture)
            }
        }
        StyledText {
            visible: text.length > 0
            Layout.fillWidth: true
            text: String(root.embed.footer || "")
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            elide: Text.ElideRight
        }
    }

    Image {
        visible: !root.videoOnly && root.thumb.length > 0 && root.picture.length === 0 && status !== Image.Error
        anchors { top: parent.top; right: parent.right; margins: 8 }
        width: 64
        height: 64
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        source: root.thumb
    }
}

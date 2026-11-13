pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "SyncplayFormat.js" as Fmt

/**
 * Chat and what the room says about itself (joins, leaves, who loaded what). The session
 * keeps recent lines, so opening the window later shows what happened while it was closed.
 */
SyncplayPane {
    id: root

    title: Translation.tr("Chat")

    function send(): void {
        const t = input.text.trim();
        if (t.length === 0)
            return;
        SyncplayService.chat(t);
        input.text = "";
    }

    StyledText {
        visible: SyncplayService.motd.length > 0
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        text: SyncplayService.motd
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    ListView {
        id: log
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: SyncplayService.messages

        // Stay at the newest line unless the reader scrolled up to look at older ones
        property bool pinned: true
        onMovementEnded: log.pinned = log.atYEnd
        Connections {
            target: SyncplayService
            function onMessageSerialChanged() {
                if (log.pinned)
                    Qt.callLater(() => log.positionViewAtEnd());
            }
        }
        Component.onCompleted: Qt.callLater(() => log.positionViewAtEnd())

        delegate: ColumnLayout {
            id: line
            required property var modelData
            readonly property bool chat: modelData.kind === "chat"
            width: log.width
            spacing: 0

            RowLayout {
                visible: line.chat
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    text: line.modelData.user ?? ""
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Bold
                    color: line.modelData.user === SyncplayService.name ? ClockStyle.colPrimary : ClockStyle.colTertiary
                }

                StyledText {
                    text: Fmt.clock(line.modelData.t)
                    font.pixelSize: ClockStyle.textSmall - 1
                    color: ClockStyle.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: line.modelData.text ?? ""
                font.pixelSize: ClockStyle.textNormal
                font.italic: !line.chat
                color: line.modelData.kind === "error" ? ClockStyle.colError
                    : line.chat ? ClockStyle.colOnSurface : ClockStyle.colSubtext
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gapSmall

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: ClockStyle.radiusFull
            color: input.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

            StyledTextInput {
                id: input
                anchors {
                    fill: parent
                    leftMargin: ClockStyle.gapLarge
                    rightMargin: ClockStyle.gapLarge
                }
                verticalAlignment: TextInput.AlignVCenter
                clip: true
                font.pixelSize: ClockStyle.textNormal
                color: ClockStyle.colOnSurface
                onAccepted: root.send()

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: input.text.length === 0
                    text: Translation.tr("Message the room")
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colSubtext
                }
            }
        }

        ClockIconButton {
            focusPolicy: Qt.NoFocus
            symbol: "send"
            filled: true
            toggled: input.text.trim().length > 0
            tooltip: Translation.tr("Send")
            onClicked: root.send()
        }
    }
}

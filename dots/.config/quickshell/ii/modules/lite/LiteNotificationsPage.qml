import QtQuick
import QtQuick.Layouts
import Quickshell

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The notification history for the Lite quick settings: newest first, each with its app,
 * age, summary and a couple of lines of body, a dismiss button, and Clear all underneath.
 * The switch in the header is do-not-disturb. It reads the shell's own Notifications list, so
 * it shows exactly what the full sidebar would.
 */
ColumnLayout {
    id: root

    signal back()

    spacing: 10

    readonly property var items: (Notifications.list ?? [])
        .filter(n => n && (String(n.summary || "").trim() !== "" || String(n.body || "").trim() !== ""))
        .slice().reverse()

    function age(time: real): string {
        const mins = Math.floor((Date.now() - time) / 60000);
        if (mins < 1)
            return Translation.tr("now");
        if (mins < 60)
            return Translation.tr("%1 min").arg(mins);
        const hours = Math.floor(mins / 60);
        if (hours < 24)
            return Translation.tr("%1 h").arg(hours);
        return Translation.tr("%1 d").arg(Math.floor(hours / 24));
    }

    Component.onCompleted: Notifications.markAllRead()

    LitePageHeader {
        Layout.fillWidth: true
        title: Translation.tr("Notifications")
        subtitle: Notifications.effectiveSilent ? Translation.tr("Do not disturb")
            : root.items.length === 0 ? "" : Translation.tr("%1 total").arg(root.items.length)
        checked: !Notifications.effectiveSilent
        onBack: root.back()
        onSwitched: Notifications.silent = !Notifications.effectiveSilent
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: 24
        Layout.bottomMargin: 24
        visible: list.count === 0
        horizontalAlignment: Text.AlignHCenter
        color: Appearance.colors.colSubtext
        text: Translation.tr("No notifications")
    }

    ListView {
        WheelScroll {}
        id: list
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(contentHeight, 360)
        visible: count > 0
        clip: true
        spacing: 6
        boundsBehavior: Flickable.StopAtBounds
        model: root.items

        delegate: Rectangle {
            id: card
            required property var modelData
            width: ListView.view.width
            implicitHeight: col.implicitHeight + 20
            radius: 16
            color: Appearance.colors.colLayer1

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                anchors.rightMargin: 40
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: [card.modelData.appName, root.age(card.modelData.time)].filter(s => s !== "").join(" · ")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.modelData.summary
                    color: Appearance.colors.colOnLayer0
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: card.modelData.body
                    color: Appearance.colors.colOnLayer1
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    maximumLineCount: 3
                    wrapMode: Text.Wrap
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6
                width: 28
                height: 28
                radius: 14
                color: closeArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    iconSize: 16
                    color: Appearance.colors.colSubtext
                }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Notifications.discardNotification(card.modelData.notificationId)
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.items.length > 0
        Item { Layout.fillWidth: true }
        LiteActionButton {
            text: Translation.tr("Clear all")
            onClicked: Notifications.discardAllNotifications()
        }
    }
}

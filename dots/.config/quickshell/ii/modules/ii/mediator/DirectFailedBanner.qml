pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Shown when a direct stream could not be played and a torrent is available instead. Nothing
 * switches on its own: the user picks the torrent or leaves it.
 */
RoundedBox {
    id: root

    readonly property var failure: MediatorService.directFailed
    readonly property string title: String(root.failure?.payload?.title ?? "")

    visible: root.failure !== null
    implicitHeight: visible ? column.implicitHeight + 24 : 0
    radius: Appearance.rounding.large
    color: Appearance.colors.colErrorContainer

    ColumnLayout {
        id: column
        anchors { fill: parent; leftMargin: 16; rightMargin: 12; topMargin: 12; bottomMargin: 12 }
        spacing: 8

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.title !== "" ? Translation.tr("The direct stream for %1 isn't working").arg(root.title)
                : Translation.tr("The direct stream isn't working")
            color: Appearance.colors.colOnErrorContainer
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: Translation.tr("%1 A torrent starts slower but usually plays.").arg(String(root.failure?.reason ?? ""))
            color: Appearance.colors.colOnErrorContainer
            opacity: 0.85
            font.pixelSize: Appearance.font.pixelSize.small
        }

        RowLayout {
            Layout.alignment: Qt.AlignRight
            spacing: 4

            DialogButton {
                buttonText: Translation.tr("Not now")
                colEnabled: Appearance.colors.colOnErrorContainer
                onClicked: MediatorService.dismissDirectFailed()
            }
            DialogButton {
                buttonText: Translation.tr("Play torrent")
                colEnabled: Appearance.colors.colOnErrorContainer
                onClicked: MediatorService.useTorrentInstead()
            }
        }
    }
}

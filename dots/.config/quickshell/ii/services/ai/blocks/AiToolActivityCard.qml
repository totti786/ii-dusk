import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/**
 * One thing an OpenCode chat did through the shell's tools: what it looked at or changed, and how it went.
 * Nothing to answer; it is here so a call that ran without asking is still seen.
 */
Rectangle {
    id: root

    property var messageData: null
    property var card: null

    readonly property var info: root.card?.data ?? ({})
    readonly property bool busy: String(root.card?.state ?? "") === "running"
    readonly property bool ok: root.info.ok !== false

    implicitHeight: column.implicitHeight + 16
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        spacing: 2

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                text: root.busy ? "pending" : root.ok ? String(root.info.icon ?? "build") : "error"
                iconSize: Appearance.font.pixelSize.normal
                color: root.ok || root.busy ? Appearance.colors.colOnLayer2 : Appearance.m3colors.m3error
            }

            StyledText {
                Layout.fillWidth: true
                text: String(root.card?.summary ?? "")
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text.length > 0 && !root.busy
            text: String(root.info.detail ?? "")
            wrapMode: Text.WrapAnywhere
            maximumLineCount: 8
            elide: Text.ElideRight
            font.family: Appearance.font.family.monospace
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services

/**
 * Asks before one of the shell's own tools runs for an OpenCode chat. The request is
 * held by OpenCode until this card answers, so nothing runs before the user allows it.
 */
Rectangle {
    id: root

    property var messageData: null
    property var card: null
    readonly property string tool: String(root.card?.data?.tool ?? "")
    readonly property var input: root.card?.data?.input ?? ({})
    readonly property bool isCommand: root.tool === "run_shell_command" || root.tool === "run_privileged_command"
    readonly property var presentation: ({
        "run_shell_command": { "icon": "terminal", "title": Translation.tr("Run this command?") },
        "run_privileged_command": { "icon": "admin_panel_settings", "title": Translation.tr("Run this system command?") },
        "write_file": { "icon": "edit_document", "title": Translation.tr("Edit this file?") },
        "undo_change": { "icon": "undo", "title": Translation.tr("Undo this change?") },
        "settings_set": { "icon": "tune", "title": Translation.tr("Change these settings?") },
        "brightness_set": { "icon": "brightness_6", "title": Translation.tr("Change brightness?") }
    })
    readonly property var shown: root.presentation[root.tool] ?? ({ "icon": "build", "title": Translation.tr("Allow %1?").arg(root.tool) })
    /** What the call will do, in the words the card prints under its title. */
    readonly property string detail: {
        if (root.isCommand)
            return String(root.input.command ?? "");
        if (root.tool === "write_file") {
            const content = String(root.input.content ?? "");
            return String(root.input.path ?? "") + "\n\n" + (content.length > 700 ? content.slice(0, 700) + "\n…" : content);
        }
        if (root.tool === "undo_change")
            return Translation.tr("Change %1").arg(String(root.input.id ?? ""));
        if (root.tool === "settings_set")
            return Array.from(root.input.changes ?? []).map(change => `${change.key} = ${JSON.stringify(change.value)}`).join("\n");
        if (root.tool === "brightness_set")
            return Translation.tr("Brightness to %1%").arg(String(root.input.percent ?? ""));
        return JSON.stringify(root.input);
    }
    readonly property string reason: String(root.input.reason ?? "")

    implicitHeight: content.implicitHeight + Appearance.rounding.normal
    radius: Appearance.rounding.normal
    color: Appearance.colors.colSecondaryContainer

    ColumnLayout {
        id: content
        anchors.fill: parent
        anchors.margins: Appearance.rounding.unsharpenmore
        spacing: Appearance.rounding.unsharpenmore

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: root.shown.icon
                iconSize: Appearance.font.pixelSize.larger
                color: Appearance.m3colors.m3onSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: root.shown.title
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.DemiBold
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.reason.length > 0
                    text: root.reason
                    wrapMode: Text.Wrap
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.detail
                    wrapMode: Text.WrapAnywhere
                    font.family: root.tool === "brightness_set" || root.tool === "undo_change" ? Appearance.font.family.main : Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.rounding.unsharpenmore

            Item { Layout.fillWidth: true }

            RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: ColorUtils.transparentize(Appearance.colors.colLayer2, 1)
                colBackgroundHover: Appearance.colors.colLayer2Hover
                colRipple: Appearance.colors.colLayer2Active
                onClicked: Ai.rejectShellTool(root.messageData, String(root.card?.callId ?? ""))
                contentItem: StyledText {
                    text: Translation.tr("Deny")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onSecondaryContainer
                }
            }

            RippleButton {
                leftPadding: Appearance.rounding.small
                rightPadding: Appearance.rounding.small
                topPadding: Appearance.rounding.unsharpenmore / 2
                bottomPadding: Appearance.rounding.unsharpenmore / 2
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                onClicked: Ai.approveShellTool(root.messageData, String(root.card?.callId ?? ""))
                contentItem: StyledText {
                    text: Translation.tr("Allow once")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.m3colors.m3onPrimary
                }
            }
        }
    }
}

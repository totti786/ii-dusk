pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

// Compatibility name for existing hosts; this page now manages signed-in agents.
Item {
    id: root
    signal closed
    implicitHeight: content.implicitHeight
    function connection(id) { return Array.from(Ai.agentBackends ?? []).find(item => item.id === id) ?? null; }
    Component.onCompleted: Ai.refreshOpencodeModels()
    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.rounding.normal
        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Use the accounts already signed into Codex, Claude Code or OpenCode. QuickShell does not need API keys.")
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
        }
        Repeater {
            model: [
                {id: "codex", name: "Codex", command: "codex login", description: "ChatGPT sign-in"},
                {id: "claude", name: "Claude Code", command: "claude auth login", description: "Claude subscription sign-in"},
                {id: "opencode", name: "OpenCode", command: "opencode auth login", description: "Existing OpenCode providers"}
            ]
            delegate: Rectangle {
                id: card
                required property var modelData
                readonly property var connection: root.connection(modelData.id)
                Layout.fillWidth: true
                implicitHeight: details.implicitHeight + Appearance.rounding.normal * 2
                radius: Appearance.rounding.normal
                color: Appearance.colors.colLayer1
                ColumnLayout {
                    id: details
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: Appearance.rounding.normal
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { text: card.modelData.name; font.weight: Font.DemiBold; color: Appearance.colors.colOnLayer1 }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            text: !card.connection ? Translation.tr("Checking…")
                                : !card.connection.installed ? Translation.tr("Not installed")
                                : card.connection.signedIn ? Translation.tr("Ready") : Translation.tr("Sign in required")
                            color: card.connection?.signedIn ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                        }
                    }
                    StyledText { text: card.modelData.description; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
                    RippleButton {
                        Layout.fillWidth: true
                        implicitHeight: 38
                        buttonRadius: Appearance.rounding.small
                        buttonText: card.modelData.command
                        onClicked: AiOutputController.copyText(card.modelData.command)
                        StyledToolTip { text: Translation.tr("Copy sign-in command, then run it in a terminal") }
                    }
                }
            }
        }
        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 40
            buttonRadius: Appearance.rounding.full
            buttonText: Translation.tr("Refresh connection status")
            onClicked: Ai.refreshOpencodeModels()
        }
    }
}

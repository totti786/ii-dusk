pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets

/**
 * Sign-in status for the agent CLIs (Codex, Claude Code, OpenCode). They keep their
 * own credentials, so there is nothing to type here: each card says whether the CLI
 * is installed and signed in, and copies the command that signs it in.
 */
Item {
    id: root

    readonly property var agents: [
        {id: "codex", name: "Codex", description: Translation.tr("ChatGPT sign-in"), command: "codex login"},
        {id: "claude", name: "Claude Code", description: Translation.tr("Claude subscription sign-in"), command: "claude auth login"},
        {id: "opencode", name: "OpenCode", description: Translation.tr("Existing OpenCode providers"), command: "opencode auth login"}
    ]

    implicitHeight: content.implicitHeight

    function connection(id: string): var {
        return Array.from(Ai.agentBackends ?? []).find(item => item.id === id) ?? null;
    }

    Component.onCompleted: Ai.refreshOpencodeModels()

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Signed-in agents")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }

            RippleButton {
                implicitHeight: 28
                implicitWidth: refreshLabel.implicitWidth + 24
                buttonRadius: Appearance.rounding.full
                onClicked: Ai.refreshOpencodeModels()

                contentItem: StyledText {
                    id: refreshLabel
                    horizontalAlignment: Text.AlignHCenter
                    text: Translation.tr("Refresh")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                }
            }
        }

        Repeater {
            model: root.agents

            delegate: Rectangle {
                id: card

                required property var modelData
                readonly property var connection: root.connection(modelData.id)
                readonly property bool ready: connection?.installed === true && connection?.signedIn === true
                readonly property string statusText: !connection ? Translation.tr("Checking…")
                    : !connection.installed ? Translation.tr("Not installed")
                    : connection.signedIn ? Translation.tr("Ready") : Translation.tr("Sign in required")

                Layout.fillWidth: true
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                implicitHeight: nameColumn.implicitHeight + 12 * 2

                ColumnLayout {
                    id: nameColumn
                    anchors {
                        left: parent.left
                        right: statusCell.left
                        verticalCenter: parent.verticalCenter
                        leftMargin: 12
                        rightMargin: 8
                    }
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.name
                        elide: Text.ElideRight
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: card.modelData.description
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                // The status and the command sit in fixed cells at the right edge, so the
                // dots and commands line up down the list whatever the name needs.
                RowLayout {
                    id: statusCell
                    anchors {
                        right: commandButton.left
                        verticalCenter: parent.verticalCenter
                        rightMargin: 8
                    }
                    width: 120
                    spacing: 8

                    Rectangle {
                        implicitWidth: 8
                        implicitHeight: 8
                        radius: width / 2
                        color: card.ready ? Appearance.m3colors.m3primary
                            : ColorUtils.transparentize(Appearance.colors.colSubtext, 0.5)
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: card.statusText
                        elide: Text.ElideRight
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                    }
                }

                RippleButton {
                    id: commandButton
                    anchors {
                        right: parent.right
                        verticalCenter: parent.verticalCenter
                        rightMargin: 12
                    }
                    width: 190
                    implicitHeight: 30
                    buttonRadius: Appearance.rounding.verysmall
                    colBackground: Appearance.colors.colLayer1
                    onClicked: AiOutputController.copyText(card.modelData.command)

                    contentItem: StyledText {
                        horizontalAlignment: Text.AlignHCenter
                        text: card.modelData.command
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer1
                    }

                    StyledToolTip { text: Translation.tr("Copy the sign-in command, then run it in a terminal") }
                }
            }
        }
    }
}

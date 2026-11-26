import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.services.ai

Item {
    id: root
    anchors.fill: parent
    property bool showBackButton: false
    signal goBack()

    ContentPage {
        anchors.fill: parent
        forceWidth: false

        RowLayout {
            visible: root.showBackButton
            spacing: Appearance.sizes.elevationMargin
            RippleButton {
                implicitWidth: Appearance.sizes.elevationMargin * 4
                implicitHeight: implicitWidth
                buttonRadius: Appearance.rounding.full
                colBackground: Appearance.colors.colSecondaryContainer
                colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                colRipple: Appearance.colors.colSecondaryContainerActive
                onClicked: root.goBack()
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: "arrow_back"
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnSecondaryContainer
                }
            }
            StyledText {
                text: Translation.tr("Context & Memory")
                font.pixelSize: Appearance.font.pixelSize.large
                font.family: Appearance.font.family.title
                color: Appearance.colors.colOnLayer0
            }
        }

        ContentSection {
            icon: "account_tree"
            title: Translation.tr("Conversation Context")
            tooltip: Translation.tr("Manage message history truncation and token allocation for long conversations.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "summarize"
                    text: Translation.tr("Manage long conversations")
                    checked: Config.options.ai.context.manage
                    onCheckedChanged: {
                        Config.options.ai.context.manage = checked;
                    }
                }

                ConfigSwitch {
                    enabled: Config.options.ai.context.manage
                    buttonIcon: "auto_awesome"
                    text: Translation.tr("Summarise earlier messages when needed")
                    checked: Config.options.ai.context.summarise
                    onCheckedChanged: {
                        Config.options.ai.context.summarise = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.ai.context.manage
                    icon: "data_usage"
                    text: Translation.tr("Tokens reserved for each answer")
                    value: Config.options.ai.context.reserveTokens
                    from: 256
                    to: 32768
                    stepSize: 256
                    onValueChanged: {
                        Config.options.ai.context.reserveTokens = value;
                    }
                }

                ConfigSwitch {
                    buttonIcon: "text_snippet"
                    text: Translation.tr("Extract text from attached documents")
                    checked: Config.options.ai.extractDocuments
                    onCheckedChanged: {
                        Config.options.ai.extractDocuments = checked;
                    }
                }
            }
        }

        ContentSection {
            icon: "psychology"
            title: Translation.tr("Long-Term Memory")
            tooltip: Translation.tr("Persist key facts and preferences across different chat sessions.")

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.sizes.elevationMargin / 2

                ConfigSwitch {
                    buttonIcon: "psychology"
                    text: Translation.tr("Remember facts between conversations")
                    checked: Config.options.ai.memory.enabled
                    onCheckedChanged: {
                        Config.options.ai.memory.enabled = checked;
                    }
                }

                ConfigSpinBox {
                    enabled: Config.options.ai.memory.enabled
                    icon: "memory"
                    text: Translation.tr("Facts remembered between conversations")
                    value: Config.options.ai.memory.limit
                    from: 0
                    to: 200
                    stepSize: 1
                    onValueChanged: {
                        Config.options.ai.memory.limit = value;
                    }
                }
            }
        }
        ContentSection {
            icon: "history"
            title: Translation.tr("Conversation continuity")
            ConfigSwitch {
                buttonIcon: "restore"
                text: Translation.tr("Reopen the last conversation on startup")
                checked: Config.options.ai.sessions.restoreLast
                onCheckedChanged: Config.options.ai.sessions.restoreLast = checked
            }
            ConfigSwitch {
                buttonIcon: "manage_search"
                text: Translation.tr("Retrieve relevant details from earlier conversations")
                checked: Config.options.ai.memory.retrieveHistory
                onCheckedChanged: Config.options.ai.memory.retrieveHistory = checked
            }
            ConfigSpinBox {
                icon: "data_usage"
                text: Translation.tr("Maximum input context, approximate tokens")
                from: 4096
                to: 32000
                stepSize: 1000
                value: Config.options.ai.context.maxInputTokens
                onValueChanged: Config.options.ai.context.maxInputTokens = value
            }
        }
        ContentSection {
            icon: "school"
            title: Translation.tr("Learned skills")
            ConfigSwitch {
                buttonIcon: "school"
                text: Translation.tr("Use saved skills across agents")
                checked: Config.options.ai.memory.skills
                onCheckedChanged: Config.options.ai.memory.skills = checked
            }
            ConfigSwitch {
                buttonIcon: "auto_awesome"
                text: Translation.tr("Learn reusable skills after verified tasks")
                enabled: Config.options.ai.memory.skills && Config.options.ai.memory.enabled
                checked: Config.options.ai.memory.autoLearn
                onCheckedChanged: Config.options.ai.memory.autoLearn = checked
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Background reviews use the selected agent’s allowance. Failed approaches remain drafts until verified.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: AiMemory.learning.state === "reviewing" ? Translation.tr("Reviewing the last task and improving saved knowledge…")
                    : AiMemory.learning.state === "queued" ? Translation.tr("A learning review is queued")
                    : AiMemory.learning.state === "failed" ? Translation.tr("Learning review failed: %1").arg(AiMemory.learning.error ?? "")
                    : AiMemory.learning.lastReviewAt ? Translation.tr("Last review: %1").arg(Translation.westernDigits(new Date(AiMemory.learning.lastReviewAt).toLocaleString(Translation.locale)))
                    : Translation.tr("Completed tasks are reviewed automatically. Reviews use your selected agent’s allowance.")
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                visible: String(AiMemory.learning.lastResult ?? "").length > 0
                text: AiMemory.learning.lastResult ?? ""
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1 saved facts · %2 learned skills. Relevant knowledge is retrieved locally for each request.").arg(AiMemory.facts.length).arg(AiMemory.skills.length)
                wrapMode: Text.Wrap
                color: Appearance.colors.colSubtext
            }
            StyledText {
                Layout.fillWidth: true
                visible: AiMemory.errorText.length > 0
                text: AiMemory.errorText
                wrapMode: Text.Wrap
                color: Appearance.m3colors.m3error
            }
            Repeater {
                model: AiMemory.skills
                delegate: ColumnLayout {
                    id: learnedSkill
                    required property var modelData
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        StyledText { Layout.fillWidth: true; text: learnedSkill.modelData.name + (learnedSkill.modelData.status === "draft" ? " · Draft" : ""); elide: Text.ElideRight; font.bold: true }
                        RippleButton {
                            buttonText: Translation.tr("Forget")
                            onClicked: AiMemory.forgetSkill(learnedSkill.modelData.id)
                        }
                    }
                    StyledText { Layout.fillWidth: true; text: learnedSkill.modelData.description; wrapMode: Text.Wrap; color: Appearance.colors.colSubtext }
                    StyledText { Layout.fillWidth: true; text: Translation.tr("Verified: %1").arg(learnedSkill.modelData.evidence); wrapMode: Text.Wrap; color: Appearance.colors.colSubtext; font.pixelSize: Appearance.font.pixelSize.small }
                }
            }
        }
    }
}

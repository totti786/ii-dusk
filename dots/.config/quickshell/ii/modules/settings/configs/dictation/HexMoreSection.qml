pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "hexSchema.js" as HexSchema

/**
 * The remaining Linux dictation settings, built from Hex's own catalogue so a new
 * Hex version's additions show up without a shell change. Their wording is Hex's.
 */
ContentSection {
    id: root

    icon: "science"
    title: Translation.tr("More Hex settings")
    collapsible: true
    expanded: false

    readonly property var entries: HexSchema.extras(HexSettings.catalogue)
    readonly property var groups: [
        {
            id: "dictation",
            title: Translation.tr("Dictation extras"),
            icon: "settings_voice"
        },
        {
            id: "window",
            title: Translation.tr("In the Hex window"),
            icon: "web_asset"
        },
        {
            id: "api",
            title: Translation.tr("Hex's local API"),
            icon: "api"
        }
    ]

    function describe(entry: var): string {
        return HexSettings.labDescriptions[entry.key] ?? String(entry.about ?? "").replace(/^Labs:\s*/, "");
    }

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: root.entries.length > 0
            ? Translation.tr("Mostly experimental features, described in Hex's own words.")
            : Translation.tr("Hex has to run once before these can be listed. Dictate something or open Hex, then reopen this page.")
    }

    Repeater {
        // Nothing is built until the section is opened.
        model: root.expanded ? root.groups.filter(group => root.entries.some(entry => HexSchema.group(entry.key) === group.id)) : []

        delegate: ContentSubsection {
            id: groupSection
            required property var modelData
            title: modelData.title
            icon: modelData.icon
            Layout.fillWidth: true

            Repeater {
                model: root.entries.filter(entry => HexSchema.group(entry.key) === groupSection.modelData.id)

                delegate: ColumnLayout {
                    id: row
                    required property var modelData
                    readonly property string hexKey: modelData.key
                    Layout.fillWidth: true
                    spacing: 4

                    Loader {
                        Layout.fillWidth: true
                        active: row.modelData.kind === "bool"
                        visible: active
                        sourceComponent: ConfigSwitch {
                            buttonIcon: "toggle_on"
                            text: Translation.tr(HexSchema.title(row.hexKey))
                            description: root.describe(row.modelData)
                            enabled: HexSettings.loaded
                            Binding on checked {
                                value: HexSettings.on(row.hexKey)
                            }
                            onCheckedChanged: HexSettings.set(row.hexKey, checked)
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: row.modelData.kind === "choice"
                        visible: active
                        sourceComponent: ColumnLayout {
                            spacing: 4

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr(HexSchema.title(row.hexKey))
                                color: Appearance.colors.colOnLayer0
                                wrapMode: Text.Wrap
                            }

                            ConfigSelectionArray {
                                enabled: HexSettings.loaded
                                currentValue: HexSettings.get(row.hexKey)
                                onSelected: newValue => HexSettings.set(row.hexKey, newValue)
                                options: (row.modelData.choices ?? []).map(choice => ({
                                            displayName: String(choice),
                                            value: choice
                                        }))
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: ["text", "integer", "number"].indexOf(row.modelData.kind) !== -1
                        visible: active
                        sourceComponent: ConfigTextField {
                            id: field
                            icon: "edit"
                            text: Translation.tr(HexSchema.title(row.hexKey))
                            tooltip: root.describe(row.modelData)
                            placeholderText: Translation.tr("Press Enter to save")
                            enabled: HexSettings.loaded
                            Binding on inputText {
                                value: String(HexSettings.get(row.hexKey) ?? "")
                            }
                            Connections {
                                target: field.textField
                                function onAccepted() {
                                    const typed = field.inputText.trim();
                                    if (row.modelData.kind === "text")
                                        HexSettings.set(row.hexKey, typed);
                                    else if (typed.length > 0 && !isNaN(Number(typed)))
                                        HexSettings.set(row.hexKey, Number(typed));
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

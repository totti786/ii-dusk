pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import "voxtypeSchema.js" as VoxSchema

/**
 * The remaining dictation settings, built from Voxtype's own schema so a new
 * version's additions show up without a shell change. Their wording is Voxtype's.
 */
ContentSection {
    id: root

    icon: "science"
    title: Translation.tr("More Voxtype settings")
    collapsible: true
    expanded: false

    readonly property var entries: VoxSchema.extras(VoxtypeSettings.keys, VoxtypeSettings.engine)

    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: Appearance.colors.colSubtext
        text: Translation.tr("Fine tuning, described in Voxtype's own words. Clearing a field restores its default.")
    }

    Repeater {
        // Nothing is built until the section is opened. Keyed by name so that a
        // saved value does not rebuild the rows.
        model: root.expanded ? VoxSchema.sections(root.entries) : []

        delegate: ContentSubsection {
            id: group
            required property string modelData
            title: Translation.tr(modelData)
            icon: "settings"
            Layout.fillWidth: true
            collapsible: true
            expanded: false

            Repeater {
                model: group.expanded ? root.entries.filter(entry => entry.section === group.modelData).map(entry => entry.key) : []

                delegate: ColumnLayout {
                    id: row
                    required property string modelData
                    readonly property var entry: VoxtypeSettings.entries[modelData] ?? ({})
                    readonly property string kind: entry.type ?? ""
                    Layout.fillWidth: true
                    spacing: 4

                    Loader {
                        Layout.fillWidth: true
                        active: row.kind === "bool"
                        visible: active
                        sourceComponent: ConfigSwitch {
                            buttonIcon: "toggle_on"
                            text: Translation.tr(row.entry.label ?? row.modelData)
                            description: row.entry.description ?? ""
                            enabled: VoxtypeSettings.loaded
                            Binding on checked {
                                value: VoxtypeSettings.on(row.modelData)
                            }
                            onCheckedChanged: VoxtypeSettings.set(row.modelData, checked)
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: row.kind === "enum"
                        visible: active
                        sourceComponent: ColumnLayout {
                            spacing: 4

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr(row.entry.label ?? row.modelData)
                                color: Appearance.colors.colOnLayer0
                                wrapMode: Text.Wrap
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: row.entry.description ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }

                            ConfigSelectionArray {
                                enabled: VoxtypeSettings.loaded
                                currentValue: VoxtypeSettings.get(row.modelData)
                                onSelected: newValue => VoxtypeSettings.set(row.modelData, newValue)
                                options: (row.entry.choices ?? []).map(choice => ({
                                            displayName: String(choice),
                                            value: choice
                                        }))
                            }
                        }
                    }

                    Loader {
                        Layout.fillWidth: true
                        active: row.kind.length > 0 && row.kind !== "bool" && row.kind !== "enum"
                        visible: active
                        sourceComponent: ColumnLayout {
                            spacing: 4

                            ConfigTextField {
                                id: field
                                icon: "edit"
                                text: Translation.tr(row.entry.label ?? row.modelData)
                                placeholderText: Translation.tr("Press Enter to save")
                                enabled: VoxtypeSettings.loaded
                                Binding on inputText {
                                    value: {
                                        const stored = VoxtypeSettings.get(row.modelData);
                                        if (stored === null || stored === undefined)
                                            return "";
                                        // Voxtype keeps decimals as 32-bit floats.
                                        return row.kind === "float" ? String(Math.round(stored * 10000) / 10000) : String(stored);
                                    }
                                }
                                Connections {
                                    target: field.textField
                                    function onAccepted() {
                                        VoxtypeSettings.set(row.modelData, field.inputText.trim());
                                    }
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: row.entry.description ?? ""
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                color: Appearance.colors.colSubtext
                                wrapMode: Text.Wrap
                            }
                        }
                    }
                }
            }
        }
    }
}

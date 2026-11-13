pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The Anki app's right-hand settings sheet. */
ClockSheet {
    id: root

    title: Translation.tr("Anki settings")
    subtitle: Translation.tr("The shell owns the collection while this window is open")

    ColumnLayout {
        Layout.fillWidth: true
        spacing: ClockStyle.gap

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Profile")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }

        Flow {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            Repeater {
                model: AnkiService.profiles

                delegate: ClockChip {
                    required property var modelData
                    label: String(modelData)
                    selected: AnkiService.profile === String(modelData)
                    onClicked: {
                        if (AnkiService.profile === String(modelData))
                            return;
                        Config.options.anki.profile = String(modelData);
                        AnkiService.retry();
                        root.close();
                    }
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: AnkiService.profiles.length === 0
            text: Translation.tr("Using Anki's last-used profile.")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }

        ClockFormToggle {
            Layout.fillWidth: true
            label: Translation.tr("Play audio automatically")
            description: Translation.tr("Play the question and answer clips when they appear")
            checked: Config.options.anki.autoPlayAudio
            onToggled: checked => Config.options.anki.autoPlayAudio = checked
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: ClockStyle.colOutline
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Collection")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            text: AnkiService.collectionPath.length > 0 ? AnkiService.collectionPath : Translation.tr("Not open")
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colOnSurface
            wrapMode: Text.WrapAnywhere
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Anki %1").arg(AnkiService.version)
            visible: AnkiService.version.length > 0
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
        }

        ClockButton {
            Layout.fillWidth: true
            label: Translation.tr("Close and release collection")
            symbol: "lock_open"
            variant: "text"
            onClicked: {
                AnkiService.stop();
                GlobalStates.ankiOpen = false;
            }
        }
    }
}

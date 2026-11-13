pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."
import "../components"

/**
 * Where the sounds live. Everything else (volumes, mixes, the timer) is saved as you use it.
 */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: width

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: list
            width: flick.width
            spacing: ClockStyle.paneGap

            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "settings"
                shape: MaterialShape.Shape.Cookie9Sided
                title: Translation.tr("Where the sounds live")
                text: Translation.tr("Soundscapes plays the recordings of a Noice library folder: audio, icons and the manifest.")
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("Sound library")
                symbol: "folder_open"

                ClockSettingsRow {
                    first: true
                    symbol: "folder"
                    title: Translation.tr("Library folder")
                    description: SoundscapesService.catalogError.length > 0 ? SoundscapesService.catalogError
                        : Translation.tr("%1 in %2 groups").arg(SoundscapesService.countLabel(SoundscapesService.sounds.length)).arg(SoundscapesService.groups.length)

                    Rectangle {
                        implicitWidth: root.compact ? 200 : 300
                        implicitHeight: 40
                        radius: 20
                        color: ClockStyle.colField
                        TextInput {
                            id: pathInput
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gapLarge
                                rightMargin: ClockStyle.gapLarge
                            }
                            text: SoundscapesService.libraryDir
                            clip: true
                            color: ClockStyle.colOnSurface
                            selectionColor: ClockStyle.colPrimary
                            selectedTextColor: ClockStyle.colOnPrimary
                            font.family: Appearance.font.family.monospace
                            font.pixelSize: ClockStyle.textNormal
                            verticalAlignment: TextInput.AlignVCenter
                            onAccepted: root.apply()
                        }
                    }
                }
                ClockSettingsRow {
                    symbol: "cloud_download"
                    title: Translation.tr("Download missing sounds")
                    description: SoundscapesService.downloading ? Translation.tr("Downloading… %1 / %2").arg(SoundscapesService.downloadDone).arg(SoundscapesService.downloadTotal)
                        : SoundscapesService.downloadError.length > 0 ? SoundscapesService.downloadError
                        : SoundscapesService.missingClips > 0 || SoundscapesService.needsDownload ? Translation.tr("%1 recordings are not on disk").arg(SoundscapesService.needsDownload ? 33 : SoundscapesService.missingClips)
                        : Translation.tr("Everything is downloaded")
                    ClockButton {
                        enabled: !SoundscapesService.downloading
                        symbol: "download"
                        label: Translation.tr("Download")
                        variant: "tonal"
                        onClicked: SoundscapesService.download()
                    }
                }
                ClockSettingsRow {
                    last: true
                    symbol: "sync"
                    title: Translation.tr("Use this folder")
                    description: Translation.tr("Reads the library again; a mix that is playing is stopped")
                    ClockButton {
                        symbol: "check"
                        label: Translation.tr("Apply")
                        variant: "tonal"
                        onClicked: root.apply()
                    }
                }
            }

            ClockSettingsSection {
                Layout.fillWidth: true
                title: Translation.tr("About")
                symbol: "info"

                ClockSettingsRow {
                    first: true
                    last: true
                    symbol: "volunteer_activism"
                    title: Translation.tr("Credits")
                    description: Translation.tr("The recordings come from the Noice library. Most are CC BY: each sound's info sheet names its author and licence, so give them credit if you share anything made from them.")
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: ClockStyle.gap
            }
        }
    }

    function apply(): void {
        const path = pathInput.text.trim();
        if (path.length > 0 && path !== SoundscapesService.libraryDir)
            Config.options.soundscapes.libraryDir = path;
        else
            SoundscapesService.loadCatalog();
    }
}

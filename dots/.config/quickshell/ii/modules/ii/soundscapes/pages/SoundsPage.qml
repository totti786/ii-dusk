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
 * The library: every sound as a tile, one pane per group. Tap to layer a sound into the
 * mix; the tile grows a volume slider. A search box and group chips narrow it down.
 */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: width
    property string group: ""
    property string query: ""

    signal infoRequested(string soundId)

    readonly property var matches: SoundscapesService.sounds.filter(s => {
        if (root.group.length > 0 && s.groupId !== root.group)
            return false;
        const q = root.query.trim().toLowerCase();
        return q.length === 0 || s.name.toLowerCase().includes(q) || s.group.toLowerCase().includes(q)
            || s.tags.some(t => t.toLowerCase().includes(q));
    })
    readonly property var shownGroups: SoundscapesService.groups.filter(g => root.matches.some(s => s.groupId === g.id))
    readonly property int columns: Math.max(2, Math.floor((root.layoutWidth - ClockStyle.cardPadding * 2 + ClockStyle.gap) / (SoundscapesStyle.tileMinWidth + ClockStyle.gap)))

    function soundsOf(groupId) {
        return root.matches.filter(s => s.groupId === groupId);
    }

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
                symbol: "air"
                shape: MaterialShape.Shape.Cookie12Sided
                title: Translation.tr("Make your own weather")
                text: Translation.tr("Layer rain over a café, a fire against the wind. Tap sounds to add them, then set each one's volume.")
                trailing: [
                    ClockButton {
                        symbol: "casino"
                        label: Translation.tr("Surprise me")
                        variant: "filled"
                        iconOnly: root.compact
                        onClicked: SoundscapesService.surprise()
                    }
                ]
            }

            DownloadBanner {
                Layout.fillWidth: true
            }

            // Search and the group filter
            ColumnLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    radius: height / 2
                    color: ClockStyle.colSurfaceHigh

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: ClockStyle.gapLarge
                            rightMargin: ClockStyle.gapSmall
                        }
                        spacing: ClockStyle.gapSmall
                        MaterialSymbol {
                            text: "search"
                            iconSize: ClockStyle.iconNormal
                            color: ClockStyle.colOnSurfaceVariant
                        }
                        TextInput {
                            id: search
                            Layout.fillWidth: true
                            text: root.query
                            onTextChanged: root.query = text
                            color: ClockStyle.colOnSurface
                            selectionColor: ClockStyle.colPrimary
                            selectedTextColor: ClockStyle.colOnPrimary
                            font.family: Appearance.font.family.main
                            font.pixelSize: ClockStyle.textNormal + 1
                            clip: true
                            verticalAlignment: TextInput.AlignVCenter
                            Keys.onEscapePressed: event => {
                                if (text.length > 0) {
                                    text = "";
                                    event.accepted = true;
                                } else {
                                    event.accepted = false;
                                }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: search.text.length === 0
                                text: Translation.tr("Search sounds, places, animals…")
                                font.pixelSize: ClockStyle.textNormal + 1
                                color: ClockStyle.colSubtext
                            }
                        }
                        ClockIconButton {
                            visible: root.query.length > 0
                            symbol: "close"
                            size: 32
                            iconSize: 18
                            tooltip: Translation.tr("Clear")
                            onClicked: search.text = ""
                        }
                    }
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall
                    ClockChip {
                        symbol: "apps"
                        label: Translation.tr("All")
                        selected: root.group.length === 0
                        onClicked: root.group = ""
                    }
                    Repeater {
                        model: SoundscapesService.groups
                        delegate: ClockChip {
                            required property var modelData
                            symbol: SoundscapesService.styleOf(modelData.id).symbol
                            label: modelData.name
                            selected: root.group === modelData.id
                            onClicked: root.group = root.group === modelData.id ? "" : modelData.id
                        }
                    }
                }
            }

            ClockEmptyState {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapHuge
                visible: SoundscapesService.catalogLoaded && SoundscapesService.catalogError.length > 0 && !SoundscapesService.downloading
                symbol: SoundscapesService.needsDownload ? "cloud_download" : "folder_off"
                title: SoundscapesService.needsDownload ? Translation.tr("The sounds are not here yet") : Translation.tr("No sound library")
                subtitle: SoundscapesService.needsDownload
                    ? Translation.tr("%1. Download them (about 53 MB), or point the app at another folder in its settings.").arg(SoundscapesService.catalogError)
                    : Translation.tr("%1. Point the app at the folder in its settings.").arg(SoundscapesService.catalogError)
            }
            ClockButton {
                Layout.alignment: Qt.AlignHCenter
                visible: SoundscapesService.needsDownload && !SoundscapesService.downloading && SoundscapesService.downloadError.length === 0
                symbol: "download"
                label: Translation.tr("Download the sounds")
                variant: "filled"
                onClicked: SoundscapesService.download()
            }
            ClockEmptyState {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapHuge
                visible: SoundscapesService.catalogLoaded && SoundscapesService.catalogError.length === 0 && root.matches.length === 0
                symbol: "search_off"
                title: Translation.tr("Nothing sounds like that")
                subtitle: Translation.tr("Try another word, or clear the filter")
            }

            Repeater {
                model: root.shownGroups
                delegate: ClockPane {
                    id: pane
                    required property var modelData
                    readonly property var look: SoundscapesService.styleOf(modelData.id)
                    readonly property var inGroup: root.soundsOf(modelData.id)
                    Layout.fillWidth: true
                    title: modelData.name
                    symbol: look.symbol
                    shape: MaterialShape.Shape[look.shape] ?? MaterialShape.Shape.Cookie9Sided
                    count: inGroup.length

                    GridLayout {
                        Layout.fillWidth: true
                        columns: root.columns
                        columnSpacing: ClockStyle.gap
                        rowSpacing: ClockStyle.gap
                        uniformCellWidths: true

                        Repeater {
                            model: pane.inGroup
                            delegate: SoundTile {
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.preferredHeight: SoundscapesStyle.tileHeight
                                sound: modelData
                                active: SoundscapesService.isOn(modelData.id)
                                volume: SoundscapesService.stateOf(modelData.id).vol
                                playing: SoundscapesService.playing
                                onToggled: modelData.available ? SoundscapesService.toggle(modelData.id) : SoundscapesService.download()
                                onVolumeMoved: value => SoundscapesService.setVolume(modelData.id, value)
                                onInfoRequested: root.infoRequested(modelData.id)
                            }
                        }
                    }
                }
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: SoundscapesService.hasMix ? SoundscapesStyle.dockClearance : ClockStyle.gap
            }
        }
    }
}

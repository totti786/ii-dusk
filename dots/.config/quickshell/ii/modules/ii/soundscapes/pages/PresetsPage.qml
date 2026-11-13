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
 * Mixes: the ones that ship with the app and the ones you saved. Choosing one swaps the
 * whole mix, fading what was playing into the new layers.
 */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: width

    signal saveRequested()

    readonly property int columns: Math.max(1, Math.floor((root.layoutWidth - ClockStyle.cardPadding * 2 + ClockStyle.gap) / (264 + ClockStyle.gap)))
    readonly property var builtins: SoundscapesService.catalog.presets ?? []
    readonly property var mine: SoundscapesService.userPresets

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
                symbol: "bookmark_stacks"
                shape: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("A mood for every hour")
                text: Translation.tr("Start from a ready-made mix, or save the one you built so it is a tap away.")
                trailing: [
                    ClockButton {
                        visible: SoundscapesService.hasMix
                        symbol: "bookmark_add"
                        label: Translation.tr("Save current mix")
                        variant: "filled"
                        iconOnly: root.compact
                        onClicked: root.saveRequested()
                    }
                ]
            }

            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Your mixes")
                symbol: "bookmark"
                shape: MaterialShape.Shape.SoftBurst
                count: root.mine.length

                GridLayout {
                    Layout.fillWidth: true
                    visible: root.mine.length > 0
                    columns: root.columns
                    columnSpacing: ClockStyle.gap
                    rowSpacing: ClockStyle.gap
                    uniformCellWidths: true
                    Repeater {
                        model: root.mine
                        delegate: PresetCard {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            preset: modelData
                            tone: (index + 1) % 3
                            current: SoundscapesService.preset === modelData.id
                            playing: SoundscapesService.playing
                            onChosen: SoundscapesService.loadPreset(modelData.id)
                            onDeleted: SoundscapesService.deletePreset(modelData.id)
                        }
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    visible: root.mine.length === 0
                    implicitHeight: hint.implicitHeight + ClockStyle.gap * 2
                    radius: ClockStyle.radiusLarge
                    color: ClockStyle.colSurfaceHigh
                    RowLayout {
                        id: hint
                        anchors {
                            fill: parent
                            margins: ClockStyle.gap
                        }
                        spacing: ClockStyle.gap
                        ClockBadge {
                            size: 52
                            text: "bookmark_add"
                            shape: MaterialShape.Shape.Cookie7Sided
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("Nothing saved yet")
                                font.family: Appearance.font.family.title
                                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                                font.pixelSize: ClockStyle.textLarge
                                color: ClockStyle.colOnSurface
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: SoundscapesService.hasMix ? Translation.tr("Save what is playing and it will wait here")
                                    : Translation.tr("Build a mix, then save it from here or from the Mix tab")
                                wrapMode: Text.WordWrap
                                font.pixelSize: ClockStyle.textSmall
                                color: ClockStyle.colSubtext
                            }
                        }
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Made for you")
                symbol: "auto_awesome"
                shape: MaterialShape.Shape.Cookie12Sided
                count: root.builtins.length

                GridLayout {
                    Layout.fillWidth: true
                    columns: root.columns
                    columnSpacing: ClockStyle.gap
                    rowSpacing: ClockStyle.gap
                    uniformCellWidths: true
                    Repeater {
                        model: root.builtins
                        delegate: PresetCard {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            preset: modelData
                            tone: index % 3
                            current: SoundscapesService.preset === modelData.id
                            playing: SoundscapesService.playing
                            onChosen: SoundscapesService.loadPreset(modelData.id)
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

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Every speaker and microphone PipeWire knows, with the default marked and changeable. */
Item {
    id: root

    property bool compact: false
    property real layoutWidth: root.width

    readonly property bool sideBySide: root.layoutWidth >= 880

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
                symbol: "speaker_group"
                title: Translation.tr("Where sound goes and comes from")
                text: Translation.tr("The default speakers and microphone are what new apps use. Click a device to make it the default.")
            }

            GridLayout {
                Layout.fillWidth: true
                columns: root.sideBySide ? 2 : 1
                rowSpacing: ClockStyle.paneGap
                columnSpacing: ClockStyle.paneGap

                ClockPane {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Output devices")
                    symbol: "speaker"
                    count: Audio.outputDevices.length
                    Repeater {
                        model: Audio.outputDevices
                        delegate: MixerVolumeCard {
                            required property var modelData
                            node: modelData
                            device: true
                            isDefault: modelData.id === Audio.sink?.id
                            onMakeDefault: Audio.setDefaultSink(modelData)
                        }
                    }
                }

                ClockPane {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Input devices")
                    symbol: "mic"
                    shape: MaterialShape.Shape.Clover4Leaf
                    count: Audio.inputDevices.length
                    Repeater {
                        model: Audio.inputDevices
                        delegate: MixerVolumeCard {
                            required property var modelData
                            node: modelData
                            device: true
                            isDefault: modelData.id === Audio.source?.id
                            onMakeDefault: Audio.setDefaultSource(modelData)
                        }
                    }
                }
            }

            ClockEmptyState {
                Layout.fillWidth: true
                visible: Audio.outputDevices.length === 0 && Audio.inputDevices.length === 0
                symbol: "speaker_group"
                title: Translation.tr("No sound devices")
                subtitle: Translation.tr("Is PipeWire running?")
            }
        }
    }
}

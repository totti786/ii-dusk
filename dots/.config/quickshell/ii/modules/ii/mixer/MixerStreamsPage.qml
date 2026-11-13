pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The apps playing sound (output: true) or listening to a microphone (output: false), each
 * with its own volume, under the volume of the default device that carries them.
 */
Item {
    id: root

    property bool output: true
    property bool compact: false
    property real layoutWidth: root.width

    readonly property var streams: root.output ? Audio.outputAppNodes : Audio.inputAppNodes
    readonly property var master: root.output ? Audio.sink : Audio.source
    readonly property real padding: root.compact ? ClockStyle.pagePadding : ClockStyle.pagePaddingWide

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
                symbol: root.output ? "volume_up" : "mic"
                shape: root.output ? MaterialShape.Shape.Cookie9Sided : MaterialShape.Shape.Clover4Leaf
                title: root.output ? Translation.tr("Every sound, one slider each") : Translation.tr("Who is listening to you")
                text: root.output ? Translation.tr("Turn an app up past 100 % or down to nothing without touching the others.")
                    : Translation.tr("Apps that are recording from a microphone, with a volume for each.")
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.master !== null
                title: root.output ? Translation.tr("Speakers") : Translation.tr("Microphone")
                symbol: root.output ? "speaker" : "mic"
                MixerVolumeCard {
                    node: root.master
                    device: true
                    isDefault: true
                }
            }

            ClockPane {
                Layout.fillWidth: true
                title: root.output ? Translation.tr("Apps") : Translation.tr("Apps listening")
                symbol: "apps"
                shape: MaterialShape.Shape.SoftBurst
                count: root.streams.length
                Repeater {
                    model: root.streams
                    delegate: MixerVolumeCard {
                        required property var modelData
                        node: modelData
                    }
                }
                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.streams.length === 0
                    symbol: root.output ? "volume_off" : "mic_off"
                    shapeSize: ClockStyle.emptyShapeSmall
                    title: root.output ? Translation.tr("Nothing is playing") : Translation.tr("Nothing is listening")
                    subtitle: root.output ? Translation.tr("Apps appear here while they make sound")
                        : Translation.tr("Apps appear here while they use the microphone")
                }
            }
        }
    }
}

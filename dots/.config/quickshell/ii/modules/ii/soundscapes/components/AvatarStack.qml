import QtQuick
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * The sounds of a mix as overlapping round pictograms, each in its group's tone, with a
 * "+N" for the ones that do not fit. `ringColor` is the surface behind, so the circles
 * look cut out of each other.
 */
Item {
    id: root

    property var ids: []
    property int maxShown: 5
    property real size: 40
    property color ringColor: ClockStyle.colPane

    readonly property int shown: Math.min(root.ids.length, root.maxShown)
    readonly property int extra: root.ids.length - root.shown
    readonly property real step: root.size * 0.68

    implicitWidth: root.shown > 0 ? root.step * (root.shown + (root.extra > 0 ? 1 : 0) - 1) + root.size : 0
    implicitHeight: root.size

    function toneOf(id) {
        return SoundscapesService.styleOf(SoundscapesService.sound(id)?.groupId ?? "").tone;
    }

    Repeater {
        model: root.ids.slice(0, root.shown)
        delegate: Rectangle {
            required property string modelData
            required property int index
            readonly property int tone: root.toneOf(modelData)
            x: index * root.step
            width: root.size
            height: root.size
            radius: width / 2
            color: SoundscapesStyle.container(tone)
            border.width: Math.max(2, root.size * 0.07)
            border.color: root.ringColor
            z: root.shown - index
            SoundIcon {
                anchors.centerIn: parent
                width: root.size * 0.52
                height: width
                source: SoundscapesService.sound(parent.modelData)?.icon ?? ""
                color: SoundscapesStyle.onContainer(parent.tone)
            }
        }
    }
    Rectangle {
        visible: root.extra > 0
        x: root.shown * root.step
        width: root.size
        height: root.size
        radius: width / 2
        color: ClockStyle.colSurfaceHighest
        border.width: Math.max(2, root.size * 0.07)
        border.color: root.ringColor
        StyledText {
            anchors.centerIn: parent
            text: `+${root.extra}`
            font.pixelSize: Math.round(root.size * 0.34)
            font.weight: Font.DemiBold
            color: ClockStyle.colOnSurfaceVariant
        }
    }
}

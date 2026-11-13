import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * A saved or built-in mix: a mark, its name and the sounds it layers. The one that is
 * playing now is filled and says so; yours can be deleted.
 */
Item {
    id: root

    required property var preset
    property bool current: false
    property bool playing: false
    property int tone: 0

    signal chosen()
    signal deleted()

    readonly property var ids: Object.keys(root.preset.mix ?? {})
    readonly property color surface: root.current ? SoundscapesStyle.container(root.tone)
        : (pointer.containsMouse ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh)

    implicitHeight: 148
    scale: pointer.pressed ? 0.975 : 1
    Behavior on scale {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    Rectangle {
        anchors.fill: parent
        radius: ClockStyle.radiusCard
        color: root.surface
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
    }
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.chosen()
    }

    RowLayout {
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 16
        }
        spacing: ClockStyle.gap

        ClockBadge {
            size: 52
            text: root.preset.icon ?? "bookmark"
            shape: root.current ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie9Sided
            color: root.current ? SoundscapesStyle.accent(root.tone) : SoundscapesStyle.container(root.tone)
            colSymbol: root.current ? SoundscapesStyle.onAccent(root.tone) : SoundscapesStyle.onContainer(root.tone)
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.preset.name
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                font.pixelSize: ClockStyle.textLarge
                color: root.current ? SoundscapesStyle.onContainer(root.tone) : ClockStyle.colOnSurface
            }
            StyledText {
                Layout.fillWidth: true
                text: root.current ? (root.playing ? Translation.tr("Playing now") : Translation.tr("Paused"))
                    : SoundscapesService.countLabel(root.ids.length)
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: root.current ? SoundscapesStyle.onContainer(root.tone) : ClockStyle.colSubtext
            }
        }
        ClockIconButton {
            visible: !(root.preset.builtin ?? true)
            symbol: "delete"
            size: 36
            iconSize: 20
            tooltip: Translation.tr("Delete this mix")
            colIcon: root.current ? SoundscapesStyle.onContainer(root.tone) : ClockStyle.colOnSurfaceVariant
            onClicked: root.deleted()
        }
    }

    AvatarStack {
        anchors {
            left: parent.left
            bottom: parent.bottom
            leftMargin: 16
            bottomMargin: 16
        }
        ids: root.ids
        size: 36
        maxShown: 6
        ringColor: root.surface
    }
}

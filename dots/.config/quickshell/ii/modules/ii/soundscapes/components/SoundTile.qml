import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * One sound of the library. Tapping it puts it in the mix: the card takes its group's tone,
 * the badge turns into a livelier shape and starts to spin, rings pulse behind it, and a
 * volume slider takes the place of the group name.
 */
Item {
    id: root

    required property var sound
    property bool active: false
    property real volume: 0.6
    /// The mix is audible (not paused): only then do the badge and its rings move.
    property bool playing: false

    signal toggled()
    signal volumeMoved(real value)
    signal infoRequested()

    readonly property var look: SoundscapesService.styleOf(root.sound.groupId)
    readonly property int tone: root.look.tone
    readonly property color colOn: SoundscapesStyle.onContainer(root.tone)
    readonly property color colAccent: SoundscapesStyle.accent(root.tone)
    readonly property color colOnAccent: SoundscapesStyle.onAccent(root.tone)
    readonly property bool lively: root.active && root.playing && !ClockStyle.reducedMotion

    implicitHeight: SoundscapesStyle.tileHeight
    opacity: root.sound.available ? 1 : 0.55
    scale: pointer.pressed ? 0.975 : 1
    Behavior on scale {
        enabled: !ClockStyle.reducedMotion
        animation: ClockStyle.motionFast.numberAnimation.createObject(this)
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: ClockStyle.radiusCard
        color: root.active ? (pointer.containsMouse ? SoundscapesStyle.containerHover(root.tone) : SoundscapesStyle.container(root.tone))
            : (pointer.containsMouse ? ClockStyle.colSurfaceHighest : ClockStyle.colSurfaceHigh)
        Behavior on color {
            animation: ClockStyle.motionFast.colorAnimation.createObject(this)
        }
    }

    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.toggled()
    }

    // Two rings that swell out of the badge and fade, offset by half a cycle
    Item {
        id: badgeSlot
        x: 14
        y: 14
        width: 60
        height: 60

        Repeater {
            model: 2
            delegate: Rectangle {
                id: ring
                required property int index
                anchors.centerIn: parent
                width: badgeSlot.width
                height: width
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: root.colAccent
                opacity: 0
                scale: 1
                SequentialAnimation {
                    running: root.lively
                    loops: Animation.Infinite
                    PauseAnimation { duration: ring.index * 1500 }
                    ParallelAnimation {
                        NumberAnimation { target: ring; property: "scale"; from: 1; to: 1.7; duration: 3000; easing.type: Easing.OutCubic }
                        SequentialAnimation {
                            NumberAnimation { target: ring; property: "opacity"; from: 0; to: 0.45; duration: 300 }
                            NumberAnimation { target: ring; property: "opacity"; to: 0; duration: 2700; easing.type: Easing.OutCubic }
                        }
                    }
                    onStopped: {
                        ring.opacity = 0;
                        ring.scale = 1;
                    }
                }
            }
        }

        SoundBadge {
            anchors.fill: parent
            size: 60
            icon: root.sound.icon
            shapeName: root.active ? SoundscapesStyle.morphOf(root.look.shape) : root.look.shape
            colShape: root.active ? root.colAccent : SoundscapesStyle.container(root.tone)
            colIcon: root.active ? root.colOnAccent : SoundscapesStyle.onContainer(root.tone)
            spinning: root.lively
        }
    }

    ClockIconButton {
        anchors {
            top: parent.top
            right: parent.right
            topMargin: 8
            rightMargin: 8
        }
        symbol: "info"
        size: 32
        iconSize: 18
        tooltip: Translation.tr("About this sound")
        colIcon: root.active ? root.colOn : ClockStyle.colOnSurfaceVariant
        opacity: root.active || pointer.containsMouse || hovered ? 0.9 : 0.45
        Behavior on opacity {
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
        onClicked: root.infoRequested()
    }

    StyledText {
        id: nameText
        anchors {
            left: parent.left
            right: parent.right
            top: badgeSlot.bottom
            leftMargin: 16
            rightMargin: 12
            topMargin: 12
        }
        text: root.sound.name
        elide: Text.ElideRight
        font.family: Appearance.font.family.title
        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
        font.pixelSize: ClockStyle.textLarge
        color: root.active ? root.colOn : ClockStyle.colOnSurface
    }

    Item {
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 12
            rightMargin: 12
            bottomMargin: 8
        }
        height: 34

        StyledText {
            anchors {
                left: parent.left
                right: parent.right
                leftMargin: 4
                verticalCenter: parent.verticalCenter
            }
            text: !root.sound.available ? Translation.tr("Not downloaded · tap to fetch")
                : root.sound.silence > 0 ? `${root.sound.group} · ${Translation.tr("now and then")}` : root.sound.group
            elide: Text.ElideRight
            font.pixelSize: ClockStyle.textSmall
            color: ClockStyle.colSubtext
            opacity: root.active ? 0 : 1
            Behavior on opacity {
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
        }

        StyledSlider {
            anchors.fill: parent
            opacity: root.active ? 1 : 0
            enabled: root.active
            visible: opacity > 0
            from: 0
            to: 1
            value: root.volume
            configuration: StyledSlider.Configuration.XS
            stopIndicatorValues: []
            highlightColor: root.colAccent
            handleColor: root.colAccent
            trackColor: ColorUtils.transparentize(root.colOn, 0.82)
            tooltipContent: `${Math.round(value * 100)}%`
            onMoved: root.volumeMoved(value)
            Behavior on opacity {
                NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
            }
        }
    }
}

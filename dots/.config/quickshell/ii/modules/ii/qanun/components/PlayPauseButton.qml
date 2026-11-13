import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.qanun

/**
 * The metronome's transport: a large scalloped play/pause switch that morphs its
 * shape, crossfades its glyph and breathes a ring while the click is running.
 */
Item {
    id: root

    property bool playing: false
    property bool counting: false
    property real size: 84
    property string playTooltip: Translation.tr("Start")
    property string pauseTooltip: Translation.tr("Pause")
    property color containerColor: QanunStyle.colPrimary
    property color contentColor: QanunStyle.colOnPrimary

    signal clicked()

    implicitWidth: root.size
    implicitHeight: root.size
    opacity: root.enabled ? 1 : 0.45

    // Breathing halo.
    Rectangle {
        id: halo
        anchors.centerIn: parent
        width: parent.width
        height: parent.height
        radius: width / 2
        color: "transparent"
        border.width: 2
        border.color: root.containerColor
        opacity: 0
        scale: 1

        SequentialAnimation {
            id: haloAnimation
            loops: Animation.Infinite
            running: root.playing && !Appearance.reducedMotion
            PauseAnimation { duration: 260 }
            ParallelAnimation {
                NumberAnimation { target: halo; property: "scale"; from: 1; to: 1.35; duration: 900; easing.type: Easing.OutCubic }
                NumberAnimation { target: halo; property: "opacity"; from: 0.28; to: 0; duration: 900; easing.type: Easing.OutCubic }
            }
            PauseAnimation { duration: 120 }
            onRunningChanged: if (!running) { halo.scale = 1; halo.opacity = 0; }
        }
    }

    MaterialShape {
        id: shape
        anchors.fill: parent
        shapeString: root.playing ? "Cookie9Sided" : "Cookie7Sided"
        color: root.containerColor
        rotation: ripple.hovered ? 8 : 0
        scale: ripple.down ? 0.9 : (ripple.hovered ? 1.03 : 1)

        Behavior on rotation {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on scale {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    RippleButton {
        id: ripple
        anchors.fill: parent
        buttonRadius: root.size / 2
        buttonRadiusPressed: root.size * 0.22
        colBackground: "transparent"
        colBackgroundHover: Qt.alpha(QanunStyle.colOnPrimary, 0.08)
        colBackgroundActive: Qt.alpha(QanunStyle.colOnPrimary, 0.14)
        colRipple: Qt.alpha(QanunStyle.colOnPrimary, 0.22)
        enabled: root.enabled
        Accessible.name: root.playing ? root.pauseTooltip : root.playTooltip
        onClicked: root.clicked()

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: "play_arrow"
                iconSize: root.size * 0.46
                fill: 1
                color: root.contentColor
                scale: root.playing ? 0.55 : 1
                opacity: root.playing ? 0 : 1
                rotation: root.playing ? -40 : 0

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.counting ? "timer" : "pause"
                iconSize: root.size * 0.42
                fill: 1
                color: root.contentColor
                scale: root.playing ? 1 : 0.55
                opacity: root.playing ? 1 : 0
                rotation: root.playing ? 0 : 40

                Behavior on scale {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on rotation {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
        }
    }

    StyledToolTip {
        text: root.playing ? root.pauseTooltip : root.playTooltip
        extraVisibleCondition: ripple.hovered
    }
}

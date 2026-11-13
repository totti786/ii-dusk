import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/**
 * The reward for finishing: a small banner and a burst of paper in the tag's colour.
 * Built by the app on a signal and destroyed when it has played, so an idle app
 * holds no particles, no timers and no animation tree.
 */
Item {
    id: root

    property string message: ""
    property string symbol: "celebration"
    property color colAccent: GritStyle.colPrimary

    signal finished()

    anchors.fill: parent
    z: 200

    Timer {
        interval: GritStyle.reducedMotion ? 1400 : 2800
        running: true
        onTriggered: root.finished()
    }

    Repeater {
        model: GritStyle.reducedMotion ? 0 : 44

        Rectangle {
            id: particle
            required property int index

            readonly property real startX: root.width * (0.3 + Math.random() * 0.4)
            readonly property real drift: (Math.random() - 0.5) * root.width * 0.7
            readonly property real fall: root.height * (0.35 + Math.random() * 0.55)
            readonly property real size: 5 + Math.random() * 8
            readonly property color tint: index % 3 === 0
                ? ColorUtils.mix(root.colAccent, GritStyle.colTertiary, 0.7)
                : index % 3 === 1
                    ? ColorUtils.mix(root.colAccent, GritStyle.colSecondaryContainer, 0.7)
                    : root.colAccent

            x: startX
            y: root.height * 0.28
            width: size
            height: size * (0.6 + Math.random() * 0.8)
            radius: index % 2 === 0 ? width / 2 : 2
            color: tint
            opacity: 0
            rotation: Math.random() * 360

            ParallelAnimation {
                running: true

                NumberAnimation {
                    target: particle
                    property: "opacity"
                    from: 1
                    to: 0
                    duration: Appearance.dur(2200)
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: particle
                    property: "x"
                    from: particle.startX
                    to: particle.startX + particle.drift
                    duration: Appearance.dur(2200)
                    easing.type: Easing.OutCubic
                }
                NumberAnimation {
                    target: particle
                    property: "y"
                    from: root.height * 0.28
                    to: root.height * 0.28 + particle.fall
                    duration: Appearance.dur(2200)
                    easing.type: Easing.OutQuad
                }
                NumberAnimation {
                    target: particle
                    property: "rotation"
                    from: particle.rotation
                    to: particle.rotation + (Math.random() > 0.5 ? 540 : -540)
                    duration: Appearance.dur(2200)
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    Rectangle {
        id: banner
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.height * 0.2
        implicitWidth: bannerRow.implicitWidth + GritStyle.gapHuge * 2
        implicitHeight: 64
        radius: GritStyle.pill(64)
        color: GritStyle.colSurfaceHigh
        border.width: 1
        border.color: ColorUtils.applyAlpha(root.colAccent, 0.35)

        RowLayout {
            id: bannerRow
            anchors.centerIn: parent
            spacing: GritStyle.gap

            MaterialShapeWrappedMaterialSymbol {
                text: root.symbol
                iconSize: 20
                padding: 8
                shape: "Flower"
                color: root.colAccent
                colSymbol: ColorUtils.mostReadable(root.colAccent,
                    [GritStyle.colOnPrimary, GritStyle.colBackground])
            }

            StyledText {
                text: root.message
                font.family: GritStyle.fontTitle
                font.variableAxes: GritStyle.axesTitle
                font.pixelSize: Appearance.font.pixelSize.large
                color: GritStyle.colOnSurface
            }
        }

        scale: 0.85
        opacity: 0
        Component.onCompleted: {
            banner.scale = 1;
            banner.opacity = 1;
        }
        Behavior on scale {
            enabled: !GritStyle.reducedMotion
            NumberAnimation {
                duration: GritStyle.motionEnter.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.emphasizedDecel
            }
        }
        Behavior on opacity {
            animation: GritStyle.motionFast.numberAnimation.createObject(this)
        }
    }
}

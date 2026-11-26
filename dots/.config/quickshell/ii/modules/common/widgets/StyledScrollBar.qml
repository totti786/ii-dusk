import QtQuick
import QtQuick.Controls
import qs.modules.common
import qs.modules.common.functions

ScrollBar {
    id: root

    property color thumbColor: Config.options.appearance.colorfulScrollbar ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
    property color trackColor: Qt.rgba(thumbColor.r, thumbColor.g, thumbColor.b, 0.25)
    property real trackGap: 6
    property real barWidth: 6

    policy: ScrollBar.AsNeeded
    topPadding: Appearance.rounding.normal
    bottomPadding: Appearance.rounding.normal
    active: hovered || pressed

    background: Item {
        implicitWidth: root.barWidth
        opacity: root.contentItem.opacity

        // Top track
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.barWidth
            y: root.topPadding
            height: Math.max(0, root.contentItem.y - y - root.trackGap)
            color: root.trackColor
            radius: width / 2
            visible: height > 0
        }

        // Bottom track
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: root.barWidth
            property real startY: root.contentItem.y + root.contentItem.height + root.trackGap
            y: Math.min(root.height - root.bottomPadding, startY)
            height: Math.max(0, root.height - root.bottomPadding - y)
            color: root.trackColor
            radius: width / 2
            visible: height > 0
        }
    }

    contentItem: Item {
        implicitWidth: root.barWidth
        implicitHeight: root.visualSize

        opacity: root.policy === ScrollBar.AlwaysOn || (root.active && root.size < 1.0) ? 0.8 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.dur(350)
                easing.type: Appearance.animation.elementMoveFast.type
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }

        Rectangle {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.bottom: parent.bottom

            width: root.hovered || root.pressed ? root.barWidth * 4 : root.barWidth
            color: root.thumbColor

            // The side against the edge stays small and the side facing the content
            // grows. In a mirrored layout the bar is on the left, so they trade places.
            readonly property real edgeRadius: root.barWidth / 2
            property real innerRadius: root.hovered || root.pressed ? Appearance.rounding.large : root.barWidth / 2
            topRightRadius: LayoutMirroring.enabled ? innerRadius : edgeRadius
            bottomRightRadius: LayoutMirroring.enabled ? innerRadius : edgeRadius
            topLeftRadius: LayoutMirroring.enabled ? edgeRadius : innerRadius
            bottomLeftRadius: LayoutMirroring.enabled ? edgeRadius : innerRadius

            Behavior on width {
                NumberAnimation {
                    duration: Appearance.dur(250)
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on innerRadius {
                NumberAnimation {
                    duration: Appearance.dur(250)
                    easing.type: Easing.OutCubic
                }
            }

            Column {
                anchors.centerIn: parent
                spacing: -4
                opacity: root.hovered || root.pressed ? 1 : 0

                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.dur(200)
                        easing.type: Easing.InOutQuad
                    }
                }

                MaterialSymbol {
                    text: "expand_less"
                    iconSize: 20
                    color: Appearance.colors.colLayer0
                }
                MaterialSymbol {
                    text: "expand_more"
                    iconSize: 20
                    color: Appearance.colors.colLayer0
                }
            }
        }
    }
}

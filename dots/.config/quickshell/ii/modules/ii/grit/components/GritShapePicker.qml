import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.grit.components

/** The expressive shape a tag wears around its icon. */
Item {
    id: root

    property string selected: "Cookie7Sided"
    property color colAccent: GritStyle.colPrimary

    signal picked(string shape)

    implicitHeight: flow.implicitHeight

    Flow {
        id: flow
        width: root.width
        spacing: GritStyle.gapSmall

        Repeater {
            model: GritStyle.shapeNames

            Item {
                id: shapeItem
                required property string modelData
                readonly property bool active: root.selected === shapeItem.modelData

                width: 42
                height: 42

                Rectangle {
                    anchors.fill: parent
                    radius: GritStyle.radiusSmall
                    color: shapeItem.active
                        ? ColorUtils.applyAlpha(root.colAccent, 0.16)
                        : "transparent"
                    border.width: shapeItem.active ? 1 : 0
                    border.color: ColorUtils.applyAlpha(root.colAccent, 0.4)
                }

                Item {
                    anchors.centerIn: parent
                    width: 28
                    height: 28

                    MaterialShape {
                        anchors.fill: parent
                        shapeString: shapeItem.modelData
                        color: shapeItem.active ? root.colAccent : GritStyle.colFieldHover
                        rotation: shapeItem.active ? 18 : 0

                        Behavior on rotation {
                            enabled: !GritStyle.reducedMotion
                            NumberAnimation {
                                duration: GritStyle.motionDefault.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: GritStyle.motionDefault.bezierCurve
                            }
                        }
                    }

                    MaterialSymbol {
                        anchors.centerIn: parent
                        visible: shapeItem.active
                        text: "check"
                        iconSize: 14
                        fill: 1
                        color: ColorUtils.mostReadable(root.colAccent,
                            [GritStyle.colOnPrimary, GritStyle.colBackground])
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(shapeItem.modelData)
                }
            }
        }
    }
}

import QtQuick
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.panadoro.components

/** The expressive shape a tag wears around its icon. */
Item {
    id: root

    property string selected: "Cookie7Sided"
    property color colAccent: PanadoroStyle.colPrimary

    signal picked(string shape)

    implicitHeight: flow.implicitHeight

    Flow {
        id: flow
        width: root.width
        spacing: PanadoroStyle.gapSmall

        Repeater {
            model: PanadoroStyle.shapeNames

            Item {
                id: shapeItem
                required property string modelData
                readonly property bool active: root.selected === shapeItem.modelData

                width: 42
                height: 42

                Rectangle {
                    anchors.fill: parent
                    radius: PanadoroStyle.radiusSmall
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
                        color: shapeItem.active ? root.colAccent : PanadoroStyle.colFieldHover
                        rotation: shapeItem.active ? 18 : 0

                        Behavior on rotation {
                            enabled: !PanadoroStyle.reducedMotion
                            NumberAnimation {
                                duration: PanadoroStyle.motionDefault.duration
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: PanadoroStyle.motionDefault.bezierCurve
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
                            [PanadoroStyle.colOnPrimary, PanadoroStyle.colBackground])
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

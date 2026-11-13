import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    property string highlightedOrigin: "leftEdge"

    readonly property var bindings: (Config.options && Config.options.interactions && Config.options.interactions.touchGestures && Config.options.interactions.touchGestures.bindings)
        ? Config.options.interactions.touchGestures.bindings
        : null

    implicitHeight: 220
    Layout.fillWidth: true
    radius: Appearance.rounding.normal
    color: Appearance.colors.colLayer2

    function actionFor(orig) {
        if (!root.bindings) return null;
        var actId = root.bindings[orig] ? root.bindings[orig] : "none";
        return TouchGestureActionRegistry.actionById(actId);
    }

    Item {
        anchors.centerIn: parent
        width: Math.min(parent.width - 40, 360)
        height: 170

        // Screen frame
        Rectangle {
            id: screenFrame
            anchors.fill: parent
            radius: Appearance.rounding.large
            color: Appearance.colors.colLayer1

            // Screen Content Mockup / Center Label
            ColumnLayout {
                anchors.centerIn: parent
                spacing: 4

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    iconSize: 28
                    text: {
                        var act = root.actionFor(root.highlightedOrigin);
                        return (act && act.icon) ? act.icon : "touch_app";
                    }
                    color: Appearance.m3colors.m3primary
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: {
                        var act = root.actionFor(root.highlightedOrigin);
                        return Translation.tr((act && act.name) ? act.name : "None");
                    }
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer1
                }
            }

            // Top Edge Indicator
            Rectangle {
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.4
                height: 8
                radius: Appearance.rounding.full
                color: root.highlightedOrigin === "topEdge"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Bottom Edge Indicator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width * 0.35
                height: 8
                radius: Appearance.rounding.full
                color: root.highlightedOrigin === "bottomEdge"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Left Edge Indicator
            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: parent.height * 0.45
                radius: Appearance.rounding.full
                color: root.highlightedOrigin === "leftEdge"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Right Edge Indicator
            Rectangle {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: parent.height * 0.45
                radius: Appearance.rounding.full
                color: root.highlightedOrigin === "rightEdge"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Top-Left Corner Indicator
            Rectangle {
                anchors.top: parent.top
                anchors.left: parent.left
                width: 24
                height: 24
                radius: Appearance.rounding.small
                color: root.highlightedOrigin === "topLeftCorner"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Top-Right Corner Indicator
            Rectangle {
                anchors.top: parent.top
                anchors.right: parent.right
                width: 24
                height: 24
                radius: Appearance.rounding.small
                color: root.highlightedOrigin === "topRightCorner"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Bottom-Left Corner Indicator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                width: 24
                height: 24
                radius: Appearance.rounding.small
                color: root.highlightedOrigin === "bottomLeftCorner"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }

            // Bottom-Right Corner Indicator
            Rectangle {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 24
                height: 24
                radius: Appearance.rounding.small
                color: root.highlightedOrigin === "bottomRightCorner"
                    ? Appearance.m3colors.m3primary
                    : Appearance.colors.colLayer3

                Behavior on color { ColorAnimation { duration: Appearance.dur(150) } }
            }
        }
    }
}

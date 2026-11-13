pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common

SequentialAnimation {
    id: root

    required property Item target
    property real distance: 30

    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: -root.distance; duration: Appearance.dur(50) }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: root.distance; duration: Appearance.dur(50) }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: -root.distance / 2; duration: Appearance.dur(40) }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: root.distance / 2; duration: Appearance.dur(40) }
    NumberAnimation { target: root.target; property: "Layout.leftMargin"; to: 0; duration: Appearance.dur(30) }
}

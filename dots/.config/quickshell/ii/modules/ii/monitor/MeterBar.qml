import QtQuick

import qs.modules.common
import qs.modules.ii.clock.components

/// A thin horizontal meter, 0 to 100. Turns the error colour when it is nearly full.
Rectangle {
    id: root

    property real percent: 0
    property color barColor: ClockStyle.colPrimary
    property bool warn: true
    /// Off for bars whose row is reused for another item between samples
    property bool animated: true

    implicitHeight: 8
    radius: height / 2
    color: ClockStyle.colSurfaceHighest

    Rectangle {
        width: Math.max(root.percent > 0 ? root.height : 0, parent.width * Math.min(1, root.percent / 100))
        height: parent.height
        radius: parent.radius
        color: root.warn && root.percent >= 90 ? ClockStyle.colError : root.barColor
        Behavior on width {
            enabled: root.animated && !ClockStyle.reducedMotion
            NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
        }
    }
}

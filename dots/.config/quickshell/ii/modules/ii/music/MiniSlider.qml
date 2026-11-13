import QtQuick

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The music app's slider: the shell's Material 3 Expressive StyledSlider with this app's
 * colours. `wavy` makes it the progress wave (the played part undulates while `animate` is
 * true and settles flat when paused); otherwise it is the thin straight slider used for
 * volume. `moved` fires once, when the handle is let go; `dragValue` follows it meanwhile.
 */
Item {
    id: root

    property real value: 0              // 0 to 1
    property color colFill: ClockStyle.colPrimary
    property color colTrack: ClockStyle.colSurfaceHighest
    property bool wavy: false
    property bool animate: false
    property bool showPercent: false
    readonly property bool dragging: slider.pressed
    readonly property real dragValue: slider.value
    readonly property real shown: Math.max(0, Math.min(1, slider.pressed ? slider.value : root.value))

    signal moved(real value)

    implicitHeight: root.wavy ? 28 : 24

    // The slider writes its own value while dragged, which would break a plain binding.
    Binding {
        target: slider
        property: "value"
        value: root.value
        when: !slider.pressed
    }

    StyledSlider {
        id: slider
        anchors.fill: parent
        configuration: root.wavy ? StyledSlider.Configuration.Wavy : StyledSlider.Configuration.XS
        animateWave: root.wavy && root.animate
        highlightColor: root.colFill
        handleColor: root.colFill
        trackColor: root.colTrack
        usePercentTooltip: root.showPercent
        stopIndicatorValues: []
        onPressedChanged: {
            if (!pressed)
                root.moved(slider.value);
        }
    }
}

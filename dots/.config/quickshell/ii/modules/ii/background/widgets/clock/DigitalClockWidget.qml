import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.ii.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "clock_digital"

    // The clock has no card, so a size class changes how it is set rather than how large its
    // box is: the strip is one small line, the tile stacks small digits, the wide one is a line
    // with the date, and the tall one is the clock as configured (stacked, at its own size).
    supportedSizes: ["2x0.5", "1x1", "2x1", "1x2"]
    defaultSize: "1x2"
    readonly property real sizeScaleFor: root.sizeClass === "2x0.5" ? 0.28 : root.sizeClass === "1x1" ? 0.4 : root.sizeClass === "2x1" ? 0.55 : 1
    readonly property int verticalModeFor: root.sizeClass === "1x2" ? -1 : (root.sizeClass === "1x1" ? 1 : 0)

    implicitHeight: contentColumn.implicitHeight
    implicitWidth: contentColumn.implicitWidth

    property bool wallpaperSafetyTriggered: false

    visibleWhenLocked: root.lockBehavior === "keep" || root.lockBehavior === "custom" || root.lockBehavior === "center" || root.lockBehavior === "lockOnly"
    opacity: {
        if (root.lockBehavior === "lockOnly") return GlobalStates.screenLocked ? 1 : 0;
        if (GlobalStates.screenLocked && !visibleWhenLocked) return 0;
        return 1;
    }

    needsColText: true

    property var textHorizontalAlignment: {
        if (root.forceCenter || !Config.options.background.widgets.clock_digital.adaptiveAlignment || Config.options.background.widgets.clock_digital.vertical)
            return Text.AlignHCenter;
        if (root.x < root.scaledScreenWidth / 3)
            return Text.AlignLeft;
        if (root.x > root.scaledScreenWidth * 2 / 3)
            return Text.AlignRight;
        return Text.AlignHCenter;
    }

    Column {
        id: contentColumn
        anchors.centerIn: parent
        spacing: 10

        DigitalClock {
            textHorizontalAlignment: root.textHorizontalAlignment
            sizeScale: root.sizeScaleFor
            verticalMode: root.verticalModeFor
            forceDate: root.sizeClass === "2x1"
        }
    }
}

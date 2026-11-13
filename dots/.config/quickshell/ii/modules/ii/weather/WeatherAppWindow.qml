pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common

/**
 * The weather app as an ordinary floating window: an xdg toplevel the compositor moves
 * and floats (see hyprland/rules.lua), sized like the shell's other windowed apps.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    // A forecast has more columns than a timer: open wider than the clock, but keep the
    // same family maximum so the window never feels like a second desktop.
    implicitWidth: Math.round(Math.min(1480, Math.max(960, root.screenWidth * 0.86)))
    implicitHeight: Math.round(Math.min(940, Math.max(620, root.screenHeight * 0.82)))
    minimumSize: Qt.size(WeatherStyle.windowMinWidth, WeatherStyle.windowMinHeight)

    title: "ii Weather"
    color: WeatherStyle.colWindow
    visible: GlobalStates.weatherAppOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.weatherAppOpen)
            GlobalStates.weatherAppOpen = false;
    }

    WeatherAppContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}

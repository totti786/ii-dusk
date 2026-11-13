pragma ComponentBehavior: Bound

import QtQuick
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.ii.grit.components

/**
 * Grit as an ordinary application window: an xdg toplevel the compositor moves,
 * floats and centres. It opens at the same family footprint as the other ii apps.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property real screenWidth: root.screen?.width ?? 1920
    readonly property real screenHeight: root.screen?.height ?? 1080

    // The same 900–1500 by 460–700 footprint as the clock family, a little taller
    // because Grit's pages carry a hero, a grid and a footer.
    readonly property real familyWidth: Math.min(1500, Math.max(940, root.screenWidth * 0.9)) + 40
    readonly property real familyHeight: Math.min(780, Math.max(500, root.screenHeight * 0.68)) + 100

    title: "ii Grit"
    implicitWidth: Math.round(Math.min(root.familyWidth, root.screenWidth * 0.95))
    implicitHeight: Math.round(Math.min(root.familyHeight, root.screenHeight * 0.88))
    minimumSize: Qt.size(GritStyle.windowMinWidth, GritStyle.windowMinHeight)

    color: GritStyle.colBackground
    visible: GlobalStates.gritAppOpen && !GlobalStates.screenLocked

    onVisibleChanged: {
        if (!visible && !GlobalStates.screenLocked && GlobalStates.gritAppOpen)
            GlobalStates.gritAppOpen = false;
    }

    GritAppContent {
        anchors.fill: parent
        focus: true
        onCloseRequested: root.closeRequested()
    }
}

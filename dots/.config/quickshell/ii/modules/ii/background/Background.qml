pragma ComponentBehavior: Bound

import qs
import QtQuick
import Quickshell
import qs.modules.common

Scope {
    id: backgroundScope

    /// Passed to every screen's widget surface; see BackgroundWidgetsWindow.canvasOverlay.
    property Component widgetCanvasOverlay: null

    readonly property int widgetSyncVersion: widgetStateManager?.syncVersion ?? 0
    readonly property var widgetStateManager: extras.item ? extras.item.widgetStateManager : null

    Variants {
        id: root
        model: Quickshell.screens

        BackgroundRoot {
            widgetStateManager: backgroundScope.widgetStateManager
        }
    }

    Loader {
        id: extras
        // Keep the actual wallpaper window alive while widgets arrive later.
        active: StartupState.widgetsReady
        source: active ? Qt.resolvedUrl("BackgroundExtras.qml") : ""
        onLoaded: {
            item.canvasOverlay = Qt.binding(() => backgroundScope.widgetCanvasOverlay);
        }
    }
}

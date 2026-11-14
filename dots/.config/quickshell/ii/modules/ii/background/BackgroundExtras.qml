pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import qs.modules.ii.background.compositor
import qs.modules.ii.background.widgets

// Compiled by URL only after the wallpaper and bar have painted.
Scope {
    id: root
    readonly property alias widgetStateManager: widgetState
    property Component canvasOverlay: null

    WidgetStateManager { id: widgetState }

    Variants {
        model: root.widgetStateManager ? Quickshell.screens : []
        BackgroundWidgetsWindow {
            widgetStateManager: root.widgetStateManager
            canvasOverlay: root.canvasOverlay
        }
    }
    Variants {
        model: root.widgetStateManager ? Quickshell.screens : []
        BlurOverlayWindow {}
    }
}

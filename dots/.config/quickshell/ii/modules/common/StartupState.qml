pragma Singleton

import QtQuick
import Quickshell

// Shared by the real desktop windows and the small shell entry point.
Singleton {
    id: root

    readonly property double startedAt: Date.now()
    property bool desktopReady: false
    property bool islandReady: false
    property bool widgetsReady: false
    property var wallpaperScreens: []
    property var barScreens: []

    function wallpaperPainted(name) {
        if (wallpaperScreens.indexOf(name) !== -1) return;
        console.info("[Startup] Wallpaper painted on", name, Date.now() - startedAt, "ms");
        wallpaperScreens = wallpaperScreens.concat([name]);
    }

    function barPainted(name) {
        if (barScreens.indexOf(name) !== -1) return;
        console.info("[Startup] Bar painted on", name, Date.now() - startedAt, "ms");
        barScreens = barScreens.concat([name]);
    }

    function finish() {
        if (desktopReady) return;
        console.info("[Startup] Desktop ready; releasing remaining modules", Date.now() - startedAt, "ms");
        desktopReady = true;
    }

    function islandPainted() {
        if (islandReady) return;
        console.info("[Startup] Dynamic Island painted", Date.now() - startedAt, "ms");
        islandReady = true;
    }

    function releaseWidgets() {
        if (widgetsReady) return;
        console.info("[Startup] Loading desktop widgets last", Date.now() - startedAt, "ms");
        widgetsReady = true;
    }
}

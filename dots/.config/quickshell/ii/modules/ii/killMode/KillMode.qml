pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/**
 * Kill mode: Super+Esc turns a full-screen crosshair on; clicking an app
 * window force-quits it and closes the mode. Escape or a right click leaves
 * without killing anything.
 *
 * Hyprland's own `hyprctl kill` is a one-shot compositor click mode: it cannot
 * be toggled from a bind, has no cursor of its own, and cancels itself when the
 * Escape release that started the bind arrives. This is the shell-owned version
 * instead: the overlay takes the clicks, resolves the window under the pointer
 * and kills its pid, so the mode can stay on and show that it is on.
 */
Scope {
    id: root

    function monitorForPanel(panel): var {
        return Hyprland.monitorFor(panel.screen);
    }

    /// The topmost app window under a point in this panel's coordinates.
    function windowAt(panel, localX, localY): var {
        const monitor = root.monitorForPanel(panel);
        if (!monitor)
            return null;

        const x = monitor.x + localX;
        const y = monitor.y + localY;

        // A shell surface over the point owns the click, not the app behind it.
        // Levels 2/3 are top/overlay; background widgets live below windows.
        const levels = HyprlandData.layers?.[monitor.name]?.levels ?? {};
        const panelArea = panel.width * panel.height;
        for (const level of ["2", "3"]) {
            for (const layer of (levels[level] ?? [])) {
                if (layer?.namespace === "ii-kill-mode")
                    continue;
                // Full-screen shell surfaces (floating island, AI companion,
                // wallpaper helpers) are click-through. Only a bar/dock-sized
                // surface actually owns the click and should block the window
                // behind it.
                if (Number(layer.w) * Number(layer.h) >= panelArea * 0.9)
                    continue;
                if (x >= layer.x && x < layer.x + layer.w
                        && y >= layer.y && y < layer.y + layer.h)
                    return null;
            }
        }

        const activeId = monitor.activeWorkspace?.id ?? -1;
        const specialName = monitor.specialWorkspace?.name ?? "";

        const candidates = HyprlandData.windowList.filter(client => {
            if (client.mapped === false || client.hidden === true || client.acceptsInput === false)
                return false;
            // Never kill the shell itself through its own toplevel (the Files
            // window shares the shell's pid).
            if (/quickshell/i.test(String(client.class ?? "")))
                return false;
            const onSpecial = specialName !== "" && client.workspace?.name === specialName;
            return onSpecial || client.workspace?.id === activeId;
        }).sort((a, b) => {
            // Floating windows sit above tiled ones; among each kind, the most
            // recently focused window is the one in front.
            const floating = Number(b.floating) - Number(a.floating);
            if (floating !== 0)
                return floating;
            return Number(a.focusHistoryID ?? 9999) - Number(b.focusHistoryID ?? 9999);
        });

        return candidates.find(client =>
            x >= client.at[0] && x < client.at[0] + client.size[0]
            && y >= client.at[1] && y < client.at[1] + client.size[1]) ?? null;
    }

    function kill(client): void {
        if (!client)
            return;
        if (Number(client.pid) > 0) {
            Quickshell.execDetached(["/bin/kill", "-KILL", String(client.pid)]);
            return;
        }
        Hyprland.dispatch(`hl.dsp.window.close({ window = "address:${client.address}" })`);
    }

    function setActive(value): void {
        GlobalStates.killModeActive = value;
    }

    GlobalShortcut {
        name: "killModeToggle"
        description: "Toggles the window kill mode"
        onPressed: root.setActive(!GlobalStates.killModeActive)
    }

    IpcHandler {
        target: "killMode"

        function toggle(): void { root.setActive(!GlobalStates.killModeActive); }
        function close(): void { root.setActive(false); }
        function isOpen(): bool { return GlobalStates.killModeActive; }
    }

    Connections {
        target: GlobalStates
        function onKillModeActiveChanged() {
            if (GlobalStates.killModeActive)
                HyprlandData.updateWindowList();
        }
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.setActive(false);
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: window
            required property ShellScreen modelData
            screen: window.modelData

            visible: GlobalStates.killModeActive
            color: "transparent"
            WlrLayershell.namespace: "ii-kill-mode"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            exclusionMode: ExclusionMode.Ignore

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            onVisibleChanged: {
                if (visible)
                    Qt.callLater(() => surface.forceActiveFocus());
            }

            // A faint red wash says the whole desktop is armed.
            Rectangle {
                anchors.fill: parent
                color: Appearance.colors.colError
                opacity: 0.06
            }

            Item {
                id: surface
                anchors.fill: parent
                focus: true

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape && !(event.modifiers & Qt.MetaModifier)) {
                        root.setActive(false);
                        event.accepted = true;
                    }
                }

                MouseArea {
                    id: pointer
                    anchors.fill: parent
                    cursorShape: Qt.CrossCursor
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true

                    onClicked: event => {
                        if (event.button === Qt.RightButton) {
                            root.setActive(false);
                            return;
                        }
                        const client = root.windowAt(window, event.x, event.y);
                        if (client) {
                            root.kill(client);
                            // One kill per activation: the overlay closes so the
                            // next click is an ordinary click again.
                            root.setActive(false);
                        }
                    }
                }

                // The crosshair follows the pointer so the cursor is never the
                // only indication that the mode is armed.
                Item {
                    visible: pointer.containsMouse
                    x: pointer.mouseX - width / 2
                    y: pointer.mouseY - height / 2
                    width: 42
                    height: 42
                    z: 10

                    Rectangle {
                        anchors.centerIn: parent
                        width: 2
                        height: parent.height
                        radius: 1
                        color: Appearance.colors.colError
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: parent.width
                        height: 2
                        radius: 1
                        color: Appearance.colors.colError
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: Appearance.colors.colSurfaceContainer
                        border.width: 2
                        border.color: Appearance.colors.colError
                    }
                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: "dangerous"
                        iconSize: 14
                        color: Appearance.colors.colError
                    }
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: 28
                    width: banner.implicitWidth + 44
                    height: 52
                    radius: 26
                    color: Appearance.colors.colSurfaceContainer
                    border.width: 1
                    border.color: Appearance.colors.colError

                    Row {
                        id: banner
                        anchors.centerIn: parent
                        spacing: 10

                        MaterialSymbol {
                            text: "dangerous"
                            iconSize: 22
                            color: Appearance.colors.colError
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: Translation.tr("Kill mode — click a window to kill it · Esc or right-click to cancel")
                            color: Appearance.colors.colOnSurface
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.normal
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }
        }
    }
}

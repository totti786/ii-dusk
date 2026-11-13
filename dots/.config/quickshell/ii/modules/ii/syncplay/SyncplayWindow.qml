pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Syncplay as a floating window: watch together. The window is only a frontend: the call
 * lives in its own process, so closing this window leaves the room open (the player keeps
 * syncing) and "Leave" is the only thing that ends it.
 */
FloatingWindow {
    id: root

    signal closeRequested()

    readonly property bool inRoom: SyncplayService.linked && SyncplayService.connected

    // Closed by the window manager (Super+Q, the compositor's close): tell the app, or its
    // open flag stays true and "open" does nothing afterwards.
    onVisibleChanged: {
        if (!root.visible)
            root.closeRequested();
    }

    title: "ii Syncplay"
    implicitWidth: 1040
    implicitHeight: 700
    minimumSize: Qt.size(Math.max(ClockStyle.windowMinWidth, 820), 560)
    color: ClockStyle.colBackground

    // Takes the keyboard while the window is open, except where a text field has it.
    Item {
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
            if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
                root.closeRequested();
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Syncplay")
            subtitle: root.inRoom
                ? `${SyncplayService.room} · ${SyncplayService.host}`
                : ""
            onCloseRequested: root.closeRequested()

            ClockButton {
                visible: SyncplayService.linked
                focusPolicy: Qt.NoFocus
                variant: "text"
                symbol: "logout"
                label: root.inRoom ? Translation.tr("Leave room") : Translation.tr("Cancel")
                onClicked: SyncplayService.leave()
            }
        }

        Loader {
            Layout.fillWidth: true
            Layout.fillHeight: true
            sourceComponent: root.inRoom ? roomView : connectView
        }
    }

    Component {
        id: connectView
        SyncplayConnect {}
    }

    Component {
        id: roomView
        SyncplayRoom {}
    }
}

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
    contentItem.LayoutMirroring.enabled: Translation.isRtl
    contentItem.LayoutMirroring.childrenInherit: true
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
                symbol: "sync"
                label: Translation.tr("Recheck")
                onClicked: SyncplayService.recheck()
            }

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

    // The answer to a Recheck, when the room itself looks the same either way.
    Rectangle {
        id: recheckToast
        visible: SyncplayService.recheckNote !== ""
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: ClockStyle.gap * 2
        z: 100
        width: recheckToastText.implicitWidth + 28
        height: recheckToastText.implicitHeight + 14
        radius: Appearance.rounding.full
        color: ClockStyle.colSurfaceHigh
        border.width: 1
        border.color: ClockStyle.colOutline

        StyledText {
            id: recheckToastText
            anchors.centerIn: parent
            text: SyncplayService.recheckNote
            font.pixelSize: ClockStyle.textSmall
            color: SyncplayService.recheckOk ? ClockStyle.colPrimary : ClockStyle.colError
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

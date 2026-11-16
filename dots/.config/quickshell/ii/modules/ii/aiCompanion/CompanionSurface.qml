pragma ComponentBehavior: Bound
import QtQuick

// A single hover owner for the orb, the gaps, and every orbit action.
Item {
    id: root
    width: 208; height: 208
    property bool controlsOpen: false
    property bool dragging: false
    property bool interactionHeld: false
    readonly property Item inputArea: inputArea
    readonly property bool pointerInside: hover.hovered
    onDraggingChanged: { if (dragging) root.controlsOpen = false; }
    onInteractionHeldChanged: {
        if (interactionHeld) closeDelay.stop();
        else if (!hover.hovered) closeDelay.restart();
    }
    Item {
        id: inputArea
        anchors.centerIn: parent
        width: root.controlsOpen ? root.width : 88
        height: root.controlsOpen ? root.height : 88
    }
    HoverHandler {
        id: hover
        enabled: !root.dragging
        blocking: false
        onHoveredChanged: {
            if (hovered) { closeDelay.stop(); root.controlsOpen = true; }
            else closeDelay.restart();
        }
    }
    Timer {
        id: closeDelay
        interval: 320
        onTriggered: {
            if (!hover.hovered && !root.interactionHeld) root.controlsOpen = false;
        }
    }
}

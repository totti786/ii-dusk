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
    // The square is big enough for the orb's buttons, and the kitten sits inside it. Closed, only
    // the orb itself opens the controls; once they are out, anywhere in the square keeps them out.
    function evaluateHover() {
        const near = hover.hovered
            && Math.hypot(hover.point.position.x - root.width / 2, hover.point.position.y - root.height / 2) < 48;
        if (hover.hovered && (near || root.controlsOpen)) { closeDelay.stop(); root.controlsOpen = true; }
        else if (!closeDelay.running) closeDelay.restart();
    }
    HoverHandler {
        id: hover
        enabled: !root.dragging
        blocking: false
        onHoveredChanged: root.evaluateHover()
        onPointChanged: if (!root.controlsOpen) root.evaluateHover()
    }
    Timer {
        id: closeDelay
        interval: 320
        onTriggered: {
            if (!hover.hovered && !root.interactionHeld) root.controlsOpen = false;
        }
    }
}

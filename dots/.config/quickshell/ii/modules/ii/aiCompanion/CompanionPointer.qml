pragma ComponentBehavior: Bound
import QtQuick

// Measure in the stationary window, even while the grabbed item morphs or moves.
Item {
    id: root
    property Item orbAnchor: root
    readonly property bool pressed: tap.pressed || drag.active
    readonly property bool containsMouse: hover.hovered
    property point pressPoint
    property point centerPoint
    property bool didDrag: false
    signal activated(bool rightButton)
    signal dragStarted(point pointer, point center)
    signal dragMoved(point pointer)
    signal dragFinished()
    signal dragCancelled()
    function globalPoint(scenePoint): point {
        return root.mapToGlobal(root.mapFromItem(null, scenePoint));
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressedChanged: {
            if (pressed) {
                root.didDrag = false;
                root.pressPoint = root.globalPoint(point.scenePressPosition);
                root.centerPoint = root.orbAnchor.mapToGlobal(root.orbAnchor.width/2, root.orbAnchor.height/2);
            }
        }
        onTapped: (point, button) => {
            if (!root.didDrag) root.activated(button === Qt.RightButton);
        }
    }
    DragHandler {
        id: drag
        target: null
        acceptedButtons: Qt.LeftButton
        dragThreshold: 3
        cursorShape: Qt.ClosedHandCursor
        onActiveChanged: {
            if (active) {
                root.didDrag = true;
                root.dragStarted(root.pressPoint, root.centerPoint);
                root.dragMoved(root.globalPoint(centroid.scenePosition));
            } else root.dragFinished();
        }
        onCentroidChanged: {
            if (active) root.dragMoved(root.globalPoint(centroid.scenePosition));
        }
        onCanceled: root.dragCancelled()
    }
}

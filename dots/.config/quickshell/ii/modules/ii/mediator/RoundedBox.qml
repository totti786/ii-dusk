import QtQuick
import Quickshell.Widgets

/**
 * A filled rounded rectangle that clips its children to the rounded shape (Rectangle.clip only
 * clips to the box). One pass in the scene graph, no offscreen layer per instance, which matters
 * with a grid of posters. Draw selection rings as a sibling above it, not inside.
 */
ClippingRectangle {
    color: "transparent"
}

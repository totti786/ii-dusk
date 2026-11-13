pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Qt5Compat.GraphicalEffects
import qs.modules.common
import qs.modules.common.widgets

// Data-only counterpart to RingMedia's scalloped progress rim. It deliberately
// contains no MPRIS access, so other live players can provide their own progress.
Item {
    id: root

    property real diameter: 48
    property real progress: 0
    property real chromeOpacity: 1
    // The native anime glance can provide the saved poster without coupling
    // this reusable visual to MediatorService. Keeping the art inside the rim
    // is important: the progress mask is a wedge, not a complete badge.
    property string artSource: ""
    property string icon: "movie"
    property color primaryColor: Appearance.colors.colPrimary
    property color iconColor: Appearance.colors.colOnPrimaryContainer

    readonly property Item ringItem: ringSlot
    readonly property Item artItem: artSlot
    readonly property real sweepStep: root.diameter > 0
        ? 1 / (Math.PI * root.diameter) : 0
    readonly property real sweepProgress: root.sweepStep > 0
        ? Math.min(1, Math.round(root.progress / root.sweepStep) * root.sweepStep)
        : root.progress

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    Item {
        id: ringSlot
        anchors.fill: parent

        MaterialShape {
            anchors.centerIn: parent
            implicitSize: root.diameter
            shape: MaterialShape.Shape.Cookie9Sided
            color: root.primaryColor
            opacity: 0.22 * root.chromeOpacity
        }

        Item {
            id: rimInk
            anchors.fill: parent
            visible: false

            MaterialShape {
                anchors.centerIn: parent
                implicitSize: root.diameter
                shape: MaterialShape.Shape.Cookie9Sided
                color: root.primaryColor
            }
        }

        Item {
            id: sweepMask
            anchors.fill: parent
            visible: false

            Loader {
                anchors.fill: parent
                active: Boolean(sweepMask.Window.window)
                sourceComponent: ConicalGradient {
                    angle: 270
                    gradient: Gradient {
                        GradientStop { position: 0; color: "white" }
                        GradientStop {
                            position: Math.max(0.0001, root.sweepProgress)
                            color: "white"
                        }
                        GradientStop {
                            position: Math.min(1, Math.max(0.0001, root.sweepProgress) + 0.0001)
                            color: "transparent"
                        }
                        GradientStop { position: 1; color: "transparent" }
                    }
                }
            }
        }

        OpacityMask {
            anchors.fill: parent
            opacity: root.chromeOpacity
            source: rimInk
            maskSource: sweepMask
        }

        // Keep the center opaque so the swept rim remains a rim. The previous
        // native-only copy omitted this layer, which let the wedge paint through
        // the glyph and produced the stray light sliver beside it.
        Item {
            id: artSlot
            anchors.centerIn: parent
            width: Math.max(1, root.diameter - Math.max(3, Math.round(root.diameter * 0.11)) * 2)
            height: width

            MaterialShape {
                anchors.fill: parent
                shape: MaterialShape.Shape.Cookie9Sided
                color: Appearance.colors.colSecondaryContainer
            }

            Image {
                id: artImage
                anchors.fill: parent
                source: root.artSource
                visible: root.artSource !== "" && status === Image.Ready
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                sourceSize.width: artSlot.width * 2
                sourceSize.height: artSlot.height * 2

                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: MaterialShape {
                        width: artSlot.width
                        height: artSlot.height
                        shape: MaterialShape.Shape.Cookie9Sided
                    }
                }
            }

            MaterialSymbol {
                anchors.centerIn: parent
                visible: !artImage.visible
                text: root.icon
                fill: 1
                iconSize: Math.round(root.diameter * 0.36)
                color: root.iconColor
            }
        }
    }
}

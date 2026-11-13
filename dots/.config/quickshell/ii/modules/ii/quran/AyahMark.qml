import QtQuick
import QtQuick.Shapes
import "RosettePaths.js" as Rosette

/// The ayah rosette with the number inside, drawn as vector paths so it takes the theme colours
/// and costs almost nothing (image layers with an effect each took seconds to build a page). It
/// takes the advance width of the `﴿n﴾` token it replaces so justification holds.
Item {
    id: root

    property string digits: ""
    property real markWidth: 40
    property string fontFamily: ""
    property color accentColor: "#f4e9bc"
    property real accentStrength: 0.16
    property color inkColor: "#083a3a"
    property color numberColor: inkColor

    // viewBox 1312.98 x 1229.38 from (-70.338, -310.688); number box centre (586.2, 291.2)
    width: markWidth
    height: markWidth * 1229.38 / 1312.98

    Item {
        width: 1312.98
        height: 1229.38
        scale: root.markWidth / 1312.98
        transformOrigin: Item.TopLeft

        Shape {
            x: 70.338
            y: 310.688
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: Qt.alpha(root.accentColor, root.accentStrength)
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathSvg { path: Rosette.accent }
            }
            ShapePath {
                fillColor: root.inkColor
                strokeColor: "transparent"
                fillRule: ShapePath.OddEvenFill
                PathSvg { path: Rosette.ink }
            }
        }
    }

    Text {
        x: root.width * 0.5 - width / 2
        y: root.height * 0.4896 - height / 2
        text: root.digits
        font.family: root.fontFamily
        font.pixelSize: root.width * 350 / 1312.98
        color: root.numberColor
        renderType: Text.QtRendering
    }
}

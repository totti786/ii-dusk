import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/// A big number with a caption and a glyph, on a tinted tile.
Rectangle {
    id: root

    property string symbol: ""
    property string value: ""
    /// A number counts up to its value; a text value is shown as it is
    property real target: NaN
    property real shown: 0
    readonly property string text: isNaN(root.target) ? root.value : Math.round(root.shown).toLocaleString(Qt.locale(), "f", 0)
    onTargetChanged: if (!isNaN(root.target)) root.shown = root.target
    Component.onCompleted: if (!isNaN(root.target)) root.shown = root.target
    Behavior on shown { NumberAnimation { duration: 1100; easing.type: Easing.OutExpo } }
    property string caption: ""
    property string hint: ""
    property color tone: Appearance.colors.colPrimary
    property color container: Appearance.colors.colPrimaryContainer
    property color onContainer: Appearance.colors.colOnPrimaryContainer

    implicitHeight: 104
    radius: 26
    color: root.container

    MaterialSymbol {
        anchors { right: parent.right; top: parent.top; margins: 14 }
        text: root.symbol
        iconSize: 22
        fill: 1
        color: root.onContainer
        opacity: 0.7
    }
    ColumnLayout {
        anchors { left: parent.left; bottom: parent.bottom; margins: 16 }
        spacing: -2
        StyledText {
            text: root.text
            font.pixelSize: 34
            font.weight: Font.Bold
            font.family: Appearance.font.family.title
            color: root.onContainer
        }
        StyledText {
            text: root.caption
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.onContainer
            opacity: 0.8
        }
    }
    StyledText {
        visible: root.hint !== ""
        anchors { right: parent.right; bottom: parent.bottom; margins: 14 }
        text: root.hint
        font.pixelSize: Appearance.font.pixelSize.smallest
        color: root.onContainer
        opacity: 0.65
    }
}

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

/// A shortcut as keycaps. The Overlays page uses it on app cards and on rows alike so a
/// shortcut reads the same wherever it is shown.
RowLayout {
    id: root
    property var keys: []
    spacing: 4
    visible: root.keys.length > 0

    Repeater {
        model: root.keys
        delegate: Rectangle {
            required property string modelData
            implicitHeight: 26
            implicitWidth: Math.max(26, keyText.implicitWidth + 14)
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colSurfaceContainerHighest
            StyledText {
                id: keyText
                anchors.centerIn: parent
                text: parent.modelData
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.Bold
                color: Appearance.colors.colOnSurface
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * A quiet label/value row for metadata. The label is allowed to take the space; the
 * value never wraps, so coordinates and provider names stay copyable at a glance.
 */
RowLayout {
    id: root

    property string label: ""
    property string value: ""
    property string icon: ""

    Layout.fillWidth: true
    spacing: WeatherStyle.gapSmall

    MaterialSymbol {
        visible: root.icon.length > 0
        Layout.alignment: Qt.AlignVCenter
        text: root.icon
        iconSize: 15
        color: WeatherStyle.colSubtext
    }

    StyledText {
        Layout.fillWidth: true
        text: root.label
        font.pixelSize: WeatherStyle.textTiny
        color: WeatherStyle.colSubtext
        elide: Text.ElideRight
    }

    StyledText {
        Layout.maximumWidth: 420
        text: root.value
        font.pixelSize: WeatherStyle.textTiny
        font.weight: Font.Medium
        color: WeatherStyle.colOnSurfaceVariant
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
    }
}

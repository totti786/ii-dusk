import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * A label/description pair with one control on the right. On a narrow column the
 * control still owns the right edge, which is the familiar settings-row rhythm.
 */
RowLayout {
    id: root

    property string label: ""
    property string description: ""

    Layout.fillWidth: true
    spacing: WeatherStyle.gap

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 1

        StyledText {
            Layout.fillWidth: true
            text: root.label
            font.pixelSize: WeatherStyle.textSmall
            font.weight: Font.Medium
            color: WeatherStyle.colOnSurface
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.description.length > 0
            text: root.description
            font.pixelSize: WeatherStyle.textTiny
            color: WeatherStyle.colSubtext
            wrapMode: Text.Wrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    Item {
        id: slot
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    default property alias contentData: slot.data
}

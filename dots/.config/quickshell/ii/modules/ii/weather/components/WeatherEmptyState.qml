import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * The one thing the app can say before it has weather: what it is doing, why it is not
 * doing it, and the next useful action.
 */
Item {
    id: root

    property string icon: "cloud"
    property string title: ""
    property string message: ""
    property bool busy: false
    default property alias actions: actionRow.data

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 440)
        spacing: WeatherStyle.gap

        Rectangle {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 76
            implicitHeight: 76
            radius: WeatherStyle.radiusFull
            color: WeatherStyle.alpha(WeatherStyle.colPrimary, 0.12)

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.icon
                iconSize: 36
                fill: 1
                color: WeatherStyle.colPrimary
                RotationAnimation on rotation {
                    running: root.busy
                    from: 0
                    to: 360
                    duration: 1600
                    loops: Animation.Infinite
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.title
            font.family: WeatherStyle.fontTitle
            font.variableAxes: WeatherStyle.axesTitle
            font.pixelSize: WeatherStyle.textLarge
            color: WeatherStyle.colOnSurface
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.message
            font.pixelSize: WeatherStyle.textSmall
            color: WeatherStyle.colSubtext
            wrapMode: Text.Wrap
        }

        RowLayout {
            id: actionRow
            Layout.alignment: Qt.AlignHCenter
            spacing: WeatherStyle.gapSmall
        }
    }
}

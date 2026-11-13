import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * The location sheet that slides in from the right. It sits beside the page instead of
 * covering it, so the weather stays visible while you search.
 */
Rectangle {
    id: root

    signal closeRequested()

    implicitWidth: WeatherStyle.sheetWidth
    radius: WeatherStyle.radiusCard
    color: WeatherStyle.colPane

    ColumnLayout {
        anchors {
            fill: parent
            margins: WeatherStyle.panePadding + 4
        }
        spacing: WeatherStyle.gap

        RowLayout {
            Layout.fillWidth: true
            spacing: WeatherStyle.gapSmall

            MaterialSymbol {
                text: "location_on"
                iconSize: 20
                fill: 1
                color: WeatherStyle.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: "Location"
                font.family: WeatherStyle.fontTitle
                font.variableAxes: WeatherStyle.axesTitle
                font.pixelSize: WeatherStyle.textLarge
                color: WeatherStyle.colOnSurface
            }

            WeatherIconButton {
                symbol: "close"
                tooltip: "Close location"
                size: 36
                iconSize: 18
                onClicked: root.closeRequested()
            }
        }

        Flickable {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: manager.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.VerticalFlick

            ScrollBar.vertical: StyledScrollBar {
                policy: ScrollBar.AsNeeded
            }

            WeatherLocationManager {
                id: manager
                width: parent.width
                autoFocusSearch: true
                onLocationChosen: root.closeRequested()
            }
        }
    }
}

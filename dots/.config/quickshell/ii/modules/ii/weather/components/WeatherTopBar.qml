import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * The app bar: rail toggle, page title, page actions and close.
 */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: false
    property bool showRailToggle: false
    property bool railExpanded: true
    property bool showClose: true
    property real subtitleOpacity: 1
    default property alias actions: actionRow.data

    signal backRequested()
    signal railToggled()
    signal closeRequested()

    implicitHeight: WeatherStyle.topBarHeight

    RowLayout {
        anchors {
            fill: parent
            leftMargin: WeatherStyle.gapTiny
            rightMargin: WeatherStyle.gapTiny
        }
        spacing: WeatherStyle.gapSmall

        WeatherIconButton {
            visible: root.showBack
            symbol: "arrow_back"
            tooltip: "Back"
            onClicked: root.backRequested()
        }

        WeatherIconButton {
            visible: root.showRailToggle && !root.showBack
            symbol: root.railExpanded ? "menu_open" : "menu"
            tooltip: root.railExpanded ? "Collapse navigation" : "Expand navigation"
            onClicked: root.railToggled()
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: WeatherStyle.gapTiny
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: WeatherStyle.fontTitle
                font.variableAxes: WeatherStyle.axesTitle
                font.pixelSize: WeatherStyle.textTitle + 4
                color: WeatherStyle.colOnBackground
                animateChange: !WeatherStyle.reducedMotion
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                opacity: root.subtitleOpacity
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: WeatherStyle.textTiny
                color: WeatherStyle.colSubtext
            }
        }

        RowLayout {
            id: actionRow
            spacing: WeatherStyle.gapTiny
        }

        WeatherIconButton {
            visible: root.showClose
            symbol: "close"
            tooltip: "Close weather"
            onClicked: root.closeRequested()
        }
    }
}

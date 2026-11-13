import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * Round icon button used in the app bar, rail and cards.
 */
RippleButton {
    id: root

    property string symbol: "circle"
    property string tooltip: ""
    property real size: WeatherStyle.iconButton
    property real iconSize: WeatherStyle.iconNormal
    property bool filled: false
    property bool selected: false
    property color colIcon: root.selected ? WeatherStyle.colOnPrimary : WeatherStyle.colOnSurfaceVariant

    implicitWidth: root.size
    implicitHeight: root.size
    buttonRadius: WeatherStyle.pill(root.size)
    buttonRadiusPressed: WeatherStyle.radiusSmall
    colBackground: "transparent"
    colBackgroundHover: WeatherStyle.colSurfaceHover
    colBackgroundActive: WeatherStyle.colSurfaceActive
    colBackgroundToggled: WeatherStyle.colPrimary
    colBackgroundToggledHover: WeatherStyle.colPrimaryHover
    colBackgroundToggledActive: WeatherStyle.colPrimaryActive
    toggled: root.selected
    Accessible.name: root.tooltip.length > 0 ? root.tooltip : root.symbol

    contentItem: Item {
        MaterialSymbol {
            anchors.centerIn: parent
            text: root.symbol
            iconSize: root.iconSize
            fill: root.filled || root.selected ? 1 : 0
            color: root.colIcon

            Behavior on color {
                animation: WeatherStyle.motionFast.colorAnimation.createObject(this)
            }
        }
    }

    StyledToolTip {
        text: root.tooltip
        extraVisibleCondition: root.tooltip.length > 0
    }
}

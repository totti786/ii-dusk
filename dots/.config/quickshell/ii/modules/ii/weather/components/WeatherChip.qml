import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * Pill control for filters, units and provider models. Selected is a real state, not
 * just a stronger hover, so it survives the mouse leaving.
 */
RippleButton {
    id: root

    property string label: ""
    property string iconName: ""
    property bool selected: false
    property bool compact: false

    signal triggered()

    implicitHeight: root.compact ? 30 : WeatherStyle.chipHeight
    leftPadding: root.compact ? 11 : 15
    rightPadding: root.compact ? 11 : 15
    topPadding: 0
    bottomPadding: 0
    buttonRadius: WeatherStyle.pill(root.height)
    buttonRadiusPressed: WeatherStyle.radiusNormal
    toggled: root.selected
    colBackground: WeatherStyle.colSurfaceHigh
    colBackgroundHover: WeatherStyle.colSurfaceHover
    colBackgroundActive: WeatherStyle.colSurfaceActive
    colBackgroundToggled: WeatherStyle.colSecondaryContainer
    colBackgroundToggledHover: WeatherStyle.colSecondaryContainerHover
    colBackgroundToggledActive: WeatherStyle.colSecondaryContainerActive
    colRipple: WeatherStyle.colPrimaryActive
    onClicked: root.triggered()
    Accessible.name: root.label

    contentItem: RowLayout {
        spacing: 6

        MaterialSymbol {
            visible: root.iconName.length > 0
            Layout.alignment: Qt.AlignVCenter
            text: root.iconName
            iconSize: root.compact ? 15 : 17
            fill: root.selected ? 1 : 0
            color: root.selected ? WeatherStyle.colOnSecondaryContainer : WeatherStyle.colOnSurfaceVariant
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            text: root.label
            font.pixelSize: root.compact ? WeatherStyle.textTiny : WeatherStyle.textSmall
            font.weight: root.selected ? Font.DemiBold : Font.Medium
            color: root.selected ? WeatherStyle.colOnSecondaryContainer : WeatherStyle.colOnSurfaceVariant
        }
    }

    scale: root.down ? 0.96 : (root.hovered ? 1.015 : 1)
    Behavior on scale {
        animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
    }
}

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * One destination in the weather rail, shaped as a group like the clock and notes rails.
 */
RippleButton {
    id: root

    property bool expanded: true
    property string symbol: "circle"
    property string label: ""
    property string badge: ""
    property bool current: false
    property bool isFirst: false
    property bool isLast: false
    property bool prevIsCurrent: false
    property bool nextIsCurrent: false

    signal triggered()

    implicitHeight: WeatherStyle.railRowHeight
    padding: 0
    toggled: root.current
    colBackground: WeatherStyle.colPane
    colBackgroundHover: WeatherStyle.colPaneHover
    colBackgroundActive: WeatherStyle.colPaneActive
    colBackgroundToggled: WeatherStyle.colPrimary
    colBackgroundToggledHover: WeatherStyle.colPrimaryHover
    colBackgroundToggledActive: WeatherStyle.colPrimaryActive
    onClicked: root.triggered()

    scale: root.down ? 0.96 : (root.hovered ? 1.012 : 1)
    Behavior on scale {
        animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
    }

    readonly property real pillRadius: WeatherStyle.pill(root.implicitHeight)
    readonly property real joinRadius: Appearance.rounding.verysmall
    readonly property bool topIsPill: root.current || root.down || root.prevIsCurrent
    readonly property bool bottomIsPill: root.current || root.down || root.nextIsCurrent

    topLeftRadius: root.topIsPill ? root.pillRadius : (root.isFirst ? WeatherStyle.radiusLarge : root.joinRadius)
    topRightRadius: root.topLeftRadius
    bottomLeftRadius: root.bottomIsPill ? root.pillRadius : (root.isLast ? WeatherStyle.radiusLarge : root.joinRadius)
    bottomRightRadius: root.bottomLeftRadius

    Behavior on topLeftRadius {
        animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
    }
    Behavior on bottomLeftRadius {
        animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
    }

    readonly property color colText: root.current ? WeatherStyle.colOnPrimary : WeatherStyle.colOnSurfaceVariant

    contentItem: Item {
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: root.expanded ? 18 : 0
            anchors.rightMargin: root.expanded ? 12 : 0
            spacing: 12

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter
                Layout.fillWidth: !root.expanded
                horizontalAlignment: Text.AlignHCenter
                text: root.symbol
                iconSize: WeatherStyle.iconLarge
                fill: root.current ? 1 : 0
                color: root.colText

                Behavior on fill {
                    animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: root.expanded
                text: root.label
                elide: Text.ElideRight
                font.pixelSize: WeatherStyle.textNormal
                font.weight: root.current ? Font.DemiBold : Font.Normal
                color: root.colText
            }

            Rectangle {
                Layout.alignment: Qt.AlignVCenter
                visible: root.expanded && root.badge.length > 0
                implicitWidth: Math.max(24, badgeText.implicitWidth + 12)
                implicitHeight: 23
                radius: WeatherStyle.radiusFull
                color: root.current
                    ? WeatherStyle.alpha(WeatherStyle.colOnPrimary, 0.18)
                    : WeatherStyle.colSecondaryContainer

                StyledText {
                    id: badgeText
                    anchors.centerIn: parent
                    text: root.badge
                    font.pixelSize: WeatherStyle.textTiny
                    font.weight: Font.Bold
                    color: root.current ? WeatherStyle.colOnPrimary : WeatherStyle.colOnSecondaryContainer
                }
            }
        }

        Rectangle {
            visible: !root.expanded && root.badge.length > 0
            width: 8
            height: 8
            radius: 4
            x: parent.width / 2 + 10
            y: parent.height / 2 - 14
            color: root.current ? WeatherStyle.colOnPrimary : WeatherStyle.colPrimary
        }
    }

    StyledToolTip {
        text: root.label
        extraVisibleCondition: !root.expanded
    }
}

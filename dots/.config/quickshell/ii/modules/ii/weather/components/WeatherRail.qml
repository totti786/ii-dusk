pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * Weather destinations. The rail is the app's map; Settings is the only thing at its
 * foot because it is not a forecast page.
 */
Item {
    id: root

    property var tabs: []
    property string currentTab: ""
    property bool expanded: true
    property bool settingsOpen: false
    property bool showSettings: true
    property var badges: ({})

    signal selected(string tabId)
    signal settingsRequested()

    clip: true

    Rectangle {
        anchors.fill: parent
        radius: WeatherStyle.radiusLarge
        color: WeatherStyle.colPane
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: WeatherStyle.panePadding
        }
        spacing: 0

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            spacing: 2

            Repeater {
                model: root.tabs

                WeatherRailItem {
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    expanded: root.expanded
                    symbol: modelData.icon
                    label: modelData.label
                    badge: String(root.badges?.[modelData.id] ?? "")
                    current: !root.settingsOpen && root.currentTab === modelData.id
                    isFirst: index === 0
                    isLast: index === root.tabs.length - 1
                    prevIsCurrent: !root.settingsOpen && index > 0 && root.currentTab === root.tabs[index - 1]?.id
                    nextIsCurrent: !root.settingsOpen && index < root.tabs.length - 1 && root.currentTab === root.tabs[index + 1]?.id
                    onTriggered: root.selected(modelData.id)
                }
            }
        }

        Item { Layout.fillHeight: true }

        RippleButton {
            id: settingsButton
            visible: root.showSettings
            Layout.fillWidth: true
            Layout.leftMargin: 4
            Layout.rightMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: WeatherStyle.railRowHeight
            buttonRadius: Math.min(WeatherStyle.railRowHeight / 2, WeatherStyle.radiusLarge)
            toggled: root.settingsOpen
            colBackground: WeatherStyle.colSecondaryContainer
            colBackgroundHover: WeatherStyle.colSecondaryContainerHover
            colBackgroundActive: WeatherStyle.colSecondaryContainerActive
            colBackgroundToggled: WeatherStyle.colPrimary
            colBackgroundToggledHover: WeatherStyle.colPrimaryHover
            colBackgroundToggledActive: WeatherStyle.colPrimaryActive
            colRipple: WeatherStyle.colPrimaryActive
            onClicked: root.settingsRequested()

            scale: settingsButton.down ? 0.96 : (settingsButton.hovered ? 1.012 : 1)
            Behavior on scale {
                animation: WeatherStyle.motionFast.numberAnimation.createObject(this)
            }

            contentItem: Item {
                RowLayout {
                    anchors.centerIn: parent
                    spacing: 10

                    MaterialSymbol {
                        text: "settings"
                        iconSize: WeatherStyle.iconLarge
                        fill: root.settingsOpen ? 1 : 0
                        color: root.settingsOpen ? WeatherStyle.colOnPrimary : WeatherStyle.colOnSecondaryContainer
                        rotation: settingsButton.hovered ? 45 : 0

                        Behavior on rotation {
                            animation: WeatherStyle.motionSpatial.numberAnimation.createObject(this)
                        }
                    }

                    StyledText {
                        visible: root.expanded
                        text: "Settings"
                        font.pixelSize: WeatherStyle.textNormal
                        font.weight: Font.DemiBold
                        color: root.settingsOpen ? WeatherStyle.colOnPrimary : WeatherStyle.colOnSecondaryContainer
                    }
                }
            }

            StyledToolTip {
                text: "Weather settings"
                extraVisibleCondition: !root.expanded
            }
        }
    }
}

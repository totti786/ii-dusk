pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * The bottom navigation a narrow weather window falls back to when the rail no longer
 * fits. Same destinations, active pill and icon carry the state.
 */
Rectangle {
    id: root

    property var tabs: []
    property string currentTab: ""

    signal selected(string tabId)

    implicitHeight: 66
    radius: WeatherStyle.radiusLarge
    color: WeatherStyle.colPane

    RowLayout {
        anchors {
            fill: parent
            topMargin: WeatherStyle.gapSmall
            bottomMargin: WeatherStyle.gapTiny
        }
        spacing: 0

        Repeater {
            model: root.tabs

            Item {
                id: navItem
                required property var modelData
                readonly property bool active: root.currentTab === navItem.modelData.id

                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2

                    RippleButton {
                        id: indicator
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: navItem.active ? 52 : 38
                        implicitHeight: 30
                        buttonRadius: WeatherStyle.pill(30)
                        colBackground: navItem.active ? WeatherStyle.colSecondaryContainer : "transparent"
                        colBackgroundHover: navItem.active ? WeatherStyle.colSecondaryContainerHover : WeatherStyle.colSurfaceHover
                        colRipple: WeatherStyle.colSecondaryContainerActive
                        onClicked: root.selected(navItem.modelData.id)

                        Behavior on implicitWidth {
                            animation: WeatherStyle.motionSpatial.numberAnimation.createObject(this)
                        }

                        contentItem: Item {
                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: navItem.modelData.icon
                                iconSize: 18
                                fill: navItem.active ? 1 : 0
                                color: navItem.active ? WeatherStyle.colOnSecondaryContainer : WeatherStyle.colOnSurfaceVariant
                            }
                        }
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: navItem.width - 4
                        text: navItem.modelData.label
                        elide: Text.ElideRight
                        font.pixelSize: WeatherStyle.textTiny
                        font.weight: navItem.active ? Font.DemiBold : Font.Medium
                        color: navItem.active ? WeatherStyle.colOnSurface : WeatherStyle.colOnSurfaceVariant
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.selected(navItem.modelData.id)
                }
            }
        }
    }
}

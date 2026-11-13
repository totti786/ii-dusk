pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * One keyless weather source. Selecting it is one click; there is no key dialog to
 * forget which provider it belongs to.
 */
Rectangle {
    id: root

    property var provider: ({})
    property bool selected: false

    signal chosen()

    Layout.fillWidth: true
    implicitHeight: content.implicitHeight + 20
    radius: WeatherStyle.radiusTile
    color: root.selected
        ? WeatherStyle.alpha(WeatherStyle.colPrimary, 0.10)
        : WeatherStyle.colSurfaceHigh
    border.width: 1
    border.color: root.selected
        ? WeatherStyle.alpha(WeatherStyle.colPrimary, 0.32)
        : WeatherStyle.alpha(WeatherStyle.colOutline, 0.25)

    readonly property var badges: {
        const items = [];
        if (root.provider.supportsMinutely)
            items.push("Minutely");
        if (root.provider.region && root.provider.region !== "Worldwide")
            items.push(root.provider.region);
        return items;
    }


    ColumnLayout {
        id: content
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 10
        }
        spacing: 8

        RippleButton {
            Layout.fillWidth: true
            implicitHeight: 82
            leftPadding: 8
            rightPadding: 8
            buttonRadius: WeatherStyle.radiusTile
            colBackground: "transparent"
            colBackgroundHover: WeatherStyle.colSurfaceHover
            colBackgroundActive: WeatherStyle.colSurfaceActive
            onClicked: {
                WeatherAppService.setProvider(root.provider.id);
                root.chosen();
            }

            contentItem: RowLayout {
                spacing: WeatherStyle.gapSmall

                Rectangle {
                    implicitWidth: 38
                    implicitHeight: 38
                    radius: WeatherStyle.radiusFull
                    color: root.selected
                        ? WeatherStyle.alpha(WeatherStyle.colPrimary, 0.16)
                        : WeatherStyle.colSurfaceHighest

                    MaterialSymbol {
                        anchors.centerIn: parent
                        text: WeatherStyle.providerIcon(root.provider.id)
                        iconSize: 20
                        fill: root.selected ? 1 : 0
                        color: root.selected ? WeatherStyle.colPrimary : WeatherStyle.colOnSurfaceVariant
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        StyledText {
                            text: root.provider.name
                            font.pixelSize: WeatherStyle.textSmall
                            font.weight: Font.DemiBold
                            color: WeatherStyle.colOnSurface
                            elide: Text.ElideRight
                        }

                        Repeater {
                            model: root.badges

                            Rectangle {
                                required property var modelData
                                implicitWidth: badgeLabel.implicitWidth + 10
                                implicitHeight: 18
                                radius: WeatherStyle.radiusFull
                                color: WeatherStyle.colSurfaceHighest

                                StyledText {
                                    id: badgeLabel
                                    anchors.centerIn: parent
                                    text: modelData
                                    font.pixelSize: 9
                                    color: WeatherStyle.colSubtext
                                }
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.provider.description
                        font.pixelSize: WeatherStyle.textTiny
                        color: WeatherStyle.colSubtext
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                MaterialSymbol {
                    text: root.selected ? "check_circle" : "radio_button_unchecked"
                    iconSize: 20
                    fill: root.selected ? 1 : 0
                    color: root.selected ? WeatherStyle.colPrimary : WeatherStyle.colSubtext
                }
            }
        }

    }
}

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * The next hours as one horizontal run. It is a Flickable, not a carousel: the row is
 * the data, and the user decides how much of it to see.
 */
Item {
    id: root

    property var hours: []
    property var units: ({})
    property int offset: 0
    property bool use24h: true
    property int maxItems: 24

    implicitHeight: 176
    clip: true

    readonly property var shown: (root.hours || []).slice(0, root.maxItems)

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: row.implicitWidth
        contentHeight: height
        flickableDirection: Flickable.HorizontalFlick
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        pressDelay: 80

        Row {
            id: row
            height: flick.height
            spacing: WeatherStyle.gapSmall

            Repeater {
                model: root.shown

                Rectangle {
                    id: card
                    required property var modelData
                    required property int index

                    width: WeatherStyle.hourlyCardWidth + 6
                    height: root.implicitHeight - 8
                    radius: WeatherStyle.radiusTile
                    readonly property bool now: card.index === 0
                    color: card.now ? WeatherStyle.colPrimaryContainer : WeatherStyle.colSurfaceHigh

                    ColumnLayout {
                        anchors {
                            fill: parent
                            margins: 9
                        }
                        spacing: 2

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: card.index === 0
                                ? "Now"
                                : Logic.formatHour(card.modelData.time, root.offset, root.use24h)
                            font.pixelSize: WeatherStyle.textSmall
                            font.weight: card.now ? Font.Bold : Font.Medium
                            color: card.now ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colOnSurfaceVariant
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 42

                            WeatherIcon {
                                anchors.centerIn: parent
                                iconSize: 40
                                code: card.modelData.condition
                                isDay: card.modelData.isDay !== false
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            text: Logic.formatTemperature(card.modelData.tempC, root.units)
                            font.family: WeatherStyle.fontNumbers
                            font.pixelSize: 22
                            font.weight: Font.DemiBold
                            font.variableAxes: WeatherStyle.axesDigits
                            color: card.now ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colOnSurface
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 2

                            MaterialSymbol {
                                text: "water_drop"
                                iconSize: 12
                                fill: card.modelData.precipProb >= 40 ? 1 : 0
                                color: card.now ? WeatherStyle.colOnPrimaryContainer : (card.modelData.precipProb >= 40
                                    ? WeatherStyle.colPrimary
                                    : WeatherStyle.colSubtext)
                            }

                            StyledText {
                                text: Logic.formatPercent(card.modelData.precipProb)
                                font.pixelSize: WeatherStyle.textTiny
                                color: card.now ? WeatherStyle.colOnPrimaryContainer : (card.modelData.precipProb >= 40
                                    ? WeatherStyle.colPrimary
                                    : WeatherStyle.colSubtext)
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 2

                            MaterialSymbol {
                                text: "air"
                                iconSize: 12
                                color: card.now ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Logic.formatWind(card.modelData.windKmh, root.units)
                                font.pixelSize: WeatherStyle.textSmall
                                color: card.now ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colSubtext
                                elide: Text.ElideRight
                                horizontalAlignment: Text.AlignHCenter
                            }
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        anchors {
            right: parent.right
            top: parent.top
            bottom: parent.bottom
        }
        width: 20
        visible: flick.contentWidth > flick.width + 1
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0.0; color: WeatherStyle.alpha(WeatherStyle.colPane, 0.0) }
            GradientStop { position: 1.0; color: WeatherStyle.colPane }
        }
        z: 2
    }
}

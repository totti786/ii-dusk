import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * Now, in one banner. The container takes the condition's tone from the theme, a big
 * scalloped shape in the same tone holds the weather glyph, and the numbers are set in
 * the rounded numeric face. Facts below are the same chips every pane uses.
 */
Rectangle {
    id: root

    property var cur: ({})
    property var units: ({})
    property int offset: 0
    property bool compact: false
    property string locationName: ""
    property string providerText: ""
    property var stats: []

    signal statTriggered(string label)

    readonly property bool isDay: root.cur.isDay !== false
    readonly property string tone: WeatherStyle.conditionTone(root.cur.condition, root.isDay)
    readonly property color colBody: WeatherStyle.toneContainer(root.tone)
    readonly property color colOnBody: WeatherStyle.toneOnContainer(root.tone)
    readonly property color colAccent: WeatherStyle.toneColor(root.tone)

    implicitHeight: heroLayout.implicitHeight + (root.compact ? 40 : 56)
    radius: WeatherStyle.radiusExtraLarge
    color: root.colBody

    Behavior on color {
        animation: WeatherStyle.motionFast.colorAnimation.createObject(this)
    }

    // A plain clip would square off the rounded corner, so a mask of the banner cuts it
    Item {
        id: ornament
        anchors.fill: parent
        visible: false

        MaterialShape {
            width: root.compact ? 220 : 340
            height: width
            x: root.width - width * 0.62
            y: -height * 0.28
            shape: WeatherStyle.conditionShape(root.cur.condition, root.isDay)
            color: root.colOnBody
        }
    }

    Rectangle {
        id: mask
        anchors.fill: parent
        radius: root.radius
        visible: false
        layer.enabled: true
    }

    MultiEffect {
        anchors.fill: parent
        source: ornament
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
        opacity: 0.09
    }

    RowLayout {
        id: heroLayout
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: root.compact ? 20 : 32
            rightMargin: root.compact ? 20 : 32
        }
        spacing: WeatherStyle.gapHuge

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: WeatherStyle.gap

            // Place and date
            RowLayout {
                Layout.fillWidth: true
                spacing: WeatherStyle.gapSmall

                Rectangle {
                    implicitWidth: placeRow.implicitWidth + 24
                    implicitHeight: 32
                    radius: height / 2
                    color: WeatherStyle.alpha(root.colOnBody, 0.12)

                    RowLayout {
                        id: placeRow
                        anchors.centerIn: parent
                        spacing: 6

                        MaterialSymbol {
                            text: "location_on"
                            iconSize: 16
                            fill: 1
                            color: root.colOnBody
                        }

                        StyledText {
                            text: root.locationName
                            font.pixelSize: WeatherStyle.textSmall
                            font.weight: Font.DemiBold
                            color: root.colOnBody
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: `${Logic.formatWeekday(root.cur.time || Date.now(), root.offset, false)}, ${Logic.formatMonthDay(root.cur.time || Date.now(), root.offset)}`
                    font.pixelSize: WeatherStyle.textSmall
                    color: root.colOnBody
                    opacity: 0.78
                    elide: Text.ElideRight
                }
            }

            // Temperature and what it is like
            RowLayout {
                Layout.fillWidth: true
                spacing: WeatherStyle.gapLarge

                StyledText {
                    text: Logic.formatTemperature(root.cur.tempC, root.units)
                    font.family: WeatherStyle.fontNumbers
                    font.pixelSize: root.compact ? 76 : 112
                    font.weight: Font.DemiBold
                    font.variableAxes: WeatherStyle.axesDigitsBold
                    color: root.colOnBody
                    animateChange: !WeatherStyle.reducedMotion
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 2

                    StyledText {
                        Layout.fillWidth: true
                        text: root.cur.summary || Logic.conditionText(root.cur.condition)
                        font.family: WeatherStyle.fontTitle
                        font.variableAxes: ({ "wght": 700, "wdth": 100, "ROND": 100 })
                        font.pixelSize: root.compact ? WeatherStyle.textLarge + 2 : WeatherStyle.textTitle + 6
                        color: root.colOnBody
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `H ${Logic.formatTemperature(root.cur.highC, root.units)}  ·  L ${Logic.formatTemperature(root.cur.lowC, root.units)}`
                        font.pixelSize: WeatherStyle.textNormal
                        font.weight: Font.Medium
                        color: root.colOnBody
                        opacity: 0.86
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: `Feels like ${Logic.formatTemperature(root.cur.feelsC, root.units)}`
                        font.pixelSize: WeatherStyle.textSmall
                        color: root.colOnBody
                        opacity: 0.7
                    }
                }
            }

            // The facts, as chips on the banner's own tone
            Flow {
                Layout.fillWidth: true
                spacing: WeatherStyle.gapSmall

                Repeater {
                    model: root.stats

                    WeatherQuickStat {
                        required property var modelData
                        icon: modelData.icon
                        label: modelData.label
                        value: modelData.value
                        tone: modelData.tone
                        chartId: modelData.chartId ?? ""
                        colChip: WeatherStyle.alpha(root.colOnBody, 0.12)
                        colText: root.colOnBody
                        colMuted: WeatherStyle.alpha(root.colOnBody, 0.7)
                        colGlyph: root.colOnBody
                        colGlyphBack: WeatherStyle.alpha(root.colOnBody, 0.14)
                        onTriggered: root.statTriggered(modelData.label)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: WeatherStyle.gapSmall

                StyledText {
                    text: WeatherAppService.loading ? "Refreshing…" : `Updated ${Logic.timeAgo(WeatherAppService.lastFetchTime)}`
                    font.pixelSize: WeatherStyle.textSmall
                    color: root.colOnBody
                    opacity: 0.7
                }

                StyledText {
                    text: "·"
                    font.pixelSize: WeatherStyle.textSmall
                    color: root.colOnBody
                    opacity: 0.7
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.providerText
                    font.pixelSize: WeatherStyle.textSmall
                    font.weight: Font.Medium
                    color: root.colOnBody
                    opacity: 0.85
                    elide: Text.ElideRight
                }
            }
        }

        // The glyph in a shape of the condition's own tone
        Item {
            Layout.alignment: Qt.AlignVCenter
            visible: !root.compact
            implicitWidth: 188
            implicitHeight: 188

            MaterialShape {
                anchors.fill: parent
                shape: WeatherStyle.conditionShape(root.cur.condition, root.isDay)
                color: WeatherStyle.alpha(root.colOnBody, 0.16)
            }

            WeatherIcon {
                anchors.centerIn: parent
                iconSize: 118
                code: root.cur.condition
                isDay: root.isDay
            }
        }
    }
}

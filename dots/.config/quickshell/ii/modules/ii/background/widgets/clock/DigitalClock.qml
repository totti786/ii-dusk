pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: clockColumn
    spacing: 4

    readonly property bool colorful: Config.options.background.widgets.clock_digital.colorful
    readonly property bool showColon: Config.options.background.widgets.clock_digital.showColon
    readonly property bool showSeconds: Config.options.bar.clock.showSeconds
    readonly property real lineSpacing: Config.options.background.widgets.clock_digital.lineSpacing

    // Set by the widget from its size class: how large the digits are against the configured
    // size, whether they stack (1) or sit on one line (0) in place of the configured layout
    // (-1), and whether the date shows whatever the setting says
    property real sizeScale: 1
    property int verticalMode: -1
    property bool forceDate: false
    property bool isVertical: clockColumn.verticalMode < 0 ? Config.options.background.widgets.clock_digital.vertical : clockColumn.verticalMode === 1
    property color colText: WidgetColorScheme.textColorOnBg
    property color colTextSecondary: WidgetColorScheme.subtextColorOnBg
    property color colTextTertiary: WidgetColorScheme.accentColor
    property var textHorizontalAlignment: Text.AlignHCenter

    // Time
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        Layout.fillWidth: false
        ClockText {
            id: timeTextTop
            text: DateTime.time.split(":")[0].padStart(2, "0")
            color: clockColumn.colText
            horizontalAlignment: Text.AlignHCenter
            font {
                pixelSize: Config.options.background.widgets.clock_digital.font.size * clockColumn.sizeScale
                weight: Config.options.background.widgets.clock_digital.font.weight
                family: Appearance.font.family.numbers
                variableAxes: ({
                        "wdth": Config.options.background.widgets.clock_digital.font.width,
                        "ROND": Config.options.background.widgets.clock_digital.font.roundness
                    })
            }
        }
        Loader {
            active: !clockColumn.isVertical && showColon
            visible: active
            sourceComponent: ClockText {
                text: ":"
                color: colorful ? clockColumn.colTextSecondary : clockColumn.colText
                horizontalAlignment: clockColumn.textHorizontalAlignment
                font {
                    pixelSize: timeTextTop.font.pixelSize
                    weight: timeTextTop.font.weight
                    family: timeTextTop.font.family
                    variableAxes: timeTextTop.font.variableAxes
                }
            }
        }
        Loader {
            active: !clockColumn.isVertical
            visible: active
            sourceComponent: ClockText {
                text: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0")
                color: colorful ? clockColumn.colTextTertiary : clockColumn.colText
                horizontalAlignment: clockColumn.textHorizontalAlignment
                font {
                    pixelSize: timeTextTop.font.pixelSize
                    weight: timeTextTop.font.weight
                    family: timeTextTop.font.family
                    variableAxes: timeTextTop.font.variableAxes
                }
            }
        }
        Loader {
            active: !clockColumn.isVertical && clockColumn.showSeconds && showColon
            visible: active
            sourceComponent: ClockText {
                text: ":"
                color: colorful ? clockColumn.colTextSecondary : clockColumn.colText
                horizontalAlignment: clockColumn.textHorizontalAlignment
                font {
                    pixelSize: timeTextTop.font.pixelSize
                    weight: timeTextTop.font.weight
                    family: timeTextTop.font.family
                    variableAxes: timeTextTop.font.variableAxes
                }
            }
        }
        Loader {
            active: !clockColumn.isVertical && clockColumn.showSeconds
            visible: active
            sourceComponent: ClockText {
                text: DateTime.seconds
                color: colorful ? clockColumn.colTextTertiary : clockColumn.colText
                horizontalAlignment: clockColumn.textHorizontalAlignment
                font {
                    pixelSize: timeTextTop.font.pixelSize
                    weight: timeTextTop.font.weight
                    family: timeTextTop.font.family
                    variableAxes: timeTextTop.font.variableAxes
                }
            }
        }
    }
    

    Loader {
        // -40 is the built-in tightening of the stacked lines; lineSpacing is
        // the user's vertical gap delta on top of it (negative overlaps).
        Layout.topMargin: (-40 + clockColumn.lineSpacing) * clockColumn.sizeScale
        Layout.fillWidth: true
        active: clockColumn.isVertical
        visible: active
        sourceComponent: ClockText {
            id: timeTextBottom
            text: DateTime.time.split(":")[1].split(" ")[0].padStart(2, "0") + (clockColumn.showSeconds ? ":" + DateTime.seconds : "")
            color: colorful ? clockColumn.colTextTertiary : clockColumn.colText
            horizontalAlignment: clockColumn.textHorizontalAlignment
            font {
                pixelSize: timeTextTop.font.pixelSize
                weight: timeTextTop.font.weight
                family: timeTextTop.font.family
                variableAxes: timeTextTop.font.variableAxes
            }
        }
    }

    // Date
    ClockText {
        visible: Config.options.background.widgets.clock_digital.showDate || clockColumn.forceDate
        Layout.topMargin: -20 * clockColumn.sizeScale
        Layout.fillWidth: true
        text: DateTime.longDate
        color: colorful ? clockColumn.colTextSecondary : clockColumn.colText
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }

    // Quote
    ClockText {
        visible: Config.options.background.widgets.clock_digital.quoteEnable && Config.options.background.widgets.clock_digital.quoteText.length > 0
        font.pixelSize: Appearance.font.pixelSize.normal
        text: Config.options.background.widgets.clock_digital.quoteText
        animateChange: false
        color: clockColumn.colTextSecondary
        horizontalAlignment: clockColumn.textHorizontalAlignment
    }
}

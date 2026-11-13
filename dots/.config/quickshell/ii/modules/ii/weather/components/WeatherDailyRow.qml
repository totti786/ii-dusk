import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."
import "../../../../services/WeatherAppLogic.js" as Logic

/**
 * One day in the forecast list. The temperature track is centred on a shared domain so
 * tomorrow's range can be compared with today's without reading two numbers.
 */
Rectangle {
    id: root

    property var day: ({})
    property int dayIndex: 0
    property int offset: 0
    property var units: ({})
    property bool use24h: true
    property real domainMin: 0
    property real domainMax: 1
    property bool selected: false
    property bool compact: false

    signal clicked()

    // One fixed width per column: the same figure sits under the same figure in every row
    component Cell: RowLayout {
        property real cellWidth: 64
        Layout.preferredWidth: cellWidth
        Layout.minimumWidth: cellWidth
        Layout.maximumWidth: cellWidth
        spacing: 4
    }

    implicitHeight: 64
    radius: WeatherStyle.radiusNormal
    color: root.selected
        ? WeatherStyle.colPrimaryContainer
        : (rowHover.hovered ? WeatherStyle.colSurfaceHover : "transparent")

    readonly property color colMain: root.selected ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colOnSurface
    readonly property color colMuted: root.selected ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colSubtext
    readonly property bool wet: (root.day.precipProb || 0) >= 40
    readonly property real low: Logic.temperatureValue(root.day.minC, root.units)
    readonly property real high: Logic.temperatureValue(root.day.maxC, root.units)
    readonly property real span: Math.max(0.001, root.domainMax - root.domainMin)
    readonly property real startFraction: Math.max(0, Math.min(1, (root.low - root.domainMin) / root.span))
    readonly property real endFraction: Math.max(0, Math.min(1, (root.high - root.domainMin) / root.span))

    Behavior on color {
        animation: WeatherStyle.motionFast.colorAnimation.createObject(this)
    }

    HoverHandler {
        id: rowHover
        cursorShape: Qt.PointingHandCursor
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }

    RowLayout {
        anchors {
            fill: parent
            leftMargin: WeatherStyle.gap
            rightMargin: WeatherStyle.gapSmall
        }
        spacing: WeatherStyle.gap

        ColumnLayout {
            Layout.preferredWidth: root.compact ? 84 : 116
            Layout.minimumWidth: root.compact ? 84 : 116
            Layout.maximumWidth: root.compact ? 84 : 116
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: Logic.dayLabel(root.day.time, root.offset, root.dayIndex)
                font.pixelSize: WeatherStyle.textNormal
                font.weight: root.dayIndex === 0 ? Font.Bold : Font.Medium
                color: root.colMain
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: Logic.formatMonthDay(root.day.time, root.offset)
                font.pixelSize: WeatherStyle.textSmall
                color: root.colMuted
                opacity: root.selected ? 0.8 : 1
                elide: Text.ElideRight
            }
        }

        WeatherIcon {
            Layout.alignment: Qt.AlignVCenter
            iconSize: 36
            code: root.day.condition
            isDay: true
        }

        Cell {
            cellWidth: 60
            MaterialSymbol {
                text: "water_drop"
                iconSize: 15
                fill: root.wet ? 1 : 0
                color: root.wet && !root.selected ? WeatherStyle.colPrimary : root.colMuted
            }
            StyledText {
                text: Logic.formatPercent(root.day.precipProb)
                font.pixelSize: WeatherStyle.textSmall
                color: root.wet && !root.selected ? WeatherStyle.colPrimary : root.colMuted
            }
        }

        StyledText {
            Layout.preferredWidth: 44
            Layout.minimumWidth: 44
            text: Logic.formatTemperature(root.day.minC, root.units)
            font.family: WeatherStyle.fontNumbers
            font.pixelSize: WeatherStyle.textNormal
            font.variableAxes: WeatherStyle.axesDigits
            color: root.colMuted
            horizontalAlignment: Text.AlignRight
        }

        Item {
            Layout.fillWidth: true
            Layout.minimumWidth: 44
            Layout.preferredHeight: 16

            Rectangle {
                anchors {
                    left: parent.left
                    right: parent.right
                    verticalCenter: parent.verticalCenter
                }
                height: 8
                radius: 4
                color: root.selected ? WeatherStyle.alpha(WeatherStyle.colOnPrimaryContainer, 0.16) : WeatherStyle.colSurfaceHighest
            }

            Rectangle {
                y: parent.height / 2 - height / 2
                x: root.startFraction * parent.width
                width: Math.max(8, (root.endFraction - root.startFraction) * parent.width)
                height: 8
                radius: 4
                gradient: Gradient {
                    orientation: Gradient.Horizontal
                    GradientStop { position: 0.0; color: root.selected ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colTertiary }
                    GradientStop { position: 1.0; color: root.selected ? WeatherStyle.colOnPrimaryContainer : WeatherStyle.colPrimary }
                }
            }
        }

        StyledText {
            Layout.preferredWidth: 44
            Layout.minimumWidth: 44
            text: Logic.formatTemperature(root.day.maxC, root.units)
            font.family: WeatherStyle.fontNumbers
            font.pixelSize: WeatherStyle.textLarge
            font.weight: Font.DemiBold
            font.variableAxes: WeatherStyle.axesDigits
            color: root.colMain
            horizontalAlignment: Text.AlignRight
        }

        Cell {
            visible: !root.compact
            cellWidth: 96
            MaterialSymbol {
                text: "air"
                iconSize: 15
                color: root.colMuted
            }
            StyledText {
                Layout.fillWidth: true
                text: Logic.formatWind(root.day.windKmh, root.units)
                font.pixelSize: WeatherStyle.textSmall
                color: root.colMuted
                elide: Text.ElideRight
            }
        }

        Cell {
            visible: !root.compact
            cellWidth: 56
            MaterialSymbol {
                text: "wb_sunny"
                iconSize: 15
                color: WeatherStyle.uvTone(root.day.uv) === "error" ? WeatherStyle.colError : root.colMuted
            }
            StyledText {
                text: root.day.uv !== null && root.day.uv !== undefined ? Logic.formatUv(root.day.uv) : "--"
                font.pixelSize: WeatherStyle.textSmall
                color: root.colMuted
            }
        }

        MaterialSymbol {
            text: root.selected ? "keyboard_arrow_up" : "keyboard_arrow_down"
            iconSize: 20
            color: root.colMuted
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.background.widgets
import "WeatherMood.js" as Mood

/*
 * Weather Collage (1x1): the weather as a pile of cut-out shapes. The sky's
 * own shape, large in the accent, carries the temperature in the grotesk
 * face; smaller pieces overlap its edges, each a reading in its own shape and
 * voice - humidity on a four-leaf clover in wide heavy type, the wind on a
 * circle whose arrow points the way the wind blows (the one rotation, and it
 * carries the direction), the UV index on a sun. Under the pointer the big
 * shape morphs into its family's second shape.
 */
ExpressiveCardWidget {
    id: root
    onCardTapped: GlobalStates.openWeatherApp("")

    configEntryName: "weather_collage"

    readonly property var current: Weather.data
    readonly property bool night: Mood.isNight(DateTime.clock.date, root.current?.sunrise, root.current?.sunset)
    readonly property string fam: Mood.family(root.current?.wCode ?? 113)
    readonly property var compass: ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE", "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
    // Where the wind blows to: the reported direction is where it comes from.
    readonly property real windTo: Math.max(0, root.compass.indexOf(String(root.current?.windDir ?? "N"))) * 22.5 + 180

    HoverHandler {
        id: hover
    }

    // ── The sky ──
    Item {
        id: sky
        x: 12
        y: 12
        width: 158
        height: 158

        MaterialShape {
            anchors.fill: parent
            shapeString: hover.hovered && root.actionsEnabled ? Mood.altShapeName(root.fam, root.night) : Mood.shapeName(root.fam, root.night)
            color: root.cardScheme.accentColor
        }

        Column {
            anchors.centerIn: parent
            anchors.verticalCenterOffset: 4
            spacing: -8

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: WeatherIcons.getMaterialSymbol(root.current?.wCode ?? 113)
                iconSize: 26
                fill: 1
                color: root.cardScheme.onAccentColor
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: Mood.number(root.current?.temp) + "°"
                color: root.cardScheme.onAccentColor
                font.family: Appearance.font.family.expressive
                font.pixelSize: 54
                font.weight: Font.Bold
            }
        }
    }

    // ── Wind: the arrow points downwind ──
    Item {
        id: wind
        x: root.designWidth - width - 12
        y: 18
        width: 72
        height: 72

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: root.cardScheme.innerShapeColor
        }
        MaterialSymbol {
            anchors.horizontalCenter: parent.horizontalCenter
            y: 8
            text: "arrow_upward"
            iconSize: 28
            fill: 1
            rotation: root.windTo
            color: root.cardScheme.textColorOnBg
            Behavior on rotation {
                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
            }
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 11
            text: Mood.number(root.current?.wind)
            color: root.cardScheme.textColorOnBg
            font.family: Appearance.font.family.main
            font.pixelSize: 17
            font.variableAxes: ({ "wght": 700, "wdth": 60, "ROND": 100 })
        }
    }

    // ── Humidity: on a clover, overlapping the sky's foot ──
    Item {
        id: humidity
        x: root.designWidth - width - 14
        y: root.designHeight - height - 14
        width: 104
        height: 104

        MaterialShape {
            anchors.fill: parent
            shapeString: "Clover4Leaf"
            color: root.cardScheme.pillFillColor
        }
        Column {
            anchors.centerIn: parent
            spacing: -2

            MaterialSymbol {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "humidity_percentage"
                iconSize: 18
                fill: 1
                color: root.cardScheme.textColorOnPillFill
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(root.current?.humidity ?? "--")
                color: root.cardScheme.textColorOnPillFill
                font.family: Appearance.font.family.main
                font.pixelSize: 22
                font.variableAxes: ({ "wght": 800, "wdth": 125, "ROND": 100 })
            }
        }
    }

    // ── UV: a small sun under the sky ──
    Item {
        id: uv
        x: 22
        y: root.designHeight - height - 10
        width: 60
        height: 60

        MaterialShape {
            anchors.fill: parent
            shapeString: "Sunny"
            color: root.cardScheme.highlightCircleColor
        }
        Column {
            anchors.centerIn: parent
            spacing: -4

            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "UV"
                color: root.cardScheme.highlightTextColor
                font.family: Appearance.font.family.main
                font.pixelSize: 9
                font.letterSpacing: 1
                font.variableAxes: ({ "wght": 700, "wdth": 120, "ROND": 0 })
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: String(Math.round(Number(root.current?.uv ?? 0)))
                color: root.cardScheme.highlightTextColor
                font.family: Appearance.font.family.main
                font.pixelSize: 20
                font.variableAxes: ({ "wght": 600, "wdth": 100, "slnt": -10, "ROND": 100 })
            }
        }
    }
}

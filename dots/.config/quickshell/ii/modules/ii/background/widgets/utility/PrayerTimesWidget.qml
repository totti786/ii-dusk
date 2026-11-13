pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.ii.background.widgets

/*
 * Prayer Times (wide). The day drawn as the sun's path: a curve over the six
 * stations (Fajr, Sunrise, Dhuhr, Asr, Maghrib, Isha), the part already lived lit
 * in the accent colour and the sun riding the curve at the time it is now; before
 * Fajr and after Isha a moon waits on the horizon. The next prayer's station is an
 * accent pill. On the left, the place and the time left. The stations are spaced
 * evenly, not by the clock, so the labels never collide. Everything follows the
 * PrayerTimes service, which follows the shell clock, so nothing here ticks.
 */
ExpressiveCardWidget {
    id: root

    configEntryName: "prayer_times"

    // A strip (the next prayer and the time left), a tile (the same, larger), the wide card
    // (those plus the sun's path), a wider one with room for the path, and a big one with
    // the path under a large countdown.
    supportedSizes: ["2x0.5", "1x1", "2x1", "3x1", "2x2"]
    defaultSize: "2x1"
    readonly property bool strip: root.sizeClass === "2x0.5"
    readonly property bool tile: root.sizeClass === "1x1"
    readonly property bool tall: root.sizeClass === "2x2"
    readonly property bool showChart: !root.strip && !root.tile

    readonly property real padding: root.tile || root.strip ? 18 : 20
    readonly property var next: PrayerTimes.next
    readonly property var rows: PrayerTimes.today
    readonly property bool hasData: root.rows.length === 6

    readonly property color textColor: root.cardScheme.textColorOnBg
    readonly property color subtextColor: root.cardScheme.subtextColorOnBg
    readonly property color accentColor: root.cardScheme.accentColor
    readonly property color onAccentColor: root.cardScheme.onAccentColor
    readonly property color trackColor: ColorUtils.applyAlpha(root.textColor, 0.14)

    // ── Sun path geometry (chart coordinates) ──
    readonly property real leftW: root.sizeClass === "3x1" ? 178 : 150
    readonly property real chartH: root.tall ? 270 : root.designHeight - 40
    readonly property real chartW: root.tall ? root.designWidth - root.padding * 2 : root.designWidth - root.padding * 2 - root.leftW - 12
    readonly property real step: Math.min(70, root.chartW / 6)
    readonly property real baseY: root.chartH - 82
    readonly property real amplitude: Math.min(130, root.baseY - 30)
    // How high the sun stands at each station, 0 at the horizon.
    readonly property var heights: [0, 0.42, 1, 0.78, 0.28, 0]

    // A Catmull-Rom curve through the stations, so it has no kinks at them.
    function heightAt(u) {
        const n = root.heights.length - 1;
        const c = Math.max(0, Math.min(n, u));
        const i = Math.min(n - 1, Math.floor(c));
        const t = c - i;
        const p0 = root.heights[Math.max(0, i - 1)];
        const p1 = root.heights[i];
        const p2 = root.heights[i + 1];
        const p3 = root.heights[Math.min(n, i + 2)];
        const h = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t);
        return Math.max(0, h);
    }

    function pointAt(u) {
        return Qt.point(root.step / 2 + u * root.step, root.baseY - root.heightAt(u) * root.amplitude);
    }

    function curve(from, to) {
        const pts = [];
        const count = Math.max(2, Math.ceil((to - from) / 0.04));
        for (let k = 0; k <= count; k++)
            pts.push(root.pointAt(from + (to - from) * k / count));
        return pts;
    }

    // Where the sun is, in stations: 0 at Fajr to 5 at Isha. Below 0 or above 5 it
    // is night, and the moon sits just outside the curve.
    readonly property real sunU: {
        if (!root.hasData) return -1;
        const now = PrayerTimes.now.getTime();
        let j = -1;
        for (let i = 0; i < root.rows.length; i++) {
            if (root.rows[i].time.getTime() <= now) j = i;
        }
        if (j < 0) return -0.45;
        if (j >= root.rows.length - 1) return 5.45;
        const a = root.rows[j].time.getTime();
        const b = root.rows[j + 1].time.getTime();
        return j + (now - a) / Math.max(1, b - a);
    }
    readonly property bool isNight: root.sunU < 0 || root.sunU > 5
    readonly property real litTo: Math.max(0, Math.min(5, root.sunU))
    readonly property var fullCurve: root.curve(0, 5)
    readonly property var litCurve: root.sunU < 0 ? [] : root.curve(0, root.litTo)
    readonly property var litArea: {
        if (root.litCurve.length < 2) return [];
        const first = root.litCurve[0];
        const last = root.litCurve[root.litCurve.length - 1];
        return root.litCurve.concat([Qt.point(last.x, root.baseY), Qt.point(first.x, root.baseY)]);
    }

    Component.onCompleted: PrayerTimes.requestData()
    Component.onDestruction: PrayerTimes.releaseData()

    // ── Left: the place and the next prayer ──
    ColumnLayout {
        visible: !root.strip
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.margins: root.padding
        width: root.tile || root.tall ? root.designWidth - root.padding * 2 : root.leftW
        height: root.tall ? 180 : root.designHeight - root.padding * 2
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            MaterialSymbol {
                text: "mosque"
                iconSize: Appearance.font.pixelSize.larger
                fill: 1
                color: root.accentColor
            }

            StyledText {
                Layout.fillWidth: true
                text: PrayerTimes.city || Translation.tr("Prayer times")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.variableAxes: ({ "wght": 600, "wdth": 110 })
                color: root.subtextColor
                elide: Text.ElideRight
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: 2
            visible: PrayerTimes.hijriDate.length > 0 && !root.tile
            text: PrayerTimes.hijriDate
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.subtextColor
            elide: Text.ElideRight
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            text: root.next
                ? (PrayerTimes.nextIsTomorrow
                    ? Translation.tr("%1 · tomorrow").arg(root.next.name)
                    : root.next.name)
                : (PrayerTimes.error.length > 0 ? PrayerTimes.error : Translation.tr("Loading prayer times…"))
            font.pixelSize: Appearance.font.pixelSize.larger
            font.variableAxes: ({ "wght": 650, "wdth": 110 })
            color: root.accentColor
            elide: Text.ElideRight
        }

        StyledText {
            Layout.fillWidth: true
            Layout.preferredHeight: 66
            verticalAlignment: Text.AlignVCenter
            text: root.next ? PrayerTimes.formatRemaining(PrayerTimes.minutesToNext) : "—"
            font.pixelSize: root.tall ? 76 : (root.tile ? 64 : 58)
            font.variableAxes: ({ "wght": 650, "wdth": 125 })
            fontSizeMode: Text.HorizontalFit
            minimumPixelSize: 34
            color: root.textColor
        }

        StyledText {
            Layout.fillWidth: true
            visible: root.tile && root.next !== null
            text: root.next ? PrayerTimes.formatTime(root.next.time) : ""
            font.pixelSize: Appearance.font.pixelSize.normal
            font.variableAxes: ({ "wght": 600 })
            color: root.subtextColor
        }
    }

    // ── Strip: the next prayer and what is left, in one line ──
    RowLayout {
        visible: root.strip
        anchors.fill: parent
        anchors.margins: root.padding
        spacing: 12

        MaterialSymbol {
            text: "mosque"
            iconSize: Appearance.font.pixelSize.huge
            fill: 1
            color: root.accentColor
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                text: root.next ? (PrayerTimes.nextIsTomorrow ? Translation.tr("%1 · tomorrow").arg(root.next.name) : root.next.name) : Translation.tr("Loading prayer times…")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.variableAxes: ({ "wght": 650, "wdth": 110 })
                color: root.accentColor
                elide: Text.ElideRight
            }
            StyledText {
                Layout.fillWidth: true
                text: root.next ? PrayerTimes.formatTime(root.next.time) + (PrayerTimes.city ? " · " + PrayerTimes.city : "") : ""
                font.pixelSize: Appearance.font.pixelSize.small
                color: root.subtextColor
                elide: Text.ElideRight
            }
        }
        StyledText {
            text: root.next ? PrayerTimes.formatRemaining(PrayerTimes.minutesToNext) : "—"
            font.pixelSize: 44
            font.variableAxes: ({ "wght": 650, "wdth": 125 })
            color: root.textColor
        }
    }

    // ── Right: the sun's path ──
    Item {
        id: chart
        anchors.right: parent.right
        anchors.rightMargin: root.tall ? (root.designWidth - root.step * 6) / 2 : root.padding
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 18
        height: root.chartH
        width: root.step * 6
        visible: root.hasData && root.showChart

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            // The whole day, dim.
            ShapePath {
                strokeColor: root.trackColor
                strokeWidth: 3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: root.fullCurve }
            }

            // The part already lived, softly filled to the horizon.
            ShapePath {
                strokeColor: "transparent"
                fillColor: ColorUtils.applyAlpha(root.accentColor, 0.16)
                PathPolyline { path: root.litArea }
            }

            ShapePath {
                strokeColor: root.accentColor
                strokeWidth: 3
                fillColor: "transparent"
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                PathPolyline { path: root.litCurve }
            }
        }

        // Horizon.
        Rectangle {
            x: 0
            y: root.baseY
            width: parent.width
            height: 1
            color: root.trackColor
        }

        // Stations: a dot on the curve, and the prayer under the horizon.
        Repeater {
            model: root.rows

            delegate: Item {
                id: station
                required property var modelData
                required property int index

                readonly property bool isNext: !!root.next && station.modelData.id === root.next.id
                readonly property bool isPast: station.modelData.time <= PrayerTimes.now && !station.isNext
                readonly property color fg: station.isNext ? root.onAccentColor : root.textColor

                x: station.index * root.step
                width: root.step
                height: parent.height

                Rectangle {
                    readonly property point p: root.pointAt(station.index)
                    x: p.x - station.x - width / 2
                    y: p.y - height / 2
                    width: station.isNext ? 12 : 9
                    height: width
                    radius: width / 2
                    color: station.isPast || station.isNext ? root.accentColor : root.cardColor
                    border.width: 2
                    border.color: station.isPast || station.isNext ? root.accentColor : root.trackColor
                }

                Rectangle {
                    x: 3
                    y: root.baseY + 14
                    width: parent.width - 6
                    height: 52
                    radius: root.pill(width)
                    color: root.accentColor
                    opacity: station.isNext ? 1 : 0

                    Behavior on opacity {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }

                ColumnLayout {
                    x: 0
                    y: root.baseY + 14
                    width: parent.width
                    height: 52
                    spacing: 2
                    opacity: station.isPast ? 0.45 : 1

                    Item { Layout.fillHeight: true }

                    StyledText {
                        Layout.fillWidth: true
                        text: station.modelData.name
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.variableAxes: ({ "wght": station.isNext ? 700 : 500 })
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 8
                        color: station.isNext ? station.fg : root.subtextColor
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: PrayerTimes.formatTime(station.modelData.time)
                        horizontalAlignment: Text.AlignHCenter
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.variableAxes: ({ "wght": 650 })
                        fontSizeMode: Text.HorizontalFit
                        minimumPixelSize: 8
                        color: station.fg
                    }

                    Item { Layout.fillHeight: true }
                }
            }
        }

        // The sun by day, the moon by night.
        Item {
            id: sun
            readonly property point p: root.pointAt(root.sunU)
            x: p.x - width / 2
            y: p.y - height / 2
            width: 30
            height: 30

            Behavior on x {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on y {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            Rectangle {
                anchors.fill: parent
                radius: width / 2
                color: ColorUtils.applyAlpha(root.accentColor, 0.25)
            }

            Rectangle {
                anchors.centerIn: parent
                width: 22
                height: 22
                radius: 11
                color: root.accentColor

                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.isNight ? "dark_mode" : "sunny"
                    iconSize: 15
                    fill: 1
                    color: root.onAccentColor
                }
            }
        }
    }
}

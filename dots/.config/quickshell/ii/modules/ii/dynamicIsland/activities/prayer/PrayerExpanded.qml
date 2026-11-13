pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The bubble, opened up: the same ring with the minutes inside it, the prayer's name and its
 * time beside it, and the day as five segments underneath, the ones gone by filled and the
 * next one lifted. Nothing else.
 *
 * Self-contained on purpose: the bubble loads cards by URL, and such a file gets none of its
 * directory's types. It reads PrayerTimes, which the island already follows.
 */
Item {
    id: root

    readonly property var next: PrayerTimes.next
    readonly property var five: PrayerTimes.today.filter(p => p.id !== "Sunrise")
    readonly property string nextId: root.next?.id ?? ""
    readonly property var heroItems: [disc]

    // The same colouring as the bubble: dawn and night cool, dusk warm, the day in primary.
    readonly property bool nightish: root.nextId === "Isha" || root.nextId === "Fajr"
    readonly property bool dusk: root.nextId === "Maghrib"
    readonly property color rim: root.nightish ? Appearance.colors.colSecondary : (root.dusk ? Appearance.colors.colTertiary : Appearance.colors.colPrimary)
    readonly property color discColor: root.nightish ? Appearance.colors.colSecondaryContainer : (root.dusk ? Appearance.colors.colTertiaryContainer : Appearance.colors.colPrimaryContainer)
    readonly property color onDisc: root.nightish ? Appearance.colors.colOnSecondaryContainer : (root.dusk ? Appearance.colors.colOnTertiaryContainer : Appearance.colors.colOnPrimaryContainer)

    readonly property real margin: 16
    readonly property real preferredExpandedWidth: 280
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    function glyphFor(id: string): string {
        switch (id) {
        case "Fajr": return "wb_twilight";
        case "Dhuhr": return "light_mode";
        case "Asr": return "wb_sunny";
        case "Maghrib": return "wb_twilight";
        case "Isha": return "bedtime";
        }
        return "mosque";
    }

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 16

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            // The bubble's ring, larger.
            Item {
                Layout.preferredWidth: 64
                Layout.preferredHeight: 64

                Rectangle {
                    id: disc
                    anchors.fill: parent
                    anchors.margins: 5
                    radius: width / 2
                    color: root.discColor
                    Behavior on color {
                        animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                    }
                    StyledText {
                        anchors.centerIn: parent
                        text: String(PrayerTimes.minutesToNext)
                        font.pixelSize: 24
                        font.weight: Font.Bold
                        font.features: ({ "tnum": 1 })
                        color: root.onDisc
                    }
                }

                Canvas {
                    anchors.fill: parent
                    property real f: PrayerTimes.progress
                    property color stroke: root.rim
                    onFChanged: requestPaint()
                    onStrokeChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        const r = width / 2 - 3;
                        const a0 = -Math.PI / 2;
                        const a1 = a0 + Math.PI * 2 * Math.max(0.03, Math.min(1, f));
                        ctx.lineWidth = 3;
                        ctx.lineCap = "round";
                        ctx.strokeStyle = stroke;
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, r, a0, a1);
                        ctx.stroke();
                        ctx.fillStyle = stroke;
                        ctx.beginPath();
                        ctx.arc(width / 2 + r * Math.cos(a1), height / 2 + r * Math.sin(a1), 4, 0, Math.PI * 2);
                        ctx.fill();
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 1

                StyledText {
                    Layout.fillWidth: true
                    text: root.next ? PrayerTimes.prayerName(root.next.id) : Translation.tr("Prayer times")
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.huge
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.next !== null
                    text: root.next ? Translation.tr("in %1  ·  %2").arg(PrayerTimes.formatRemaining(PrayerTimes.minutesToNext)).arg(PrayerTimes.formatTime(root.next.time)) : ""
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.small
                    font.features: ({ "tnum": 1 })
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: PrayerTimes.hijriDate.length > 0
                    text: PrayerTimes.hijriDate
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    opacity: 0.8
                }
            }
        }

        // The day: five segments, each with its name and time.
        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            Repeater {
                model: root.five

                delegate: ColumnLayout {
                    id: seg
                    required property var modelData
                    readonly property bool isNext: root.next !== null && root.next.id === seg.modelData.id
                        && root.next.time.getTime() === seg.modelData.time.getTime()
                    readonly property bool past: seg.modelData.time.getTime() <= PrayerTimes.now.getTime() && !seg.isNext

                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 5

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 4
                        radius: 2
                        color: seg.isNext ? root.rim : (seg.past ? Appearance.colors.colOnSurfaceVariant : Appearance.colors.colSurfaceContainerHighest)
                        opacity: seg.past ? 0.45 : 1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: PrayerTimes.prayerName(seg.modelData.id)
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: seg.isNext ? Font.DemiBold : Font.Normal
                        color: seg.isNext ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                        opacity: seg.past ? 0.55 : 1
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: -3
                        text: PrayerTimes.formatTime(seg.modelData.time)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: seg.isNext ? Font.DemiBold : Font.Normal
                        font.features: ({ "tnum": 1 })
                        color: seg.isNext ? Appearance.colors.colOnSurface : Appearance.colors.colSubtext
                        opacity: seg.past ? 0.55 : 1
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "MonitorFormat.js" as Fmt

/// Battery at a glance: charge, time left (or until full) and what it is drawing right now.
Rectangle {
    id: root

    readonly property var b: MonitorService.battery
    readonly property bool charging: b !== null && b.status === "Charging"
    readonly property bool low: b !== null && b.percent < 20 && !root.charging
    readonly property color accent: root.low ? ClockStyle.colError : ClockStyle.colPrimary

    visible: b !== null
    radius: ClockStyle.radiusFull
    color: root.low ? ClockStyle.colErrorContainer : ClockStyle.colSurfaceHigh
    implicitHeight: 36
    implicitWidth: row.implicitWidth + 28

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 8

        MaterialSymbol {
            text: root.charging ? "battery_charging_full" : root.low ? "battery_alert" : "battery_full"
            iconSize: 20
            color: root.accent
        }
        StyledText {
            text: root.b ? root.b.percent + "%" : ""
            color: ClockStyle.colOnBackground
            font.weight: Font.DemiBold
        }
        StyledText {
            visible: text !== ""
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textSmall
            text: {
                const b = root.b;
                if (!b || b.seconds === null || b.seconds === undefined)
                    return b && b.status === "Full" ? Translation.tr("Full") : "";
                return b.status === "Charging" ? Translation.tr("%1 until full").arg(Fmt.duration(b.seconds))
                    : Translation.tr("%1 left").arg(Fmt.duration(b.seconds));
            }
        }
        StyledText {
            visible: root.b !== null && root.b.watts > 0
            text: root.b ? `${root.b.watts.toFixed(1)} W` : ""
            color: ClockStyle.colOnBackground
            font.pixelSize: ClockStyle.textSmall
            font.weight: Font.Medium
        }
    }
}

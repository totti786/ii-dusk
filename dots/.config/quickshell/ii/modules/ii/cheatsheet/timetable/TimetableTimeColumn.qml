import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import "."
import "TimetableHelpers.js" as H
import qs.services

Column {
    id: timeColumn
    
    property int totalSlots
    property int slotHeight
    property int slotDuration
    property int startMinute
    property int timeColumnWidth

    width: timeColumnWidth

    Repeater {
        model: totalSlots
        delegate: Item {
            width: timeColumnWidth
            height: slotHeight

            StyledText {
                text: {
                    let totalMinutes = startMinute + (index * slotDuration);
                    return Translation.dayMarks(H.minutesToTimeStr(totalMinutes, Config.options?.time.format));
                }
                anchors.top: parent.top
                anchors.topMargin: -font.pixelSize / 2
                anchors.right: parent.right
                anchors.rightMargin: 8
                width: parent.width - 8
                horizontalAlignment: Text.AlignRight
                font.weight: Font.Medium
                color: Appearance.colors.colOnSurfaceVariant
                // A 12-hour label is wider than the column at full size.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: 8
                elide: Text.ElideRight
            }
        }
    }
}

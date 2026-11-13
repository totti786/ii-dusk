import QtQuick
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/// Seven bars, Sunday to Saturday: when in the week the contributions happen.
Item {
    id: root

    property var totals: [0, 0, 0, 0, 0, 0, 0]
    readonly property real peak: Math.max(1, ...root.totals)
    readonly property int best: root.totals.indexOf(Math.max(...root.totals))
    property int hoverIndex: -1
    readonly property var names: [Translation.tr("Sun"), Translation.tr("Mon"), Translation.tr("Tue"), Translation.tr("Wed"), Translation.tr("Thu"), Translation.tr("Fri"), Translation.tr("Sat")]

    Row {
        anchors { left: parent.left; right: parent.right; top: parent.top; bottom: caption.top; bottomMargin: 4 }
        spacing: 8
        Repeater {
            model: 7
            delegate: Item {
                id: col
                required property int index
                width: (parent.width - 6 * 8) / 7
                height: parent.height
                readonly property real frac: root.totals[index] / root.peak
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: dayLabel.top; bottomMargin: 4 }
                    height: Math.max(6, (parent.height - 44) * col.frac * grow)
                    property real grow: 0
                    Component.onCompleted: grow = 1
                    Behavior on grow { NumberAnimation { duration: 700 + col.index * 90; easing.type: Easing.OutBack } }
                    radius: Math.min(10, width / 2)
                    color: col.index === root.best ? Appearance.colors.colPrimary : Appearance.colors.colSecondaryContainer
                    opacity: root.hoverIndex === -1 || root.hoverIndex === col.index ? 1 : 0.55
                    Behavior on opacity { NumberAnimation { duration: 120 } }
                    StyledText {
                        anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.top; bottomMargin: 3 }
                        text: String(root.totals[col.index])
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        font.weight: col.index === root.best ? Font.Bold : Font.Normal
                        color: col.index === root.best ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    }
                }
                StyledText {
                    id: dayLabel
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
                    text: root.names[col.index]
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    color: col.index === root.best ? Appearance.colors.colPrimary : Appearance.colors.colOnSurfaceVariant
                    font.weight: col.index === root.best ? Font.Bold : Font.Normal
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: root.hoverIndex = col.index
                    onExited: root.hoverIndex = -1
                }
            }
        }
    }
    StyledText {
        id: caption
        anchors { left: parent.left; bottom: parent.bottom }
        font.pixelSize: Appearance.font.pixelSize.smaller
        color: root.hoverIndex >= 0 ? Appearance.colors.colOnSurface : Appearance.colors.colOnSurfaceVariant
        text: root.hoverIndex >= 0 ? Translation.tr("%1 · %2 contributions").arg(root.names[root.hoverIndex]).arg(root.totals[root.hoverIndex])
            : Translation.tr("Busiest on %1").arg(root.names[root.best])
    }
}

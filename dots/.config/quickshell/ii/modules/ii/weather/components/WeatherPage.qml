import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import ".."

/**
 * The scroll container shared by every weather page: a centred, max-width column with
 * room for a scrollbar, so a wide monitor gets a readable measure instead of a dashboard
 * stretched edge to edge.
 */
Flickable {
    id: root

    property int padding: WeatherStyle.pagePaddingWide
    property int maxContentWidth: 1440
    property alias spacing: contentColumn.spacing
    default property alias contentData: contentColumn.data

    contentWidth: width
    contentHeight: contentColumn.height + root.padding * 2
    boundsBehavior: Flickable.StopAtBounds
    clip: true
    flickableDirection: Flickable.VerticalFlick
    pressDelay: 60

    ScrollBar.vertical: StyledScrollBar {
        policy: ScrollBar.AsNeeded
    }

    ColumnLayout {
        id: contentColumn
        x: Math.max(root.padding, (root.width - Math.min(root.maxContentWidth, root.width - root.padding * 2)) / 2)
        y: root.padding
        width: Math.min(root.maxContentWidth, Math.max(1, root.width - root.padding * 2))
        spacing: WeatherStyle.gapHuge
    }
}

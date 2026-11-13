import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The app bar, with the same proportions as ClockTopBar but a stable title. */
Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property bool showBack: false
    property bool showRailToggle: false
    property bool railExpanded: true
    property bool showClose: true
    default property alias actions: actionRow.data

    signal backRequested()
    signal railToggled()
    signal closeRequested()

    implicitHeight: ClockStyle.topBarHeight

    RowLayout {
        anchors {
            fill: parent
            leftMargin: ClockStyle.gapTiny
            rightMargin: ClockStyle.gapTiny
        }
        spacing: ClockStyle.gapSmall

        ClockIconButton {
            visible: root.showBack
            symbol: "arrow_back"
            tooltip: Translation.tr("Back")
            onClicked: root.backRequested()
        }

        ClockIconButton {
            visible: root.showRailToggle && !root.showBack
            symbol: root.railExpanded ? "menu_open" : "menu"
            tooltip: root.railExpanded ? Translation.tr("Collapse") : Translation.tr("Expand")
            onClicked: root.railToggled()
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: ClockStyle.gapTiny
            spacing: 0

            StyledText {
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle + 4
                color: ClockStyle.colOnBackground
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.subtitle.length > 0
                text: root.subtitle
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colSubtext
            }
        }

        RowLayout {
            id: actionRow
            spacing: ClockStyle.gapTiny
        }

        ClockIconButton {
            visible: root.showClose
            symbol: "close"
            tooltip: Translation.tr("Close")
            onClicked: root.closeRequested()
        }
    }
}

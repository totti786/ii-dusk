import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The process list's controls, for the header line of its card: a search that opens in place
 * ("/" or the button; Esc closes it) and the switch between the two readings of processor use.
 */
RowLayout {
    id: root

    /// Show processor use as a share of the whole processor (true) or of one core, as top does
    property bool ofTotal: true
    /// A search that is closed does not filter
    readonly property string filterText: MonitorService.procSearchOpen ? filterField.text : ""

    spacing: 8

    function focusSearch(): void {
        filterField.input.forceActiveFocus();
    }

    Connections {
        target: MonitorService
        function onProcSearchFocusChanged() {
            // The field is created hidden: wait for it to show before it can take the keys
            Qt.callLater(() => root.focusSearch());
        }
    }

    ClockFormField {
        id: filterField
        visible: MonitorService.procSearchOpen
        Layout.fillWidth: true
        Layout.minimumWidth: 100
        Layout.preferredHeight: 40
        symbol: "search"
        placeholder: Translation.tr("Filter by name, command or PID")
        // Esc closes the search and hands the keys back to the window
        input.Keys.onEscapePressed: event => {
            MonitorService.procSearchOpen = false;
            filterField.input.focus = false;
            event.accepted = true;
        }
    }
    Item {
        visible: !MonitorService.procSearchOpen
        Layout.fillWidth: true
    }

    Rectangle {
        implicitHeight: 28
        implicitWidth: 28
        radius: 14
        color: MonitorService.procSearchOpen ? ClockStyle.colSecondaryContainer : searchArea.containsMouse ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh
        MaterialSymbol {
            anchors.centerIn: parent
            text: "search"
            iconSize: 18
            color: ClockStyle.colOnBackground
        }
        MouseArea {
            id: searchArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            // Closed or not being typed in: open it and put the cursor there. Typing already: close it.
            onClicked: {
                if (MonitorService.procSearchOpen && filterField.input.activeFocus)
                    MonitorService.procSearchOpen = false;
                else
                    MonitorService.openProcSearch();
            }
        }
        StyledToolTip {
            requireOverlay: false
            extraVisibleCondition: searchArea.containsMouse
            text: Translation.tr("Search processes (/ or Ctrl+F)")
        }
    }

    // A small switch between the two readings of processor use
    Rectangle {
        implicitHeight: 28
        implicitWidth: modeText.implicitWidth + 24
        radius: height / 2
        color: modeArea.containsMouse ? ClockStyle.colSurfaceHover : ClockStyle.colSurfaceHigh

        StyledText {
            id: modeText
            anchors.centerIn: parent
            text: root.ofTotal ? Translation.tr("% of total") : Translation.tr("% of a core")
            color: ClockStyle.colOnBackground
            font.pixelSize: ClockStyle.textSmall
        }
        MouseArea {
            id: modeArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.ofTotal = !root.ofTotal
        }
        StyledToolTip {
            requireOverlay: false
            extraVisibleCondition: modeArea.containsMouse
            text: Translation.tr("Show processor use as a share of the whole processor or of one core. Click to switch.")
        }
    }
}

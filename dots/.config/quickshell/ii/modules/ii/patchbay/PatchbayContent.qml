pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Window

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The Patchbay inside its window: the top bar, a row of filters, and the graph. It reads
 * the PipeWire graph only while it is on show.
 */
FocusScope {
    id: root

    signal closeRequested()

    readonly property bool shown: root.Window.window?.visible ?? true

    onShownChanged: {
        PatchbayService.watching = root.shown;
        if (root.shown)
            Qt.callLater(() => root.forceActiveFocus());
    }
    Component.onCompleted: PatchbayService.watching = root.shown
    Component.onDestruction: PatchbayService.watching = false

    // A control that held the keys is destroyed or hidden on close; take them back
    Connections {
        target: root.Window.window
        function onActiveFocusItemChanged() {
            if (root.Window.window && !root.Window.window.activeFocusItem)
                Qt.callLater(() => root.forceActiveFocus());
        }
    }

    Keys.onPressed: event => {
        const ctrl = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) {
            view.removeSelected();
            event.accepted = true;
        } else if (ctrl && (event.key === Qt.Key_W || event.key === Qt.Key_Q)) {
            root.closeRequested();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            view.selectedLink = -1;
            event.accepted = true;
        }
    }

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colBackground
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: ClockStyle.paneGap
        anchors.topMargin: ClockStyle.gapTiny
        spacing: ClockStyle.gapTiny

        ClockTopBar {
            Layout.fillWidth: true
            title: Translation.tr("Patchbay")
            subtitle: Translation.tr("Drag from a dot to another to connect. Click a line, then Delete, to cut it.")
            onCloseRequested: root.closeRequested()
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: ClockStyle.gapSmall
            spacing: ClockStyle.gapSmall

            ClockChip {
                symbol: "volume_up"
                label: Translation.tr("Audio")
                selected: view.showAudio
                onClicked: view.showAudio = !view.showAudio
            }
            ClockChip {
                symbol: "piano"
                label: Translation.tr("MIDI")
                selected: view.showMidi
                onClicked: view.showMidi = !view.showMidi
            }
            ClockChip {
                symbol: "videocam"
                label: Translation.tr("Video")
                selected: view.showVideo
                onClicked: view.showVideo = !view.showVideo
            }
            Item { Layout.preferredWidth: ClockStyle.gap }
            ClockChip {
                symbol: "link"
                label: Translation.tr("Connected only")
                selected: view.connectedOnly
                onClicked: view.connectedOnly = !view.connectedOnly
            }
            ClockChip {
                symbol: "speaker"
                label: Translation.tr("Monitor ports")
                selected: view.showMonitors
                onClicked: view.showMonitors = !view.showMonitors
            }
            Item { Layout.fillWidth: true }
            StyledText {
                Layout.maximumWidth: 320
                visible: PatchbayService.lastError.length > 0
                text: PatchbayService.lastError
                color: ClockStyle.colError
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
            ClockButton {
                variant: "tonal"
                symbol: "link_off"
                label: Translation.tr("Cut link")
                visible: view.selectedLink >= 0
                onClicked: view.removeSelected()
            }
            ClockButton {
                variant: "text"
                symbol: "auto_awesome_mosaic"
                label: Translation.tr("Tidy up")
                onClicked: PatchbayService.arrange()
            }
        }

        PatchbayView {
            id: view
            Layout.fillWidth: true
            Layout.fillHeight: true
        }
    }
}

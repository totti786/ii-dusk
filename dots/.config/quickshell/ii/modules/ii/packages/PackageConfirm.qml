import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A question over the page, answered with a button; Escape or a click outside says no. */
Item {
    id: root

    property string title: ""
    property string message: ""
    property string confirmLabel: Translation.tr("Continue")
    property bool danger: false
    property var onConfirmed: null

    function ask(title, message, confirmLabel, danger, callback): void {
        root.title = title;
        root.message = message;
        root.confirmLabel = confirmLabel;
        root.danger = danger;
        root.onConfirmed = callback;
        root.visible = true;
        card.forceActiveFocus();
    }

    function close(): void {
        root.visible = false;
        root.onConfirmed = null;
    }

    visible: false
    z: 20

    Rectangle {
        anchors.fill: parent
        color: ClockStyle.colScrim
        opacity: 0.5
        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(460, root.width - ClockStyle.gapHuge * 2)
        implicitHeight: col.implicitHeight + ClockStyle.gapHuge * 2
        height: implicitHeight
        radius: ClockStyle.radiusExtraLarge
        color: ClockStyle.colSheet
        focus: root.visible
        Keys.onEscapePressed: root.close()

        ColumnLayout {
            id: col
            anchors.fill: parent
            anchors.margins: ClockStyle.gapHuge
            spacing: ClockStyle.gap

            StyledText {
                Layout.fillWidth: true
                text: root.title
                color: ClockStyle.colOnBackground
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.DemiBold
                wrapMode: Text.WordWrap
            }
            StyledText {
                Layout.fillWidth: true
                text: root.message
                color: ClockStyle.colSubtext
                wrapMode: Text.WordWrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapSmall
                Item { Layout.fillWidth: true }
                ClockButton {
                    variant: "text"
                    label: Translation.tr("Cancel")
                    onClicked: root.close()
                }
                ClockButton {
                    variant: "filled"
                    danger: root.danger
                    label: root.confirmLabel
                    onClicked: {
                        const run = root.onConfirmed;
                        root.close();
                        if (run)
                            run();
                    }
                }
            }
        }
    }
}

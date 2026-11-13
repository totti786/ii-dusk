pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A small reader control sheet that keeps typography close to the article. */
Popup {
    id: root

    objectName: "wikipediaReadingPopup"

    property Item anchorItem: null
    property Item popupParent: null
    property int fontSize: 18
    property int minimumFontSize: 14
    property int maximumFontSize: 28
    property int defaultFontSize: 18

    signal fontSizeSelected(int value)

    property point anchorPoint: Qt.point(0, 0)
    readonly property bool openAbove: root.anchorPoint.y > ((root.popupParent?.height ?? 520) / 2)
    readonly property real desiredY: root.openAbove
        ? root.anchorPoint.y - root.height - ClockStyle.gapSmall
        : root.anchorPoint.y + (root.anchorItem?.height ?? 0) + ClockStyle.gapSmall

    parent: root.popupParent ?? root.anchorItem?.parent ?? null
    width: Math.min(320, Math.max(280, (root.popupParent?.width ?? 760) - 24))
    implicitHeight: 232
    height: root.implicitHeight
    x: Math.max(8, (root.popupParent?.width ?? root.width) - root.width - 8)
    y: Math.max(8, Math.min(root.desiredY,
        (root.popupParent?.height ?? root.height) - root.height - 8))
    padding: ClockStyle.gap
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    function clamp(value): int {
        return Math.max(root.minimumFontSize, Math.min(root.maximumFontSize, Math.round(Number(value))));
    }

    function changeSize(delta): void {
        root.fontSizeSelected(root.clamp(root.fontSize + Number(delta)));
    }

    function resetSize(): void {
        root.fontSizeSelected(root.clamp(root.defaultFontSize));
    }

    function updateAnchorPoint(): void {
        if (root.anchorItem && root.popupParent)
            root.anchorPoint = root.anchorItem.mapToItem(root.popupParent, 0, 0);
    }

    onOpened: {
        root.updateAnchorPoint();
        Qt.callLater(() => {
            root.updateAnchorPoint();
            decreaseButton.forceActiveFocus();
        });
    }

    background: Rectangle {
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSheet
        border.width: 1
        border.color: ClockStyle.colOutline
    }

    contentItem: ColumnLayout {
        Keys.priority: Keys.BeforeItem
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape) {
                root.close();
                event.accepted = true;
            }
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    text: Translation.tr("Reading size")
                    color: ClockStyle.colOnSurface
                    font.family: ClockStyle.fontTitle
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }

                StyledText {
                    text: Translation.tr("Adjust article text")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                }
            }

            ClockIconButton {
                symbol: "close"
                tooltip: Translation.tr("Close reading settings")
                Accessible.name: Translation.tr("Close reading settings")
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 48
            radius: ClockStyle.radiusSmall
            color: ClockStyle.colField

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapSmall
                anchors.rightMargin: ClockStyle.gapSmall
                spacing: ClockStyle.gapSmall

                ClockIconButton {
                    id: decreaseButton
                    symbol: "text_decrease"
                    tooltip: Translation.tr("Decrease text size")
                    Accessible.name: Translation.tr("Decrease text size")
                    enabled: root.fontSize > root.minimumFontSize
                    onClicked: root.changeSize(-1)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 px").arg(root.fontSize)
                    horizontalAlignment: Text.AlignHCenter
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }

                ClockIconButton {
                    symbol: "text_increase"
                    tooltip: Translation.tr("Increase text size")
                    Accessible.name: Translation.tr("Increase text size")
                    enabled: root.fontSize < root.maximumFontSize
                    onClicked: root.changeSize(1)
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 40
            radius: ClockStyle.radiusSmall
            color: ClockStyle.colPrimaryContainer

            StyledText {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapSmall
                anchors.rightMargin: ClockStyle.gapSmall
                text: Translation.tr("Aa  Reading preview")
                verticalAlignment: Text.AlignVCenter
                color: ClockStyle.colOnPrimaryContainer
                font.pixelSize: root.fontSize
                elide: Text.ElideRight
            }
        }

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("%1–%2 px").arg(root.minimumFontSize).arg(root.maximumFontSize)
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
            }

            ClockButton {
                symbol: "restart_alt"
                label: Translation.tr("Reset")
                variant: "text"
                Accessible.name: Translation.tr("Reset reading size")
                onClicked: root.resetSize()
            }
        }
    }
}

pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * The screen of the calculator: the expression above, the answer below at a size that
 * shrinks to fit, a small row for the memory flag, the angle unit and copy.
 * It only draws what the window hands it.
 */
Rectangle {
    id: root

    property string topLine: ""
    property string mainText: "0"
    property bool failed: false
    property bool hasMemory: false
    property bool showAngle: false
    property string angle: "deg"
    property bool copied: false

    signal copyRequested()
    signal angleToggled()

    color: ClockStyle.colPane
    radius: ClockStyle.radiusCard
    implicitHeight: 176

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.cardPadding - 4
        }
        spacing: ClockStyle.gapTiny

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            // Memory holds a value
            Rectangle {
                visible: root.hasMemory
                implicitWidth: memoryLabel.implicitWidth + ClockStyle.gap * 2
                implicitHeight: 24
                radius: ClockStyle.pill(height)
                color: ClockStyle.colTertiaryContainer

                StyledText {
                    id: memoryLabel
                    anchors.centerIn: parent
                    text: Translation.tr("Memory")
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.Medium
                    color: ClockStyle.colOnTertiaryContainer
                }
            }

            RippleButton {
                visible: root.showAngle
                focusPolicy: Qt.NoFocus
                implicitWidth: angleLabel.implicitWidth + ClockStyle.gap * 2
                implicitHeight: 24
                buttonRadius: ClockStyle.pill(height)
                colBackground: ClockStyle.colSurfaceHigh
                colBackgroundHover: ClockStyle.colSurfaceHover
                colRipple: ClockStyle.colSurfaceActive
                onClicked: root.angleToggled()

                contentItem: Item {
                    StyledText {
                        id: angleLabel
                        anchors.centerIn: parent
                        text: root.angle === "rad" ? Translation.tr("Radians") : Translation.tr("Degrees")
                        font.pixelSize: ClockStyle.textSmall
                        font.weight: Font.Medium
                        color: ClockStyle.colOnSurfaceVariant
                    }
                }

                StyledToolTip {
                    text: Translation.tr("Angle unit for sin, cos and tan")
                }
            }

            Item { Layout.fillWidth: true }

            StyledText {
                visible: root.copied
                text: Translation.tr("Copied")
                font.pixelSize: ClockStyle.textSmall
                color: ClockStyle.colPrimary
            }

            ClockIconButton {
                size: 32
                iconSize: ClockStyle.iconSmall + 2
                symbol: root.copied ? "check" : "content_copy"
                tooltip: Translation.tr("Copy the result")
                focusPolicy: Qt.NoFocus
                onClicked: root.copyRequested()
            }
        }

        Item { Layout.fillHeight: true }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideLeft
            text: root.topLine.length > 0 ? root.topLine : " "
            font.family: ClockStyle.fontNumbers
            font.variableAxes: ClockStyle.axesDigits
            font.pixelSize: ClockStyle.textLarge + 2
            color: ClockStyle.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignRight
            text: root.mainText
            fontSizeMode: root.failed ? Text.FixedSize : Text.HorizontalFit
            minimumPixelSize: 22
            font.family: ClockStyle.fontNumbers
            font.variableAxes: ClockStyle.axesDigitsBold
            font.pixelSize: root.failed ? ClockStyle.textTitle : Math.max(40, Math.min(72, root.height * 0.36))
            color: root.failed ? ClockStyle.colError : ClockStyle.colOnSurface
            wrapMode: Text.NoWrap
        }
    }
}

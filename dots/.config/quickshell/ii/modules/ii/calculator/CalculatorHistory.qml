pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "CalculatorMath.js" as CalcMath

/**
 * The calculations kept by the calculator and the launcher, newest first. A row recalls its
 * expression; the result next to it is inserted on its own. Hover shows copy and delete.
 * It never touches the store: the window answers the signals.
 */
Rectangle {
    id: root

    property var entries: []
    property bool grouping: true

    signal recallRequested(string expression, string result)
    signal resultRequested(string result)
    signal copyRequested(string result)
    signal removeRequested(int index)
    signal clearRequested()
    signal closeRequested()

    color: ClockStyle.colPane
    radius: ClockStyle.radiusCard

    ColumnLayout {
        anchors {
            fill: parent
            margins: ClockStyle.gap
        }
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: ClockStyle.gapSmall
            spacing: ClockStyle.gapSmall

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("History")
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: ClockStyle.textTitle - 2
                color: ClockStyle.colOnSurface
            }

            ClockIconButton {
                visible: root.entries.length > 0
                size: 36
                symbol: "delete_sweep"
                tooltip: Translation.tr("Clear history")
                focusPolicy: Qt.NoFocus
                onClicked: root.clearRequested()
            }

            ClockIconButton {
                size: 36
                symbol: "close"
                tooltip: Translation.tr("Close history")
                focusPolicy: Qt.NoFocus
                onClicked: root.closeRequested()
            }
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.entries.length > 0
            clip: true
            spacing: ClockStyle.gapTiny
            model: root.entries
            boundsBehavior: Flickable.StopAtBounds

            WheelScroll {}

            delegate: Item {
                id: row

                required property var modelData
                required property int index

                readonly property string expression: String(modelData?.expression ?? "")
                readonly property string result: String(modelData?.result ?? "")
                readonly property bool recallable: CalcMath.parses(row.expression)

                width: ListView.view.width
                implicitHeight: 68

                RippleButton {
                    id: rowButton
                    anchors.fill: parent
                    focusPolicy: Qt.NoFocus
                    buttonRadius: ClockStyle.radiusNormal
                    buttonRadiusPressed: ClockStyle.radiusSmall
                    colBackground: "transparent"
                    colBackgroundHover: ClockStyle.colSurfaceHover
                    colRipple: ClockStyle.colSurfaceActive
                    onClicked: row.recallable ? root.recallRequested(row.expression, row.result) : root.resultRequested(row.result)

                    contentItem: Item {
                        ColumnLayout {
                            anchors {
                                fill: parent
                                leftMargin: ClockStyle.gap
                                rightMargin: ClockStyle.gap
                                topMargin: ClockStyle.gapSmall
                                bottomMargin: ClockStyle.gapSmall
                            }
                            spacing: 0

                            StyledText {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideLeft
                                text: CalcMath.prettyExpression(row.expression, root.grouping)
                                font.family: ClockStyle.fontNumbers
                                font.variableAxes: ClockStyle.axesDigits
                                font.pixelSize: ClockStyle.textNormal
                                color: ClockStyle.colSubtext
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: ClockStyle.gapSmall

                                // Hover actions sit on the left so the result keeps its place
                                Row {
                                    spacing: 0
                                    opacity: rowButton.hovered ? 1 : 0
                                    Behavior on opacity {
                                        enabled: !ClockStyle.reducedMotion
                                        NumberAnimation { duration: 90 }
                                    }

                                    ClockIconButton {
                                        size: 28
                                        iconSize: ClockStyle.iconSmall + 1
                                        symbol: "content_copy"
                                        tooltip: Translation.tr("Copy the result")
                                        focusPolicy: Qt.NoFocus
                                        onClicked: root.copyRequested(row.result)
                                    }

                                    ClockIconButton {
                                        size: 28
                                        iconSize: ClockStyle.iconSmall + 1
                                        symbol: "delete"
                                        tooltip: Translation.tr("Remove")
                                        focusPolicy: Qt.NoFocus
                                        onClicked: root.removeRequested(row.index)
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                    text: "= " + CalcMath.prettyNumber(row.result, root.grouping)
                                    font.family: ClockStyle.fontNumbers
                                    font.variableAxes: ClockStyle.axesDigitsBold
                                    font.pixelSize: ClockStyle.textLarge + 4
                                    color: ClockStyle.colOnSurface
                                }
                            }
                        }
                    }
                }
            }
        }

        ClockEmptyState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.entries.length === 0
            symbol: "history"
            shape: "Cookie9Sided"
            shapeSize: ClockStyle.emptyShapeSmall
            title: Translation.tr("Nothing yet")
            subtitle: Translation.tr("Finished calculations appear here, shared with the launcher.")
        }
    }
}

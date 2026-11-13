pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** Search results remain a focused list; article state is owned by the reader page. */
Item {
    id: root

    readonly property var svc: WikipediaService
    property bool compact: false

    ColumnLayout {
        anchors.fill: parent
        spacing: ClockStyle.paneGap

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gap

            MaterialSymbol {
                text: "travel_explore"
                iconSize: ClockStyle.iconLarge
                color: ClockStyle.colPrimary
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    text: root.svc.query.length > 0
                        ? Translation.tr("Results for “%1”").arg(root.svc.query)
                        : Translation.tr("Find an article")
                    color: ClockStyle.colOnBackground
                    font.family: ClockStyle.fontTitle
                    font.variableAxes: ClockStyle.axesTitle
                    font.pixelSize: ClockStyle.textTitle
                    elide: Text.ElideRight
                }

                StyledText {
                    text: Translation.tr("Search the %1 Wikipedia").arg(root.svc.language.toUpperCase())
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textNormal
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: ClockStyle.radiusCard
            color: ClockStyle.colPane
            clip: true

            ListView {
                id: resultsList
                anchors.fill: parent
                anchors.margins: ClockStyle.gapSmall
                clip: true
                spacing: ClockStyle.gapTiny
                boundsBehavior: Flickable.StopAtBounds
                model: root.svc.results
                WheelScroll {}

                delegate: Rectangle {
                    id: resultRow
                    required property var modelData
                    width: resultsList.width
                    implicitHeight: resultBody.implicitHeight + ClockStyle.gapLarge
                    radius: ClockStyle.radiusLarge
                    color: resultHover.containsMouse ? ClockStyle.colSurfaceHover : "transparent"

                    ColumnLayout {
                        id: resultBody
                        anchors {
                            left: parent.left
                            right: parent.right
                            top: parent.top
                            margins: ClockStyle.gap
                        }
                        spacing: ClockStyle.gapTiny

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: ClockStyle.gapSmall

                            StyledText {
                                Layout.fillWidth: true
                                text: resultRow.modelData.title
                                color: ClockStyle.colOnSurface
                                font.family: ClockStyle.fontTitle
                                font.pixelSize: ClockStyle.textLarge
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }

                            MaterialSymbol {
                                text: "arrow_forward"
                                iconSize: ClockStyle.iconNormal
                                color: ClockStyle.colPrimary
                            }
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: resultRow.modelData.snippet.length > 0
                            text: resultRow.modelData.snippet
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textNormal
                            wrapMode: Text.WordWrap
                            maximumLineCount: root.compact ? 2 : 3
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: resultHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.svc.open(resultRow.modelData.title)
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(460, parent.width - ClockStyle.gapHuge * 2)
                    spacing: ClockStyle.gap
                    visible: root.svc.results.length === 0
                        && !root.svc.searching && root.svc.searchError.length === 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.svc.query.length > 0 ? "search_off" : "search"
                        iconSize: 44
                        color: ClockStyle.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.svc.query.length > 0
                            ? Translation.tr("No articles matched. Try a broader phrase.")
                            : Translation.tr("Type a title or topic above, then press Enter.")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textNormal
                        wrapMode: Text.WordWrap
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(460, parent.width - ClockStyle.gapHuge * 2)
                    spacing: ClockStyle.gap
                    visible: root.svc.searching

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "hourglass_top"
                        iconSize: 44
                        color: ClockStyle.colPrimary
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: Translation.tr("Searching…")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textNormal
                    }
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(520, parent.width - ClockStyle.gapHuge * 2)
                    spacing: ClockStyle.gap
                    visible: !root.svc.searching && root.svc.searchError.length > 0

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "cloud_off"
                        iconSize: 44
                        color: ClockStyle.colError
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: root.svc.searchError
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textNormal
                        wrapMode: Text.WordWrap
                    }

                    ClockButton {
                        Layout.alignment: Qt.AlignHCenter
                        symbol: "refresh"
                        label: Translation.tr("Try again")
                        variant: "tonal"
                        enabled: root.svc.query.length > 0
                        onClicked: root.svc.retrySearch()
                    }
                }
            }
        }
    }
}

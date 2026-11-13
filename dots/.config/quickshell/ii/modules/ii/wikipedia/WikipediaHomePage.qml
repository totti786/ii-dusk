pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A quiet, useful home: the official daily feed first, then a compact reading list. */
Item {
    id: root

    readonly property var svc: WikipediaService
    property bool compact: false
    property bool featureImageFailed: false
    readonly property bool dense: root.compact || root.width < 900

    readonly property var topics: [
        Translation.tr("Science"),
        Translation.tr("History"),
        Translation.tr("Art"),
        Translation.tr("Nature"),
        Translation.tr("Technology")
    ]

    function openFeatured(): void {
        if (root.svc.homeArticle)
            root.svc.open(root.svc.homeArticle.title);
    }

    Flickable {
        id: scroll
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: body.implicitHeight + ClockStyle.gapHuge
        WheelScroll {}

        ColumnLayout {
            id: body
            width: scroll.width
            spacing: ClockStyle.paneGap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gap

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Discover Wikipedia")
                        color: ClockStyle.colOnBackground
                        font.family: ClockStyle.fontTitle
                        font.variableAxes: ClockStyle.axesTitle
                        font.pixelSize: ClockStyle.textTitle
                    }

                    StyledText {
                        text: root.svc.homeDate.length > 0
                            ? Translation.tr("Official daily feed · %1").arg(root.svc.homeDate)
                            : Translation.tr("The free encyclopedia, in your language")
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textNormal
                    }
                }

                ClockButton {
                    symbol: "casino"
                    label: Translation.tr("Random")
                    variant: "text"
                    onClicked: root.svc.random()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.svc.homeLoading || root.svc.homeError.length > 0
                implicitHeight: stateColumn.implicitHeight + ClockStyle.cardPadding * 2
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane

                ColumnLayout {
                    id: stateColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: ClockStyle.cardPadding
                    }
                    spacing: ClockStyle.gapSmall

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: ClockStyle.gap

                        MaterialSymbol {
                            text: root.svc.homeLoading ? "hourglass_top" : "cloud_off"
                            iconSize: ClockStyle.iconLarge
                            color: root.svc.homeLoading ? ClockStyle.colPrimary : ClockStyle.colError
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            StyledText {
                                Layout.fillWidth: true
                                text: root.svc.homeLoading
                                    ? Translation.tr("Loading today's feed…")
                                    : Translation.tr("Today's feed is unavailable")
                                color: ClockStyle.colOnSurface
                                font.family: ClockStyle.fontTitle
                                font.pixelSize: ClockStyle.textLarge
                            }

                            StyledText {
                                Layout.fillWidth: true
                                visible: root.svc.homeError.length > 0
                                text: root.svc.homeError
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                                wrapMode: Text.WordWrap
                            }
                        }

                        ClockButton {
                            visible: !root.svc.homeLoading
                            symbol: "refresh"
                            label: Translation.tr("Try again")
                            variant: "tonal"
                            onClicked: root.svc.retryHome()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.svc.homeArticle !== null
                implicitHeight: root.dense ? 190 : Math.max(210,
                    featureBody.implicitHeight + ClockStyle.cardPadding * 2)
                radius: ClockStyle.radiusCard
                color: ClockStyle.colPane
                clip: true

                RowLayout {
                    id: featureBody
                    anchors {
                        fill: parent
                        margins: root.dense ? ClockStyle.gap : ClockStyle.cardPadding
                    }
                    spacing: ClockStyle.gapLarge

                    Rectangle {
                        Layout.preferredWidth: Math.min(330, Math.max(170, root.width * 0.34))
                        Layout.fillHeight: true
                        Layout.minimumHeight: root.dense ? 136 : 170
                        radius: ClockStyle.radiusLarge
                        color: ClockStyle.colSurface
                        clip: true

                        Image {
                            anchors.fill: parent
                            visible: String(root.svc.homeArticle?.thumbnail ?? "").length > 0
                            source: root.svc.homeArticle?.thumbnail ?? ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: true
                            sourceSize.width: 720
                            sourceSize.height: 480
                            onSourceChanged: root.featureImageFailed = false
                            onStatusChanged: if (status === Image.Error) root.featureImageFailed = true
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            visible: (root.svc.homeArticle?.thumbnail ?? "").length === 0 || root.featureImageFailed
                            spacing: ClockStyle.gapSmall

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignHCenter
                                text: "menu_book"
                                iconSize: 48
                                color: ClockStyle.colPrimary
                            }

                            StyledText {
                                text: Translation.tr("Featured article")
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        spacing: ClockStyle.gapSmall

                        StyledText {
                            text: Translation.tr("Featured article")
                            color: ClockStyle.colPrimary
                            font.pixelSize: ClockStyle.textSmall
                            font.weight: Font.DemiBold
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.svc.homeArticle?.title ?? ""
                            color: ClockStyle.colOnSurface
                            font.family: ClockStyle.fontTitle
                            font.variableAxes: ClockStyle.axesTitle
                            font.pixelSize: ClockStyle.textTitle
                            wrapMode: Text.WordWrap
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: !root.dense && (root.svc.homeArticle?.description ?? "").length > 0
                            text: root.svc.homeArticle?.description ?? ""
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textNormal
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.svc.homeArticle?.extract ?? ""
                            color: ClockStyle.colOnSurfaceVariant
                            font.pixelSize: ClockStyle.textSmall
                            wrapMode: Text.WordWrap
                            maximumLineCount: root.dense ? 3 : 5
                            elide: Text.ElideRight
                        }

                        Item { Layout.fillHeight: true }

                        ClockButton {
                            symbol: "menu_book"
                            label: Translation.tr("Read article")
                            variant: "tonal"
                            onClicked: root.openFeatured()
                        }
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                visible: root.svc.mostRead.length > 0
                title: Translation.tr("Most read")
                symbol: "trending_up"
                count: root.svc.mostRead.length
                shape: MaterialShape.Shape.Cookie7Sided

                Repeater {
                    model: root.svc.mostRead

                    Rectangle {
                        id: mostReadRow
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        implicitHeight: 54
                        radius: ClockStyle.radiusSmall
                        color: hover.containsMouse ? ClockStyle.colSurfaceHover : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: ClockStyle.gapSmall
                            anchors.rightMargin: ClockStyle.gapSmall
                            spacing: ClockStyle.gap

                            StyledText {
                                Layout.preferredWidth: 28
                                text: String(mostReadRow.index + 1).padStart(2, "0")
                                color: ClockStyle.colPrimary
                                font.family: ClockStyle.fontNumbers
                                font.pixelSize: ClockStyle.textNormal
                                font.weight: Font.DemiBold
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: modelData.title
                                color: ClockStyle.colOnSurface
                                font.pixelSize: ClockStyle.textNormal
                                elide: Text.ElideRight
                            }

                            StyledText {
                                visible: modelData.views > 0
                                text: Translation.tr("%1 views").arg(String(modelData.views))
                                color: ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                            }
                        }

                        MouseArea {
                            id: hover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.svc.open(modelData.title)
                        }
                    }
                }
            }

            ClockPane {
                Layout.fillWidth: true
                title: Translation.tr("Explore a topic")
                symbol: "explore"
                shape: MaterialShape.Shape.Clover4Leaf

                Flow {
                    Layout.fillWidth: true
                    spacing: ClockStyle.gapSmall

                    Repeater {
                        model: root.topics

                        ClockButton {
                            required property string modelData
                            symbol: "search"
                            label: modelData
                            variant: "text"
                            onClicked: root.svc.search(modelData)
                        }
                    }
                }
            }

            Item { Layout.preferredHeight: ClockStyle.gapHuge }
        }
    }
}

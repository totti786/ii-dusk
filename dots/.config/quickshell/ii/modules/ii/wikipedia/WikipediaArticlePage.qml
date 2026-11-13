pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** A readable native article surface with a deliberately narrow measure. */
Item {
    id: root

    readonly property var svc: WikipediaService
    readonly property int readerFontSize: Number(root.svc.readerFontSize ?? 18)
    property bool compact: false

    function openReadingSettings(anchor, popupParent): void {
        if (anchor) {
            readingPopup.anchorItem = anchor;
            readingPopup.popupParent = popupParent ?? root;
        }
        readingPopup.open();
    }

    Flickable {
        id: articleScroll
        anchors.fill: parent
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: articleColumn.implicitHeight + ClockStyle.gapHuge
        visible: root.svc.article !== null
        WheelScroll {}

        ColumnLayout {
            id: articleColumn
            width: Math.min(780, Math.max(0, articleScroll.width - ClockStyle.gapHuge * 2))
            x: Math.max(ClockStyle.gap, (articleScroll.width - width) / 2)
            spacing: ClockStyle.gap

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Article")
                    color: ClockStyle.colPrimary
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.DemiBold
                }

                StyledText {
                    visible: root.svc.article?.language.length > 0
                    text: root.svc.article?.language.toUpperCase() ?? ""
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    font.weight: Font.DemiBold
                }
            }

            StyledText {
                Layout.fillWidth: true
                text: root.svc.article?.title ?? ""
                color: ClockStyle.colOnSurface
                font.family: ClockStyle.fontTitle
                font.variableAxes: ClockStyle.axesTitle
                font.pixelSize: root.compact ? ClockStyle.textTitle : ClockStyle.textTitle + 8
                wrapMode: Text.WordWrap
            }

            StyledText {
                Layout.fillWidth: true
                visible: (root.svc.article?.description ?? "").length > 0
                text: root.svc.article?.description ?? ""
                color: ClockStyle.colPrimary
                font.pixelSize: ClockStyle.textLarge
                font.weight: Font.Medium
                wrapMode: Text.WordWrap
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(300, Math.max(170, articleColumn.width * 0.38))
                visible: (root.svc.article?.thumbnail ?? "").length > 0
                radius: ClockStyle.radiusLarge
                color: ClockStyle.colSurface
                clip: true

                Image {
                    anchors.fill: parent
                    source: root.svc.article?.thumbnail ?? ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: true
                    sourceSize.width: 1200
                    sourceSize.height: 720
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Math.max(48, bodyText.contentHeight + ClockStyle.gap)
                radius: ClockStyle.radiusSmall
                color: "transparent"

                TextEdit {
                    id: bodyText
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                    }
                    height: Math.max(48, contentHeight)
                    text: root.svc.article?.extract ?? ""
                    readOnly: true
                    selectByMouse: true
                    persistentSelection: true
                    wrapMode: TextEdit.Wrap
                    textFormat: TextEdit.PlainText
                    color: ClockStyle.colOnSurface
                    selectionColor: ClockStyle.colPrimaryContainer
                    selectedTextColor: ClockStyle.colOnPrimaryContainer
                    font.family: ClockStyle.fontMain
                    font.pixelSize: root.readerFontSize
                    cursorVisible: activeFocus
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                ClockButton {
                    id: readingButton
                    symbol: "format_size"
                    label: Translation.tr("Aa")
                    variant: "text"
                    Accessible.name: Translation.tr("Reading size")
                    onClicked: root.openReadingSettings(readingButton, root)
                }

                ClockButton {
                    symbol: "open_in_new"
                    label: Translation.tr("Open on Wikipedia")
                    variant: "tonal"
                    onClicked: root.svc.openInBrowser()
                }

                ClockButton {
                    symbol: "content_copy"
                    label: Translation.tr("Copy link")
                    variant: "text"
                    onClicked: root.svc.copyLink()
                }

                Item { Layout.fillWidth: true }
            }

            Item { Layout.preferredHeight: ClockStyle.gapHuge }
        }
    }

    WikipediaReadingPopup {
        id: readingPopup
        anchorItem: readingButton
        popupParent: root
        fontSize: root.readerFontSize
        minimumFontSize: Number(root.svc.readerFontSizeMin ?? 14)
        maximumFontSize: Number(root.svc.readerFontSizeMax ?? 28)
        defaultFontSize: Number(root.svc.readerFontSizeDefault ?? 18)
        onFontSizeSelected: value => {
            if (typeof root.svc.setReaderFontSize === "function")
                root.svc.setReaderFontSize(value);
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(520, parent.width - ClockStyle.gapHuge * 2)
        spacing: ClockStyle.gap
        visible: !root.svc.articleLoading && root.svc.article === null && root.svc.articleError.length === 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "menu_book"
            iconSize: 48
            color: ClockStyle.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Choose an article to start reading.")
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textNormal
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(520, parent.width - ClockStyle.gapHuge * 2)
        spacing: ClockStyle.gap
        visible: root.svc.articleLoading

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "hourglass_top"
            iconSize: 48
            color: ClockStyle.colPrimary
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: Translation.tr("Fetching the article…")
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textNormal
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(520, parent.width - ClockStyle.gapHuge * 2)
        spacing: ClockStyle.gap
        visible: !root.svc.articleLoading && root.svc.articleError.length > 0

        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: "cloud_off"
            iconSize: 48
            color: ClockStyle.colError
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.svc.articleError
            color: ClockStyle.colSubtext
            font.pixelSize: ClockStyle.textNormal
            wrapMode: Text.WordWrap
        }

        ClockButton {
            Layout.alignment: Qt.AlignHCenter
            symbol: "refresh"
            label: Translation.tr("Try again")
            variant: "tonal"
            onClicked: root.svc.retryArticle()
        }
    }
}

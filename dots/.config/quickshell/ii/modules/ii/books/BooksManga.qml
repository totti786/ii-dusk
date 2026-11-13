pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One manga opened from the Manga source: cover and summary on the left, chapters on
 * the right. Each chapter is downloaded directly from MangaDex as a CBZ into the library.
 */
Item {
    id: root

    property var detail: null
    property string filter: ""
    property bool confirmAll: false

    signal openPath(string path)

    readonly property var chapters: {
        const needle = root.filter.trim().toLowerCase();
        const list = root.detail?.chapters ?? [];
        if (needle.length === 0)
            return list;
        return list.filter(chapter => String(chapter.name ?? "").toLowerCase().includes(needle)
            || String(chapter.volume ?? "").toLowerCase().includes(needle));
    }
    readonly property string allHref: root.detail ? "manga-dl:" + root.detail.mangaId + ":all" : ""
    readonly property var allDownload: BooksService.downloads[root.allHref] ?? null

    function downloadChapter(chapter): void {
        BooksService.download(root.detail, {
            "href": chapter.href,
            "ext": "cbz",
            "size": 0,
            "label": chapter.name
        });
    }

    function downloadAll(): void {
        BooksService.download(root.detail, {
            "href": root.allHref,
            "ext": "cbz",
            "size": 0,
            "label": Translation.tr("All chapters")
        });
    }

    function stateFor(href): var {
        return BooksService.downloads[href] ?? null;
    }

    onDetailChanged: {
        root.filter = "";
        root.confirmAll = false;
    }

    RowLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 26

        // ── Cover and blurb ─────────────────────────────────────────────
        ColumnLayout {
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            spacing: 8

            BookCover {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 210
                Layout.preferredHeight: 315
                source: root.detail?.cover ?? ""
                title: root.detail?.title ?? ""
                format: ""
            }

            StyledText {
                Layout.fillWidth: true
                text: root.detail?.author ?? ""
                color: ClockStyle.colPrimary
                font.pixelSize: ClockStyle.textNormal
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                text: [root.detail?.year ? String(root.detail.year) : "",
                    root.detail?.status ?? "",
                    root.detail?.source ?? ""]
                    .filter(part => String(part).length > 0).join("  ·  ")
                color: ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }

            Flickable {
                WheelScroll {}
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentWidth: width
                contentHeight: summary.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                visible: summary.text.length > 0

                StyledText {
                    id: summary
                    width: parent.width
                    text: root.detail?.summary ?? ""
                    color: ClockStyle.colOnSurface
                    font.pixelSize: ClockStyle.textSmall
                    lineHeight: 1.25
                    wrapMode: Text.WordWrap
                }
            }

            ClockButton {
                Layout.fillWidth: true
                symbol: "open_in_new"
                label: Translation.tr("Open on MangaDex")
                enabled: (root.detail?.url ?? "").length > 0
                onClicked: Quickshell.execDetached(["xdg-open", root.detail.url])
            }
        }

        // ── Chapters ────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: ClockStyle.gapSmall

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    StyledText {
                        Layout.fillWidth: true
                        text: root.detail?.title ?? ""
                        color: ClockStyle.colOnSurface
                        font.pixelSize: ClockStyle.textLarge
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        text: Translation.tr("%1 chapters").arg((root.detail?.chapters ?? []).length)
                        color: ClockStyle.colSubtext
                        font.pixelSize: ClockStyle.textSmall
                    }
                }

                ClockButton {
                    symbol: root.allDownload?.state === "running" ? "hourglass_top" : "download"
                    label: {
                        if (root.allDownload?.state === "running")
                            return Translation.tr("Downloading…");
                        if (root.confirmAll)
                            return Translation.tr("Download all %1?").arg((root.detail?.chapters ?? []).length);
                        if (root.allDownload?.state === "done")
                            return Translation.tr("Download again");
                        return Translation.tr("Download all");
                    }
                    variant: root.confirmAll ? "filled" : "tonal"
                    enabled: root.allDownload?.state !== "running" && (root.detail?.chapters ?? []).length > 0
                    onClicked: {
                        if (root.allDownload?.state === "done") {
                            root.downloadAll();
                            return;
                        }
                        if (root.confirmAll) {
                            root.confirmAll = false;
                            root.downloadAll();
                        } else {
                            root.confirmAll = true;
                            confirmTimer.restart();
                        }
                    }
                }

                ClockButton {
                    visible: root.allDownload?.state === "done"
                    symbol: "menu_book"
                    label: Translation.tr("Read first")
                    variant: "filled"
                    onClicked: root.openPath(root.allDownload.path)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 44
                radius: ClockStyle.radiusLarge
                color: filterInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

                MaterialSymbol {
                    anchors {
                        left: parent.left
                        leftMargin: 14
                        verticalCenter: parent.verticalCenter
                    }
                    text: "search"
                    iconSize: 19
                    color: ClockStyle.colSubtext
                }

                StyledTextInput {
                    id: filterInput
                    anchors {
                        fill: parent
                        leftMargin: 44
                        rightMargin: 14
                    }
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: ClockStyle.colOnSurface
                    onTextChanged: root.filter = text
                }

                StyledText {
                    anchors {
                        fill: parent
                        leftMargin: 44
                        rightMargin: 14
                    }
                    verticalAlignment: Text.AlignVCenter
                    visible: filterInput.text.length === 0
                    text: Translation.tr("Filter chapters")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textNormal
                }
            }

            ListView {
                id: chapterList
                WheelScroll {}
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 3
                boundsBehavior: Flickable.StopAtBounds
                model: root.chapters
                visible: root.chapters.length > 0

                delegate: Rectangle {
                    id: chapterRow
                    required property var modelData

                    readonly property var transfer: root.stateFor(modelData.href)

                    width: chapterList.width
                    implicitHeight: 56
                    radius: ClockStyle.radiusSmall
                    color: chapterMouse.containsMouse ? ClockStyle.colSurfaceHover : "transparent"

                    MouseArea {
                        id: chapterMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 10

                        MaterialSymbol {
                            text: "menu_book"
                            iconSize: 20
                            color: ClockStyle.colSubtext
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            StyledText {
                                Layout.fillWidth: true
                                text: chapterRow.modelData.name
                                color: ClockStyle.colOnSurface
                                font.pixelSize: ClockStyle.textNormal
                                elide: Text.ElideRight
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: [chapterRow.modelData.volume,
                                    chapterRow.modelData.pages > 0
                                        ? Translation.tr("%1 pages").arg(chapterRow.modelData.pages) : "",
                                    chapterRow.transfer?.state === "running"
                                        ? Translation.tr("Downloading…") : "",
                                    chapterRow.transfer?.state === "error"
                                        ? (chapterRow.transfer?.error ?? Translation.tr("Download failed")) : ""]
                                    .filter(part => String(part).length > 0).join("  ·  ")
                                color: chapterRow.transfer?.state === "error"
                                    ? ClockStyle.colError : ClockStyle.colSubtext
                                font.pixelSize: ClockStyle.textSmall
                                elide: Text.ElideRight
                            }
                        }

                        ClockButton {
                            visible: chapterRow.transfer?.state !== "done"
                            symbol: chapterRow.transfer?.state === "running" ? "hourglass_top"
                                : chapterRow.transfer?.state === "error" ? "refresh" : "download"
                            label: chapterRow.transfer?.state === "running" ? Translation.tr("Downloading…")
                                : chapterRow.transfer?.state === "error" ? Translation.tr("Retry")
                                : Translation.tr("Download")
                            enabled: chapterRow.transfer?.state !== "running"
                            onClicked: root.downloadChapter(chapterRow.modelData)
                        }

                        ClockButton {
                            visible: chapterRow.transfer?.state === "done"
                            symbol: "menu_book"
                            label: Translation.tr("Read")
                            variant: "filled"
                            onClicked: root.openPath(chapterRow.transfer.path)
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.chapters.length === 0
                spacing: ClockStyle.gap

                ClockEmptyState {
                    Layout.alignment: Qt.AlignHCenter
                    symbol: root.filter.length > 0 ? "search_off" : "auto_stories"
                    title: root.filter.length > 0
                        ? Translation.tr("No chapters match")
                        : Translation.tr("No chapters available")
                    subtitle: root.filter.length > 0
                        ? Translation.tr("Clear the filter to see them all.")
                        : Translation.tr("MangaDex may have removed the chapters for this title, or the API could not list them.")
                }
            }
        }
    }

    Timer {
        id: confirmTimer
        interval: 3200
        onTriggered: root.confirmAll = false
    }
}

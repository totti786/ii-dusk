pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import "./WikipediaLogic.js" as WikiLogic

/** A searchable, keyboard-friendly language picker for the selected Wikipedia. */
Popup {
    id: root

    objectName: "wikipediaLanguagePopup"

    property Item anchorItem: null
    property Item popupParent: null
    property string selectedCode: "en"
    property var languages: []

    signal languageSelected(string code)

    readonly property var filteredLanguages: WikiLogic.languageSearchResults(root.languages, searchInput.text)
    readonly property int selectedIndex: {
        const code = root.selectedCode.toLowerCase();
        return root.filteredLanguages.findIndex(option => option.code === code);
    }
    property point anchorPoint: Qt.point(0, 0)
    readonly property real desiredY: root.anchorPoint.y + (root.anchorItem?.height ?? 0) + ClockStyle.gapSmall

    parent: root.popupParent ?? root.anchorItem?.parent ?? null
    width: Math.min(380, Math.max(300, (root.popupParent?.width ?? 760) - 24))
    height: Math.min(460, Math.max(320, (root.popupParent?.height ?? 520) - 80))
    // The trigger lives in the top bar's trailing action row. Right-aligning the sheet
    // keeps it on-screen at compact widths even while the top bar is relaid out.
    x: Math.max(8, (root.popupParent?.width ?? root.width) - root.width - 8)
    y: Math.max(8, Math.min(root.desiredY,
        (root.popupParent?.height ?? root.height) - root.height - 8))
    padding: ClockStyle.gap
    modal: false
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

    function selectLanguage(code): void {
        const normalized = WikiLogic.normalizeLanguage(code);
        if (normalized.length === 0)
            return;
        root.languageSelected(normalized);
        root.close();
    }

    function updateAnchorPoint(): void {
        if (root.anchorItem && root.popupParent)
            root.anchorPoint = root.anchorItem.mapToItem(root.popupParent, 0, 0);
    }

    function focusList(): void {
        if (root.filteredLanguages.length === 0)
            return;
        languageList.currentIndex = root.selectedIndex >= 0 ? root.selectedIndex : 0;
        languageList.forceActiveFocus();
        languageList.positionViewAtIndex(languageList.currentIndex, ListView.Contain);
    }

    function acceptSearch(): void {
        const needle = searchInput.text.trim();
        const highlightedIndex = languageList.currentIndex >= 0 ? languageList.currentIndex : -1;
        const code = WikiLogic.languageSelection(root.languages, needle, highlightedIndex);
        if (code.length > 0)
            root.selectLanguage(code);
    }

    onOpened: {
        root.updateAnchorPoint();
        Qt.callLater(() => {
            root.updateAnchorPoint();
            searchInput.forceActiveFocus();
            searchInput.selectAll();
        });
    }

    onClosed: {
        searchInput.text = "";
        languageList.currentIndex = -1;
    }

    background: Rectangle {
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colSheet
        border.width: 1
        border.color: ClockStyle.colOutline
    }

    contentItem: ColumnLayout {
        spacing: ClockStyle.gapSmall

        RowLayout {
            Layout.fillWidth: true
            spacing: ClockStyle.gapSmall

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Wikipedia language")
                    color: ClockStyle.colOnSurface
                    font.family: ClockStyle.fontTitle
                    font.pixelSize: ClockStyle.textLarge
                    font.weight: Font.DemiBold
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Choose a language or enter its code")
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textSmall
                    elide: Text.ElideRight
                }
            }

            ClockIconButton {
                symbol: "close"
                tooltip: Translation.tr("Close language picker")
                Accessible.name: Translation.tr("Close language picker")
                onClicked: root.close()
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 44
            radius: ClockStyle.pill(implicitHeight)
            color: searchInput.activeFocus ? ClockStyle.colFieldHover : ClockStyle.colField

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: ClockStyle.gapSmall
                anchors.rightMargin: ClockStyle.gapTiny
                spacing: ClockStyle.gapSmall

                MaterialSymbol {
                    text: "search"
                    iconSize: ClockStyle.iconNormal
                    color: ClockStyle.colSubtext
                }

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    StyledTextInput {
                        id: searchInput
                        anchors.fill: parent
                        activeFocusOnTab: true
                        clip: true
                        selectByMouse: true
                        verticalAlignment: TextInput.AlignVCenter
                        color: ClockStyle.colOnSurface
                        font.pixelSize: ClockStyle.textNormal
                        Accessible.name: Translation.tr("Search Wikipedia languages")
                        onAccepted: root.acceptSearch()
                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Escape) {
                                root.close();
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down) {
                                root.focusList();
                                event.accepted = true;
                            }
                        }

                        StyledText {
                            anchors.fill: parent
                            visible: searchInput.text.length === 0
                            verticalAlignment: Text.AlignVCenter
                            text: Translation.tr("Search languages or enter a code")
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textNormal
                        }
                    }
                }

                ClockIconButton {
                    visible: searchInput.text.length > 0
                    symbol: "close"
                    tooltip: Translation.tr("Clear language search")
                    Accessible.name: Translation.tr("Clear language search")
                    onClicked: {
                        searchInput.text = "";
                        searchInput.forceActiveFocus();
                    }
                }
            }
        }

        ListView {
            id: languageList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: ClockStyle.gapTiny
            boundsBehavior: Flickable.StopAtBounds
            keyNavigationEnabled: true
            model: root.filteredLanguages
            currentIndex: root.selectedIndex
            Accessible.name: Translation.tr("Wikipedia languages")

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    if (languageList.currentIndex >= 0 && languageList.currentIndex < root.filteredLanguages.length)
                        root.selectLanguage(root.filteredLanguages[languageList.currentIndex].code);
                    event.accepted = true;
                }
            }

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
            }

            delegate: Rectangle {
                id: languageRow
                required property var modelData
                required property int index

                width: languageList.width
                implicitHeight: 56
                radius: ClockStyle.radiusSmall
                color: languageRow.modelData.code === root.selectedCode
                    ? (languageHover.containsMouse ? ClockStyle.colPrimaryContainerHover : ClockStyle.colPrimaryContainer)
                    : (languageHover.containsMouse ? ClockStyle.colSurfaceHover : "transparent")
                Accessible.name: languageRow.modelData.nativeName + " / "
                    + languageRow.modelData.englishName + " ("
                    + languageRow.modelData.code.toUpperCase() + ")"

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: ClockStyle.gapSmall
                    anchors.rightMargin: ClockStyle.gapSmall
                    spacing: ClockStyle.gapSmall

                    MaterialSymbol {
                        Layout.preferredWidth: 24
                        text: languageRow.modelData.custom ? "code" : "language"
                        iconSize: ClockStyle.iconNormal
                        color: languageRow.modelData.code === root.selectedCode
                            ? ClockStyle.colPrimary : ClockStyle.colSubtext
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: languageRow.modelData.nativeName
                            color: ClockStyle.colOnSurface
                            font.pixelSize: ClockStyle.textNormal
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: languageRow.modelData.nativeName === languageRow.modelData.englishName
                                ? languageRow.modelData.code.toUpperCase()
                                : languageRow.modelData.englishName + " · " + languageRow.modelData.code.toUpperCase()
                            color: ClockStyle.colSubtext
                            font.pixelSize: ClockStyle.textSmall
                            elide: Text.ElideRight
                        }
                    }

                    MaterialSymbol {
                        visible: languageRow.modelData.code === root.selectedCode
                        text: "check"
                        iconSize: ClockStyle.iconNormal
                        color: ClockStyle.colPrimary
                    }
                }

                MouseArea {
                    id: languageHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: languageList.currentIndex = languageRow.index
                    onClicked: root.selectLanguage(languageRow.modelData.code)
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.selectLanguage(languageRow.modelData.code);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.close();
                        event.accepted = true;
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - ClockStyle.gapHuge
                spacing: ClockStyle.gapSmall
                visible: languageList.count === 0

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "search_off"
                    iconSize: ClockStyle.iconLarge
                    color: ClockStyle.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("No matching language code")
                    horizontalAlignment: Text.AlignHCenter
                    color: ClockStyle.colSubtext
                    font.pixelSize: ClockStyle.textNormal
                }
            }
        }
    }
}

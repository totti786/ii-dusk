pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Native anime provider flow: search -> exact provider title -> exact episode -> mpv.
 * The provider ids are carried all the way to the backend, so a similarly named result
 * cannot silently turn into another show. This component never opens a terminal picker.
 */
FocusScope {
    id: root
    focus: true
    activeFocusOnTab: true

    signal closeRequested()
    signal streamStarted()

    // Kept as inputs for the two existing callers. A local library title is prefilled as a
    // search query; its local id is never guessed to be a provider id.
    property bool searchMode: true
    property string titleId: ""
    property string titleLabel: ""
    property string defaultSeason: ""
    property string defaultEpisode: ""
    property string initialQuery: ""
    property bool autoSearch: false
    property int anilistId: 0
    property int anilistSeason: 0
    property int anilistTotal: 0

    property string query: ""
    property string screen: "search"
    property var selectedShow: ({})
    property string quality: "best"
    property bool dub: false
    readonly property var results: MediatorService.providerSearchResults
    readonly property var episodes: MediatorService.providerEpisodes
    readonly property bool busy: MediatorService.providerSearchBusy || MediatorService.providerEpisodesBusy
        || MediatorService.streamResolving

    function search(): void {
        if (root.busy) {
            MediatorService.providerSearchError = "Wait for the current anime request to finish.";
            return;
        }
        const text = String(queryField.text ?? "").trim();
        if (text === "") {
            MediatorService.providerSearchError = "Enter an anime title to search.";
            return;
        }
        if (root.initialQuery !== "" && text !== root.initialQuery.trim()) {
            // A new query is no longer necessarily the AniList entry the hub opened;
            // do not attach that media id to a different show.
            root.anilistId = 0;
            root.anilistSeason = 0;
            root.anilistTotal = 0;
        }
        root.query = text;
        root.screen = "search";
        root.selectedShow = ({});
        MediatorService.searchProvider(text);
    }

    function selectShow(show): void {
        if (root.busy || !show || !show.id)
            return;
        root.selectedShow = show;
        root.screen = "episodes";
        MediatorService.streamError = "";
        MediatorService.streamMessage = "";
        MediatorService.loadProviderEpisodes(show);
    }

    function backToSearch(): void {
        if (root.busy)
            return;
        root.screen = "search";
        root.selectedShow = ({});
        MediatorService.providerEpisodes = [];
        MediatorService.providerEpisodesError = "";
        queryField.input.forceActiveFocus();
    }

    function playEpisode(episode): void {
        if (root.busy || !root.selectedShow?.id || !episode?.id)
            return;
        MediatorService.playProviderEpisode(root.selectedShow.id, episode.id,
                                            root.selectedShow.title ?? "", root.dub,
                                            root.quality.trim() || "best",
                                            root.selectedShow.poster ?? "", true,
                                            root.anilistId, root.anilistSeason,
                                            root.anilistTotal);
    }

    function focusInitialField(): void {
        queryField.input.forceActiveFocus();
        queryField.input.selectAll();
    }

    Component.onCompleted: {
        MediatorService.clearProviderSearch();
        root.query = root.searchMode ? root.initialQuery : root.titleLabel;
        queryField.text = root.query;
        Qt.callLater(root.focusInitialField);
        if (root.searchMode && root.autoSearch && root.initialQuery.trim() !== "")
            Qt.callLater(root.search);
    }

    Keys.onEscapePressed: event => {
        if (event.key === Qt.Key_Escape) {
            if (root.screen === "episodes" && !root.busy)
                root.backToSearch();
            else if (!root.busy)
                root.closeRequested();
            event.accepted = true;
        }
    }

    function focusSearchResultsIfIdle(): void {
        if (root.screen === "search" && root.results.length > 0 && !queryField.input.activeFocus)
            resultList.forceActiveFocus();
    }

    function focusEpisodesIfIdle(): void {
        if (root.screen === "episodes" && root.episodes.length > 0)
            episodeList.forceActiveFocus();
    }

    Connections {
        target: MediatorService
        function onProviderSearchResultsChanged(): void {
            Qt.callLater(root.focusSearchResultsIfIdle);
        }
        function onProviderEpisodesChanged(): void {
            Qt.callLater(root.focusEpisodesIfIdle);
        }
        function onProviderStreamStarted(): void {
            root.streamStarted();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#99000000"
        z: 0
        MouseArea { anchors.fill: parent }
    }

    RoundedBox {
        id: panel
        anchors.centerIn: parent
        width: Math.min(parent.width - 32, 760)
        height: Math.min(parent.height - 32, 700)
        color: Appearance.colors.colLayer0
        radius: Appearance.rounding.verylarge
        z: 1

        Flickable {
            WheelScroll {}
            id: flick
            anchors.fill: parent
            anchors.margins: 24
            clip: true
            contentWidth: width
            contentHeight: body.implicitHeight
            boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
                id: body
                width: flick.width
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    StyledText {
                        Layout.fillWidth: true
                        text: root.screen === "episodes" ? "Choose an episode" : "Stream anime"
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                    }
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: Appearance.rounding.full
                        color: closeArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        opacity: root.busy ? 0.45 : 1
                        MaterialSymbol { anchors.centerIn: parent; text: "close"; iconSize: 20; color: Appearance.colors.colOnLayer0 }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            enabled: !root.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeRequested()
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.screen === "search"
                    spacing: 8
                    SettingsField {
                        id: queryField
                        Layout.fillWidth: true
                        label: "Anime search"
                        placeholder: "e.g. Frieren or Naruto"
                        onAccepted: root.search()
                        input.Keys.onDownPressed: event => {
                            if (root.results.length > 0) {
                                resultList.currentIndex = resultList.currentIndex < 0 ? 0 : resultList.currentIndex;
                                resultList.forceActiveFocus();
                                event.accepted = true;
                            }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 106
                        Layout.preferredHeight: 44
                        Layout.alignment: Qt.AlignBottom
                        radius: Appearance.rounding.small
                        color: root.busy ? Appearance.colors.colLayer2 : Appearance.colors.colPrimary
                        opacity: root.busy ? 0.65 : 1
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 5
                            MaterialSymbol { text: "search"; iconSize: 19; color: Appearance.colors.colOnPrimary }
                            StyledText { text: "Search"; color: Appearance.colors.colOnPrimary; font.weight: Font.Medium }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.search()
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.topMargin: -8
                    visible: root.screen === "search"
                    text: "Search the online provider; results are selected before playback."
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "search" && root.searchMode === false
                    text: `Searching online for “${root.titleLabel}” — choose the exact result before playback.`
                    wrapMode: Text.Wrap
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "search" && MediatorService.providerSearchBusy
                    text: "Searching provider…"
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "search" && !MediatorService.providerSearchBusy
                        && MediatorService.providerSearchError !== ""
                    text: MediatorService.providerSearchError
                    color: Appearance.colors.colError
                    wrapMode: Text.Wrap
                }

                ListView {
                    WheelScroll {}
                    id: resultList
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.screen === "search"
                        ? Math.min(344, Math.max(86, root.results.length * 86)) : 0
                    visible: root.screen === "search"
                    clip: true
                    spacing: 6
                    reuseItems: true
                    model: root.screen === "search" ? root.results : []
                    activeFocusOnTab: true
                    Keys.onReturnPressed: {
                        if (currentIndex >= 0 && currentIndex < root.results.length)
                            root.selectShow(root.results[currentIndex]);
                    }
                    delegate: Rectangle {
                        id: resultRow
                        required property var modelData
                        required property int index
                        width: resultList.width
                        height: 86
                        radius: Appearance.rounding.normal
                        color: resultMouse.containsMouse || resultList.currentIndex === resultRow.index
                            ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 12
                            Rectangle {
                                Layout.preferredWidth: 54
                                Layout.preferredHeight: 66
                                radius: Appearance.rounding.small
                                color: Appearance.colors.colLayer2
                                clip: true
                                Image {
                                    anchors.fill: parent
                                    source: MediatorService.cachedImage(resultRow.modelData.poster)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 3
                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultRow.modelData.title ?? resultRow.modelData.id
                                    color: Appearance.colors.colOnLayer0
                                    font.weight: Font.Medium
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    text: resultRow.modelData.description ?? ""
                                    color: Appearance.colors.colSubtext
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                    wrapMode: Text.Wrap
                                }
                            }
                            MaterialSymbol { text: "chevron_right"; iconSize: 22; color: Appearance.colors.colSubtext }
                        }
                        MouseArea {
                            id: resultMouse
                            anchors.fill: parent
                            enabled: !root.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                resultList.currentIndex = resultRow.index;
                                root.selectShow(resultRow.modelData);
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes"
                    spacing: 8
                    Rectangle {
                        Layout.preferredWidth: 38
                        Layout.preferredHeight: 36
                        radius: Appearance.rounding.full
                        color: backArea.containsMouse ? Appearance.colors.colLayer2 : "transparent"
                        MaterialSymbol { anchors.centerIn: parent; text: "arrow_back"; iconSize: 20; color: Appearance.colors.colOnLayer0 }
                        MouseArea {
                            id: backArea
                            anchors.fill: parent
                            enabled: !root.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.backToSearch()
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: root.selectedShow.title ?? "Selected anime"
                        color: Appearance.colors.colOnLayer0
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes"
                    spacing: 6
                    StyledText {
                        text: "Quality"
                        color: Appearance.colors.colSubtext
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        Layout.alignment: Qt.AlignVCenter
                    }
                    Rectangle {
                        Layout.preferredWidth: 104
                        Layout.preferredHeight: 34
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1
                        border.width: qualityInput.activeFocus ? 1 : 0
                        border.color: Appearance.colors.colPrimary
                        opacity: root.busy ? 0.6 : 1
                        StyledText {
                            anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                            visible: qualityInput.text === ""
                            text: "best / 720p"
                            color: Appearance.colors.colSubtext
                            font.pixelSize: Appearance.font.pixelSize.smaller
                        }
                        TextInput {
                            id: qualityInput
                            anchors { fill: parent; leftMargin: 10; rightMargin: 10 }
                            verticalAlignment: TextInput.AlignVCenter
                            text: root.quality
                            color: Appearance.colors.colOnLayer0
                            font.family: Appearance.font.family.main
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            selectByMouse: true
                            activeFocusOnPress: true
                            clip: true
                            enabled: !root.busy
                            onTextChanged: if (root.quality !== text) root.quality = text
                        }
                    }
                    Item { Layout.fillWidth: true }
                    Rectangle {
                        Layout.preferredWidth: 92
                        Layout.preferredHeight: 34
                        radius: Appearance.rounding.full
                        color: root.dub ? Appearance.colors.colSecondaryContainer
                                        : Appearance.colors.colLayer1
                        opacity: root.busy ? 0.6 : 1
                        StyledText {
                            anchors.centerIn: parent
                            text: root.dub ? "Audio: Dub" : "Audio: Sub"
                            color: Appearance.colors.colOnLayer0
                            font.pixelSize: Appearance.font.pixelSize.smaller
                            font.weight: Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: !root.busy
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.dub = !root.dub
                        }
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes"
                    text: "Online playback · AniList sync and intro skipping are unavailable"
                    color: Appearance.colors.colOutlineVariant
                    font.pixelSize: Appearance.font.pixelSize.smallest
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes" && MediatorService.providerEpisodesBusy
                    text: "Loading episodes…"
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes" && !MediatorService.providerEpisodesBusy
                        && MediatorService.providerEpisodesError !== ""
                    text: MediatorService.providerEpisodesError
                    color: Appearance.colors.colError
                    wrapMode: Text.Wrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes" && MediatorService.streamResolving
                    text: MediatorService.streamMessage || "Opening episode…"
                    color: Appearance.colors.colPrimary
                    wrapMode: Text.Wrap
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.screen === "episodes" && MediatorService.streamError !== ""
                    text: MediatorService.streamError
                    color: Appearance.colors.colError
                    wrapMode: Text.Wrap
                }

                ListView {
                    WheelScroll {}
                    id: episodeList
                    Layout.fillWidth: true
                    Layout.preferredHeight: root.screen === "episodes"
                        ? Math.min(360, Math.max(48, root.episodes.length * 48)) : 0
                    visible: root.screen === "episodes"
                    clip: true
                    spacing: 4
                    reuseItems: true
                    model: root.screen === "episodes" ? root.episodes : []
                    activeFocusOnTab: true
                    focus: root.screen === "episodes" && root.episodes.length > 0
                    Keys.onReturnPressed: {
                        if (currentIndex >= 0 && currentIndex < root.episodes.length)
                            root.playEpisode(root.episodes[currentIndex]);
                    }
                    delegate: Rectangle {
                        id: episodeRow
                        required property var modelData
                        required property int index
                        readonly property bool opening: MediatorService.streamResolving
                            && MediatorService.providerPendingShowId === String(root.selectedShow.id ?? "")
                            && MediatorService.providerPendingEpisodeId === String(modelData.id ?? "")
                        width: episodeList.width
                        height: 48
                        radius: Appearance.rounding.small
                        color: episodeRow.opening || episodeMouse.containsMouse
                                || episodeList.currentIndex === episodeRow.index
                            ? Appearance.colors.colSecondaryContainer : Appearance.colors.colLayer1
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 10
                            StyledText {
                                Layout.preferredWidth: 58
                                text: `EP ${episodeRow.modelData.number}`
                                color: Appearance.colors.colPrimary
                                font.weight: Font.Medium
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: episodeRow.opening ? "Opening…"
                                    : (episodeRow.modelData.title || "Episode")
                                color: Appearance.colors.colOnLayer0
                                elide: Text.ElideRight
                            }
                            MaterialSymbol {
                                text: episodeRow.opening ? "hourglass_top" : "play_arrow"
                                iconSize: 20
                                color: episodeRow.opening
                                    ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                            }
                        }
                        MouseArea {
                            id: episodeMouse
                            anchors.fill: parent
                            enabled: !root.busy && !episodeRow.opening
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                episodeList.currentIndex = episodeRow.index;
                                root.playEpisode(episodeRow.modelData);
                            }
                        }
                    }
                }

            }
        }
    }
}

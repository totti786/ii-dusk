pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * The Streaming tab's one control row: which source (anime or movies and shows), how to browse
 * it, and the AniList link. It pins to the top once the page scrolls under it. Every control
 * has a key: Ctrl+Up/Down for the source, Ctrl+Left/Right for the browse chips.
 */
Item {
    id: root

    property string onlineKind: "anime"
    /// The page has scrolled and this row is riding over the covers
    property bool stuck: false

    signal kindRequested(string kind)
    signal settingsRequested()
    signal refreshRequested()

    readonly property bool stremio: root.onlineKind === "stremio"
    readonly property var animeModes: [
        { mode: "trending", label: "Trending" },
        { mode: "season", label: "This season" },
        { mode: "popular", label: "Popular" },
        { mode: "top", label: "Top rated" }
    ]
    readonly property var stremioKinds: [
        { kind: "movie", label: "Movies", icon: "movie" },
        { kind: "series", label: "Series", icon: "tv" }
    ]
    /// A search can show both kinds at once; browsing is one catalog at a time
    readonly property var kindChips: StremioService.searching
        ? [{ kind: "all", label: "All", icon: "apps" }].concat(root.stremioKinds) : root.stremioKinds
    readonly property var anilist: MediatorService.anilistStatus ?? ({})
    readonly property bool anilistOk: Boolean(root.anilist?.ok)
    readonly property string anilistUser: String(root.anilist?.username ?? "")
    readonly property int anilistPending: Number(root.anilist?.pending ?? 0)

    implicitHeight: 40

    /// Ctrl+Left / Ctrl+Right: the previous or next browse chip, without wrapping
    function stepBrowse(delta): void {
        if (root.stremio) {
            const cur = StremioService.searching ? StremioService.searchKind : StremioService.kind;
            const i = root.kindChips.findIndex(k => k.kind === cur);
            const k = root.kindChips[Math.max(0, Math.min(root.kindChips.length - 1, i + delta))];
            if (StremioService.searching)
                StremioService.setKind(k.kind);
            else
                StremioService.browse(k.kind, StremioService.sort, StremioService.sort === "year" ? StremioService.genre : "");
            return;
        }
        const i = root.animeModes.findIndex(m => m.mode === AnimeBrowseService.mode);
        // From search results, either direction lands on the first chip
        const j = i < 0 ? 0 : Math.max(0, Math.min(root.animeModes.length - 1, i + delta));
        AnimeBrowseService.load(root.animeModes[j].mode);
    }

    Rectangle {
        anchors { fill: parent; topMargin: -10; bottomMargin: -6; leftMargin: -8; rightMargin: -8 }
        radius: Appearance.rounding.normal
        // The theme's layer colour is translucent, which let the covers show through; make it solid
        color: Qt.rgba(Appearance.colors.colLayer0.r, Appearance.colors.colLayer0.g, Appearance.colors.colLayer0.b, 1)
        opacity: root.stuck ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: Appearance.dur(140) }
        }
        border.width: 1
        border.color: Appearance.colors.colOutlineVariant
    }

    RowLayout {
        anchors.fill: parent
        spacing: 8

        // Source
        Repeater {
            model: [
                { kind: "anime", label: "Anime", icon: "animation", key: "Ctrl+↑" },
                { kind: "stremio", label: "Movies & Shows", icon: "movie", key: "Ctrl+↓" }
            ]
            delegate: Rectangle {
                id: kindPill
                required property var modelData
                readonly property bool on: root.onlineKind === kindPill.modelData.kind
                Layout.preferredWidth: kindRow.implicitWidth + 28
                Layout.preferredHeight: 36
                radius: Appearance.rounding.full
                color: kindPill.on ? Appearance.colors.colSecondaryContainer
                     : kindArea.containsMouse ? Appearance.colors.colLayer1 : "transparent"
                border.width: kindPill.on ? 0 : 1
                border.color: Appearance.colors.colOutlineVariant
                RowLayout {
                    id: kindRow
                    anchors.centerIn: parent
                    spacing: 6
                    MaterialSymbol {
                        text: kindPill.modelData.icon
                        iconSize: 18
                        fill: kindPill.on ? 1 : 0
                        color: Appearance.colors.colOnLayer0
                    }
                    StyledText {
                        text: kindPill.modelData.label
                        color: Appearance.colors.colOnLayer0
                        font.weight: kindPill.on ? Font.Medium : Font.Normal
                    }
                }
                MouseArea {
                    id: kindArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.kindRequested(kindPill.modelData.kind)
                }
                StyledToolTip {
                    extraVisibleCondition: kindArea.containsMouse
                    text: kindPill.modelData.key
                }
            }
        }

        Rectangle {
            Layout.preferredWidth: 1
            Layout.preferredHeight: 20
            Layout.leftMargin: 6
            Layout.rightMargin: 6
            color: Appearance.colors.colOutlineVariant
        }

        // How to browse it
        Repeater {
            model: root.stremio ? [] : root.animeModes
            FilterChip {
                required property var modelData
                label: modelData.label
                selected: AnimeBrowseService.mode === modelData.mode
                onClicked: AnimeBrowseService.load(modelData.mode)
            }
        }
        Repeater {
            model: root.stremio ? root.kindChips : []
            FilterChip {
                required property var modelData
                label: modelData.label
                selected: (StremioService.searching ? StremioService.searchKind : StremioService.kind) === modelData.kind
                onClicked: StremioService.searching ? StremioService.setKind(modelData.kind)
                    : StremioService.browse(modelData.kind, StremioService.sort,
                        StremioService.sort === "year" ? StremioService.genre : "")
            }
        }

        Item { Layout.fillWidth: true }

        // AniList: connected account or an invitation to connect one
        Rectangle {
            visible: !root.stremio
            Layout.preferredHeight: 34
            Layout.preferredWidth: anilistLabel.implicitWidth + 26
            radius: Appearance.rounding.full
            color: anilistArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
            RowLayout {
                id: anilistLabel
                anchors.centerIn: parent
                spacing: 6
                MaterialSymbol {
                    text: root.anilistOk ? "sync" : "account_circle"
                    iconSize: 17
                    color: root.anilistOk ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                }
                StyledText {
                    text: root.anilistOk ? `AniList · ${root.anilistUser}` : "Connect AniList"
                    color: Appearance.colors.colOnLayer0
                    font.pixelSize: Appearance.font.pixelSize.smaller
                }
                Rectangle {
                    visible: root.anilistPending > 0
                    Layout.preferredWidth: pendingLabel.implicitWidth + 10
                    Layout.preferredHeight: 17
                    radius: 8.5
                    color: Appearance.colors.colPrimary
                    StyledText {
                        id: pendingLabel
                        anchors.centerIn: parent
                        text: String(root.anilistPending)
                        color: Appearance.colors.colOnPrimary
                        font.pixelSize: Appearance.font.pixelSize.smallest
                        font.weight: Font.Bold
                    }
                }
            }
            MouseArea {
                id: anilistArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.settingsRequested()
            }
            StyledToolTip {
                extraVisibleCondition: anilistArea.containsMouse
                text: root.anilistOk ? "AniList is connected; open settings to manage sync"
                                     : "Open settings to log in to AniList"
            }
        }

        Rectangle {
            visible: !root.stremio
            Layout.preferredWidth: 34
            Layout.preferredHeight: 34
            radius: Appearance.rounding.full
            color: refreshArea.containsMouse ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1
            MaterialSymbol {
                anchors.centerIn: parent
                text: "refresh"
                iconSize: 19
                color: Appearance.colors.colOnLayer0
            }
            MouseArea {
                id: refreshArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.refreshRequested()
            }
            StyledToolTip {
                extraVisibleCondition: refreshArea.containsMouse
                text: "Refresh"
            }
        }
    }
}

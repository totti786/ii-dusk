pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.grit.components

/**
 * The opt-in focus leaderboard. It mirrors exactly what the Android app shows:
 * every account that chose to publish a tag, one row per period, and a switch
 * for every focus tag so privacy stays a per-tag decision.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    signal settingsRequested()

    property string period: "week"
    property string nameDraft: GritService.effectiveDisplayName

    readonly property real padding: root.compact ? GritStyle.pagePadding : GritStyle.pagePaddingWide
    readonly property real contentWidth: Math.min(root.layoutWidth - root.padding * 2, 1100)
    readonly property var periods: [
        { id: "day", label: Translation.tr("Today") },
        { id: "week", label: Translation.tr("Week") },
        { id: "month", label: Translation.tr("Month") }
    ]
    readonly property var ranked: {
        const key = root.period;
        const rows = [];
        for (const entry of Array.from(GritService.leaderboardEntries ?? [])) {
            let seconds = 0;
            for (const tag of Array.from(entry.tags ?? []))
                seconds += Number(tag[key] ?? 0);
            rows.push({
                uid: String(entry.uid ?? ""),
                name: String(entry.displayName ?? ""),
                tags: Array.from(entry.tags ?? []),
                updatedAt: Number(entry.updatedAt ?? 0),
                seconds: seconds
            });
        }
        rows.sort((a, b) => b.seconds - a.seconds
            || a.name.localeCompare(b.name));
        return rows;
    }
    readonly property var podium: {
        const top = root.ranked.slice(0, 3);
        if (top.length === 0)
            return [];
        const order = top.length >= 3 ? [1, 0, 2] : top.length === 2 ? [1, 0] : [0];
        return order.map(index => ({
            entry: top[index],
            rank: index + 1,
            seconds: top[index].seconds
        }));
    }
    readonly property real maxSeconds: {
        let max = 1;
        for (const row of root.ranked)
            max = Math.max(max, Number(row.seconds ?? 0));
        return max;
    }
    readonly property var ownPublicTags: GritService.activeTags.filter(tag =>
        GritService.publicTagIds.indexOf(String(tag.id)) >= 0)
    readonly property string updatedLabel: GritService.leaderboardUpdatedAt > 0
        ? Qt.formatTime(new Date(GritService.leaderboardUpdatedAt), "HH:mm")
        : ""

    function initials(name): string {
        const words = String(name ?? "").trim().split(/\s+/).filter(word => word.length > 0);
        if (words.length === 0)
            return "?";
        if (words.length === 1)
            return words[0].slice(0, 2).toUpperCase();
        return (words[0].slice(0, 1) + words[words.length - 1].slice(0, 1)).toUpperCase();
    }

    function medalColor(rank): color {
        if (rank === 1)
            return "#E7B84B";
        if (rank === 2)
            return "#B9C4CE";
        if (rank === 3)
            return "#C98B5B";
        return GritStyle.colPrimary;
    }

    function duration(seconds): string {
        return GritStyle.durationShort(Math.round(Number(seconds ?? 0) / 60));
    }

    function saveName(): void {
        GritService.setDisplayName(root.nameDraft);
        GritService.publishLeaderboard();
        GritService.refreshLeaderboard();
    }

    function togglePublic(tagId): void {
        const next = GritService.publicTagIds.indexOf(String(tagId)) < 0;
        GritService.setTagPublic(String(tagId), next);
        Qt.callLater(() => {
            GritService.publishLeaderboard();
            GritService.refreshLeaderboard();
        });
    }

    function refresh(): void {
        if (GritService.signedIn)
            GritService.refreshLeaderboard();
    }

    Component.onCompleted: {
        if (GritService.signedIn) {
            GritService.publishLeaderboard();
            GritService.refreshLeaderboard();
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible && GritService.signedIn
        onTriggered: root.refresh()
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + GritStyle.gapHuge
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
            spacing: GritStyle.gap

            GritHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "emoji_events"
                title: Translation.tr("Focus ranks")
                text: GritService.signedIn
                    ? Translation.tr("Combined focus across every public tag. Never habits, tasks or notes.")
                    : Translation.tr("Sign in to add your focus to the community board.")
                shapeName: "Cookie12Sided"
                colContainer: GritStyle.colSecondaryContainer
                colOnContainer: GritStyle.colOnSecondaryContainer
                colAccent: GritStyle.colSecondary

                RowLayout {
                    spacing: GritStyle.gapTiny

                    Repeater {
                        model: root.periods

                        ClockFormChip {
                            required property var modelData
                            label: String(modelData.label ?? "")
                            selected: root.period === String(modelData.id)
                            onTriggered: root.period = String(modelData.id)
                        }
                    }

                    ClockIconButton {
                        symbol: GritService.leaderboardLoading ? "hourglass_empty" : "refresh"
                        tooltip: Translation.tr("Refresh the leaderboard")
                        enabled: GritService.signedIn && !GritService.leaderboardLoading
                        onClicked: root.refresh()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !GritService.signedIn
                implicitHeight: signInColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: signInColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: GritStyle.gapSmall

                    StyledText {
                        text: Translation.tr("The ranks are a shared room")
                        font.family: GritStyle.fontTitle
                        font.variableAxes: GritStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: GritStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Sign in, choose a display name, then flip only the focus tags you want to publish. Private tags stay on this device.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textNormal
                        color: GritStyle.colSubtext
                    }

                    ClockButton {
                        Layout.fillWidth: true
                        Layout.topMargin: GritStyle.gapSmall
                        variant: "filled"
                        symbol: "login"
                        label: Translation.tr("Sign in or create an account")
                        onClicked: root.settingsRequested()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: GritService.leaderboardLoading
                spacing: GritStyle.gapSmall

                MaterialSymbol {
                    text: "hourglass_empty"
                    iconSize: 16
                    color: GritStyle.colSubtext
                }

                StyledText {
                    text: Translation.tr("Listening to the other devices…")
                    font.pixelSize: GritStyle.textSmall
                    color: GritStyle.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: GritService.leaderboardError.length > 0
                text: GritService.leaderboardError
                wrapMode: Text.WordWrap
                font.pixelSize: GritStyle.textSmall
                color: GritStyle.colError
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: GritStyle.gapSmall
                visible: root.podium.length > 0

                Repeater {
                    model: root.podium

                    Rectangle {
                        id: podiumCard
                        required property var modelData
                        readonly property int rank: Number(modelData.rank ?? 1)
                        readonly property var entry: modelData.entry ?? ({})
                        readonly property int seconds: Number(modelData.seconds ?? 0)
                        readonly property color medal: root.medalColor(podiumCard.rank)
                        readonly property var topTag: {
                            const tags = Array.from(podiumCard.entry.tags ?? []);
                            let best = null;
                            for (const tag of tags) {
                                if (!best || Number(tag[root.period] ?? 0) > Number(best[root.period] ?? 0))
                                    best = tag;
                            }
                            return best;
                        }
                        readonly property color accent: podiumCard.topTag
                            ? GritStyle.tagColor(podiumCard.topTag) : GritStyle.colPrimary

                        Layout.fillWidth: true
                        Layout.preferredHeight: podiumCard.rank === 1 ? 190 : podiumCard.rank === 2 ? 168 : 158
                        radius: GritStyle.radiusLarge
                        color: GritStyle.colSurface
                        border.width: String(podiumCard.entry.uid) === String(GritService.authUid) ? 1.5 : 1
                        border.color: String(podiumCard.entry.uid) === String(GritService.authUid)
                            ? ColorUtils.applyAlpha(GritStyle.colPrimary, 0.7)
                            : ColorUtils.applyAlpha(podiumCard.medal, 0.32)

                        StaggeredEntrance {
                            index: podiumCard.rank
                        }

                        ColumnLayout {
                            anchors {
                                fill: parent
                                margins: GritStyle.gapSmall
                            }
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(podiumCard.rank)
                                font.family: GritStyle.fontNumbers
                                font.variableAxes: GritStyle.axesDigitsBold
                                font.pixelSize: podiumCard.rank === 1 ? Appearance.font.pixelSize.huge : Appearance.font.pixelSize.large
                                color: podiumCard.medal
                            }

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: podiumCard.rank === 1 ? 46 : 38
                                implicitHeight: podiumCard.rank === 1 ? 46 : 38

                                MaterialShape {
                                    anchors.fill: parent
                                    shapeString: String(podiumCard.topTag?.shape ?? "Cookie12Sided")
                                    color: ColorUtils.applyAlpha(podiumCard.accent, 0.16)
                                }

                                StyledText {
                                    anchors.centerIn: parent
                                    text: root.initials(podiumCard.entry.displayName)
                                    font.family: GritStyle.fontNumbers
                                    font.variableAxes: GritStyle.axesDigitsBold
                                    font.pixelSize: podiumCard.rank === 1 ? 15 : 12
                                    color: podiumCard.accent
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                text: String(podiumCard.entry.displayName ?? "")
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.pixelSize: podiumCard.rank === 1 ? GritStyle.textNormal + 1 : GritStyle.textSmall
                                font.weight: Font.DemiBold
                                color: GritStyle.colOnSurface
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.duration(podiumCard.seconds)
                                font.family: GritStyle.fontNumbers
                                font.variableAxes: GritStyle.axesDigitsBold
                                font.pixelSize: podiumCard.rank === 1 ? Appearance.font.pixelSize.large : GritStyle.textLarge
                                color: podiumCard.accent
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.period === "day" ? Translation.tr("today")
                                    : root.period === "month" ? Translation.tr("this month") : Translation.tr("this week")
                                font.pixelSize: GritStyle.textSmall
                                color: GritStyle.colSubtext
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: String(podiumCard.entry.uid) === String(GritService.authUid)
                                text: Translation.tr("You")
                                font.pixelSize: GritStyle.textSmall
                                font.weight: Font.Bold
                                color: GritStyle.colPrimary
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapTiny
                visible: root.ranked.length > 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Everyone")
                    font.family: GritStyle.fontTitle
                    font.variableAxes: GritStyle.axesTitle
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: GritStyle.colOnSurface
                }

                StyledText {
                    text: Translation.tr("%1 accounts").arg(String(root.ranked.length))
                    font.pixelSize: GritStyle.textSmall
                    color: GritStyle.colSubtext
                }
            }

            Repeater {
                model: root.ranked

                Rectangle {
                    id: rankRow
                    required property var modelData
                    required property int index
                    readonly property bool you: String(modelData.uid) === String(GritService.authUid)
                    readonly property var topTag: {
                        const tags = Array.from(modelData.tags ?? []);
                        let best = null;
                        for (const tag of tags) {
                            if (!best || Number(tag[root.period] ?? 0) > Number(best[root.period] ?? 0))
                                best = tag;
                        }
                        return best;
                    }
                    readonly property color accent: rankRow.topTag
                        ? GritStyle.tagColor(rankRow.topTag) : GritStyle.colPrimary

                    Layout.fillWidth: true
                    implicitHeight: 68
                    radius: GritStyle.radiusNormal
                    color: rankRow.you
                        ? ColorUtils.mix(GritStyle.colSurface, rankRow.accent, 0.09)
                        : GritStyle.colSurface
                    border.width: rankRow.you ? 1 : 0
                    border.color: ColorUtils.applyAlpha(rankRow.accent, 0.45)

                    StaggeredEntrance {
                        index: Math.min(rankRow.index, 8)
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: GritStyle.gap
                            rightMargin: GritStyle.gap
                        }
                        spacing: GritStyle.gapSmall

                        StyledText {
                            Layout.preferredWidth: 24
                            text: String(rankRow.index + 1)
                            horizontalAlignment: Text.AlignHCenter
                            font.family: GritStyle.fontNumbers
                            font.variableAxes: GritStyle.axesDigitsBold
                            font.pixelSize: GritStyle.textNormal
                            color: rankRow.index < 3 ? root.medalColor(rankRow.index + 1) : GritStyle.colSubtext
                        }

                        Item {
                            implicitWidth: 38
                            implicitHeight: 38

                            MaterialShape {
                                anchors.fill: parent
                                shapeString: String(rankRow.topTag?.shape ?? "Cookie12Sided")
                                color: ColorUtils.applyAlpha(rankRow.accent, 0.16)
                            }

                            StyledText {
                                anchors.centerIn: parent
                                text: root.initials(modelData.name)
                                font.family: GritStyle.fontNumbers
                                font.variableAxes: GritStyle.axesDigitsBold
                                font.pixelSize: 11
                                color: rankRow.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: GritStyle.gapTiny

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.name ?? "")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: GritStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: GritStyle.colOnSurface
                                }

                                Rectangle {
                                    visible: rankRow.you
                                    implicitWidth: youText.implicitWidth + 10
                                    implicitHeight: 16
                                    radius: 8
                                    color: ColorUtils.applyAlpha(rankRow.accent, 0.16)

                                    StyledText {
                                        id: youText
                                        anchors.centerIn: parent
                                        text: Translation.tr("YOU")
                                        font.pixelSize: 8
                                        font.weight: Font.Bold
                                        color: rankRow.accent
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: GritStyle.colField

                                Rectangle {
                                    width: parent.width * Math.max(0.02,
                                        Math.min(1, Number(modelData.seconds ?? 0) / root.maxSeconds))
                                    implicitHeight: 4
                                    radius: 2
                                    color: rankRow.accent
                                }
                            }

                            StyledText {
                                Layout.fillWidth: true
                                text: Translation.tr("%1 public tags · %2")
                                    .arg(String(Array.from(modelData.tags ?? []).length))
                                    .arg(root.period === "day" ? Translation.tr("today")
                                        : root.period === "month" ? Translation.tr("this month")
                                        : Translation.tr("this week"))
                                elide: Text.ElideRight
                                font.pixelSize: GritStyle.textSmall
                                color: GritStyle.colSubtext
                            }
                        }

                        StyledText {
                            text: root.duration(modelData.seconds)
                            font.family: GritStyle.fontNumbers
                            font.variableAxes: GritStyle.axesDigitsBold
                            font.pixelSize: GritStyle.textNormal
                            color: rankRow.accent
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.ranked.length === 0
                implicitHeight: emptyColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: emptyColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: GritStyle.gapSmall

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "emoji_events"
                        iconSize: 26
                        padding: 14
                        shape: "Cookie9Sided"
                        color: GritStyle.colField
                        colSymbol: GritStyle.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: GritService.signedIn
                            ? Translation.tr("The podium is waiting.")
                            : Translation.tr("No shared focus yet.")
                        font.family: GritStyle.fontTitle
                        font.variableAxes: GritStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: GritStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: GritService.signedIn
                            ? Translation.tr("Publish a tag below and the first focus session puts you on the board.")
                            : Translation.tr("Sign in and make one tag public to start the board.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colSubtext
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: GritService.signedIn
                implicitHeight: nameColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: nameColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: GritStyle.gapSmall

                    StyledText {
                        text: Translation.tr("How you appear")
                        font.family: GritStyle.fontTitle
                        font.variableAxes: GritStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: GritStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("A display name for the ranks. Your email is never published.")
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: GritStyle.gapSmall

                        ClockFormField {
                            Layout.fillWidth: true
                            symbol: "person"
                            shapeKind: MaterialShape.Shape.Cookie4Sided
                            caption: Translation.tr("Display name")
                            placeholder: Translation.tr("Your name")
                            text: root.nameDraft
                            onTextChanged: {
                                if (text !== root.nameDraft)
                                    root.nameDraft = text;
                            }
                            onAccepted: root.saveName()
                        }

                        ClockButton {
                            variant: "filled"
                            symbol: "check"
                            label: Translation.tr("Save")
                            onClicked: root.saveName()
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: GritService.signedIn
                implicitHeight: publicColumn.implicitHeight + GritStyle.cardPadding * 2
                radius: GritStyle.radiusLarge
                color: GritStyle.colSurface

                ColumnLayout {
                    id: publicColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: GritStyle.cardPadding
                    }
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Public tags")
                        font.family: GritStyle.fontTitle
                        font.variableAxes: GritStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: GritStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: GritStyle.gapSmall
                        text: Translation.tr("Flip a tag on to share its focus time for today, this week and this month.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colSubtext
                    }

                    Repeater {
                        model: GritService.activeTags

                        ClockSettingsRow {
                            id: publicRow
                            required property var modelData
                            required property int index
                            first: publicRow.index === 0
                            last: publicRow.index === GritService.activeTags.length - 1
                            symbol: String(publicRow.modelData.icon ?? "label")
                            title: String(publicRow.modelData.name ?? "")
                            description: GritService.publicTagIds.indexOf(String(publicRow.modelData.id)) >= 0
                                ? Translation.tr("Visible on the ranks")
                                : Translation.tr("Private · stays here")

                            StyledSwitch {
                                checked: GritService.publicTagIds.indexOf(String(publicRow.modelData.id)) >= 0
                                checkable: false
                                onClicked: root.togglePublic(publicRow.modelData.id)
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: GritStyle.gapSmall
                        text: Translation.tr("%1 of %2 tags public · habits, tasks and notes are never uploaded to the board.")
                            .arg(String(root.ownPublicTags.length))
                            .arg(String(GritService.activeTags.length))
                        wrapMode: Text.WordWrap
                        font.pixelSize: GritStyle.textSmall
                        color: GritStyle.colSubtext
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: GritStyle.gapSmall
                horizontalAlignment: Text.AlignHCenter
                text: root.updatedLabel.length > 0
                    ? Translation.tr("Updated %1 · the board refreshes every minute").arg(root.updatedLabel)
                    : Translation.tr("Waiting for the first sync.")
                font.pixelSize: GritStyle.textSmall
                color: GritStyle.colSubtext
            }

            Item { Layout.preferredHeight: GritStyle.fabClearance }
        }
    }
}

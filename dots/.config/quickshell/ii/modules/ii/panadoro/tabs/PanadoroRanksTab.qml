pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import qs.modules.ii.panadoro.components

/**
 * The opt-in focus leaderboard: every account that chose to publish a focus tag,
 * ranked per period (today, week, month), with a switch on each of your own tags
 * so privacy stays a per-tag decision.
 */
Item {
    id: root

    property bool compact: false
    property bool wide: false
    property real layoutWidth: root.width
    property ClockSidePanel panels: null

    signal settingsRequested()

    property string period: "week"
    property string nameDraft: PanadoroService.effectiveDisplayName

    readonly property real padding: root.compact ? PanadoroStyle.pagePadding : PanadoroStyle.pagePaddingWide
    readonly property real contentWidth: root.layoutWidth - root.padding * 2
    readonly property var periods: [
        { id: "day", label: Translation.tr("Today") },
        { id: "week", label: Translation.tr("Week") },
        { id: "month", label: Translation.tr("Month") }
    ]
    readonly property var ranked: {
        const key = root.period;
        const rows = [];
        for (const entry of Array.from(PanadoroService.leaderboardEntries ?? [])) {
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
    readonly property var ownPublicTags: PanadoroService.activeTags.filter(tag =>
        PanadoroService.publicTagIds.indexOf(String(tag.id)) >= 0)
    readonly property string updatedLabel: PanadoroService.leaderboardUpdatedAt > 0
        ? Qt.formatTime(new Date(PanadoroService.leaderboardUpdatedAt), "HH:mm")
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
        switch (rank) {
        case 1: return PanadoroStyle.colGold;
        case 2: return PanadoroStyle.colSilver;
        case 3: return PanadoroStyle.colBronze;
        default: return PanadoroStyle.colPrimary;
        }
    }

    function duration(seconds): string {
        return PanadoroStyle.durationShort(Math.round(Number(seconds ?? 0) / 60));
    }

    function saveName(): void {
        PanadoroService.setDisplayName(root.nameDraft);
        PanadoroService.publishLeaderboard();
        PanadoroService.refreshLeaderboard();
    }

    function togglePublic(tagId): void {
        const next = PanadoroService.publicTagIds.indexOf(String(tagId)) < 0;
        PanadoroService.setTagPublic(String(tagId), next);
        Qt.callLater(() => {
            PanadoroService.publishLeaderboard();
            PanadoroService.refreshLeaderboard();
        });
    }

    function refresh(): void {
        if (PanadoroService.signedIn)
            PanadoroService.refreshLeaderboard();
    }

    Component.onCompleted: {
        if (PanadoroService.signedIn) {
            PanadoroService.publishLeaderboard();
            PanadoroService.refreshLeaderboard();
        }
    }

    Timer {
        interval: 60000
        repeat: true
        running: root.visible && PanadoroService.signedIn
        onTriggered: root.refresh()
    }

    StyledFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight + root.padding + PanadoroStyle.gapHuge
        clip: true

        ColumnLayout {
            id: column
            width: root.contentWidth
            x: Math.max(root.padding, (root.width - root.contentWidth) / 2)
            spacing: PanadoroStyle.gap

            PanadoroHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: "emoji_events"
                title: Translation.tr("Focus ranks")
                text: PanadoroService.signedIn
                    ? Translation.tr("Combined focus across every public tag. Never habits, tasks or notes.")
                    : Translation.tr("Sign in to add your focus to the community board.")
                shapeName: "Cookie12Sided"
                colContainer: PanadoroStyle.colSecondaryContainer
                colOnContainer: PanadoroStyle.colOnSecondaryContainer
                colAccent: PanadoroStyle.colSecondary

                RowLayout {
                    spacing: PanadoroStyle.gapTiny

                    Repeater {
                        model: root.periods

                        PanadoroChoiceChip {
                            required property var modelData
                            label: String(modelData.label ?? "")
                            selected: root.period === String(modelData.id)
                            colSelected: PanadoroStyle.colPrimary
                            colOnSelected: PanadoroStyle.colOnPrimary
                            onTriggered: root.period = String(modelData.id)
                        }
                    }

                    ClockIconButton {
                        symbol: PanadoroService.leaderboardLoading ? "hourglass_empty" : "refresh"
                        tooltip: Translation.tr("Refresh the leaderboard")
                        enabled: PanadoroService.signedIn && !PanadoroService.leaderboardLoading
                        onClicked: root.refresh()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: !PanadoroService.signedIn
                implicitHeight: signInColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: signInColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: PanadoroStyle.gapSmall

                    StyledText {
                        text: Translation.tr("The ranks are a shared room")
                        font.family: PanadoroStyle.fontTitle
                        font.variableAxes: PanadoroStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: PanadoroStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("Sign in, choose a display name, then flip only the focus tags you want to publish. Private tags stay on this device.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textNormal
                        color: PanadoroStyle.colSubtext
                    }

                    ClockButton {
                        Layout.fillWidth: true
                        Layout.topMargin: PanadoroStyle.gapSmall
                        variant: "filled"
                        symbol: "login"
                        label: Translation.tr("Sign in or create an account")
                        onClicked: root.settingsRequested()
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                visible: PanadoroService.leaderboardLoading
                spacing: PanadoroStyle.gapSmall

                MaterialSymbol {
                    text: "hourglass_empty"
                    iconSize: 16
                    color: PanadoroStyle.colSubtext
                }

                StyledText {
                    text: Translation.tr("Listening to the other devices…")
                    font.pixelSize: PanadoroStyle.textSmall
                    color: PanadoroStyle.colSubtext
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: PanadoroService.leaderboardError.length > 0
                text: PanadoroService.leaderboardError
                wrapMode: Text.WordWrap
                font.pixelSize: PanadoroStyle.textSmall
                color: PanadoroStyle.colError
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignBottom
                spacing: PanadoroStyle.gapSmall
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
                            ? PanadoroStyle.tagColor(podiumCard.topTag) : PanadoroStyle.colPrimary

                        Layout.fillWidth: true
                        Layout.preferredHeight: podiumCard.rank === 1 ? 190 : podiumCard.rank === 2 ? 168 : 158
                        radius: PanadoroStyle.radiusLarge
                        color: String(podiumCard.entry.uid) === String(PanadoroService.authUid)
                            ? ColorUtils.mix(PanadoroStyle.colSurface, PanadoroStyle.colPrimary, 0.14)
                            : ColorUtils.mix(PanadoroStyle.colSurface, podiumCard.medal, 0.08)

                        StaggeredEntrance {
                            index: podiumCard.rank
                        }

                        ColumnLayout {
                            anchors {
                                fill: parent
                                margins: PanadoroStyle.gapSmall
                            }
                            spacing: 2

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: String(podiumCard.rank)
                                font.family: PanadoroStyle.fontNumbers
                                font.variableAxes: PanadoroStyle.axesDigitsBold
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
                                    font.family: PanadoroStyle.fontNumbers
                                    font.variableAxes: PanadoroStyle.axesDigitsBold
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
                                font.pixelSize: podiumCard.rank === 1 ? PanadoroStyle.textNormal + 1 : PanadoroStyle.textSmall
                                font.weight: Font.DemiBold
                                color: PanadoroStyle.colOnSurface
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.duration(podiumCard.seconds)
                                font.family: PanadoroStyle.fontNumbers
                                font.variableAxes: PanadoroStyle.axesDigitsBold
                                font.pixelSize: podiumCard.rank === 1 ? Appearance.font.pixelSize.large : PanadoroStyle.textLarge
                                color: podiumCard.accent
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                text: root.period === "day" ? Translation.tr("today")
                                    : root.period === "month" ? Translation.tr("this month") : Translation.tr("this week")
                                font.pixelSize: PanadoroStyle.textSmall
                                color: PanadoroStyle.colSubtext
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                visible: String(podiumCard.entry.uid) === String(PanadoroService.authUid)
                                text: Translation.tr("You")
                                font.pixelSize: PanadoroStyle.textSmall
                                font.weight: Font.Bold
                                color: PanadoroStyle.colPrimary
                            }
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapTiny
                visible: root.ranked.length > 0

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Everyone")
                    font.family: PanadoroStyle.fontTitle
                    font.variableAxes: PanadoroStyle.axesTitle
                    font.pixelSize: Appearance.font.pixelSize.large
                    color: PanadoroStyle.colOnSurface
                }

                StyledText {
                    text: Translation.tr("%1 accounts").arg(String(root.ranked.length))
                    font.pixelSize: PanadoroStyle.textSmall
                    color: PanadoroStyle.colSubtext
                }
            }

            Repeater {
                model: root.ranked

                Rectangle {
                    id: rankRow
                    required property var modelData
                    required property int index
                    readonly property bool you: String(modelData.uid) === String(PanadoroService.authUid)
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
                        ? PanadoroStyle.tagColor(rankRow.topTag) : PanadoroStyle.colPrimary

                    Layout.fillWidth: true
                    implicitHeight: 68
                    radius: PanadoroStyle.radiusNormal
                    color: rankRow.you
                        ? ColorUtils.mix(PanadoroStyle.colSurface, rankRow.accent, 0.16)
                        : PanadoroStyle.colSurface

                    StaggeredEntrance {
                        index: Math.min(rankRow.index, 8)
                    }

                    RowLayout {
                        anchors {
                            fill: parent
                            leftMargin: PanadoroStyle.gap
                            rightMargin: PanadoroStyle.gap
                        }
                        spacing: PanadoroStyle.gapSmall

                        StyledText {
                            Layout.preferredWidth: 24
                            text: String(rankRow.index + 1)
                            horizontalAlignment: Text.AlignHCenter
                            font.family: PanadoroStyle.fontNumbers
                            font.variableAxes: PanadoroStyle.axesDigitsBold
                            font.pixelSize: PanadoroStyle.textNormal
                            color: rankRow.index < 3 ? root.medalColor(rankRow.index + 1) : PanadoroStyle.colSubtext
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
                                font.family: PanadoroStyle.fontNumbers
                                font.variableAxes: PanadoroStyle.axesDigitsBold
                                font.pixelSize: PanadoroStyle.textSmall
                                color: rankRow.accent
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 3

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: PanadoroStyle.gapTiny

                                StyledText {
                                    Layout.fillWidth: true
                                    text: String(modelData.name ?? "")
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: PanadoroStyle.textNormal
                                    font.weight: Font.DemiBold
                                    color: PanadoroStyle.colOnSurface
                                }

                                Rectangle {
                                    visible: rankRow.you
                                    implicitWidth: youText.implicitWidth + PanadoroStyle.gapSmall * 2
                                    implicitHeight: youText.implicitHeight + 4
                                    radius: PanadoroStyle.pill(implicitHeight)
                                    color: ColorUtils.applyAlpha(rankRow.accent, 0.16)

                                    StyledText {
                                        id: youText
                                        anchors.centerIn: parent
                                        text: Translation.tr("YOU")
                                        font.pixelSize: PanadoroStyle.textSmall
                                        font.weight: Font.Bold
                                        color: rankRow.accent
                                    }
                                }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                implicitHeight: 4
                                radius: 2
                                color: PanadoroStyle.colField

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
                                font.pixelSize: PanadoroStyle.textSmall
                                color: PanadoroStyle.colSubtext
                            }
                        }

                        StyledText {
                            text: root.duration(modelData.seconds)
                            font.family: PanadoroStyle.fontNumbers
                            font.variableAxes: PanadoroStyle.axesDigitsBold
                            font.pixelSize: PanadoroStyle.textNormal
                            color: rankRow.accent
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: root.ranked.length === 0
                implicitHeight: emptyColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: emptyColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: PanadoroStyle.gapSmall

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "emoji_events"
                        iconSize: 26
                        padding: 14
                        shape: "Cookie9Sided"
                        color: PanadoroStyle.colField
                        colSymbol: PanadoroStyle.colSubtext
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: PanadoroService.signedIn
                            ? Translation.tr("The podium is waiting.")
                            : Translation.tr("No shared focus yet.")
                        font.family: PanadoroStyle.fontTitle
                        font.variableAxes: PanadoroStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: PanadoroStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        text: PanadoroService.signedIn
                            ? Translation.tr("Publish a tag below and the first focus session puts you on the board.")
                            : Translation.tr("Sign in and make one tag public to start the board.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colSubtext
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                visible: PanadoroService.signedIn
                implicitHeight: nameColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: nameColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: PanadoroStyle.gapSmall

                    StyledText {
                        text: Translation.tr("How you appear")
                        font.family: PanadoroStyle.fontTitle
                        font.variableAxes: PanadoroStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: PanadoroStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("A display name for the ranks. Your email is never published.")
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colSubtext
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: PanadoroStyle.gapSmall

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
                visible: PanadoroService.signedIn
                implicitHeight: publicColumn.implicitHeight + PanadoroStyle.cardPadding * 2
                radius: PanadoroStyle.radiusLarge
                color: PanadoroStyle.colSurface

                ColumnLayout {
                    id: publicColumn
                    anchors {
                        left: parent.left
                        right: parent.right
                        top: parent.top
                        margins: PanadoroStyle.cardPadding
                    }
                    spacing: 2

                    StyledText {
                        text: Translation.tr("Public tags")
                        font.family: PanadoroStyle.fontTitle
                        font.variableAxes: PanadoroStyle.axesTitle
                        font.pixelSize: Appearance.font.pixelSize.large
                        color: PanadoroStyle.colOnSurface
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.bottomMargin: PanadoroStyle.gapSmall
                        text: Translation.tr("Flip a tag on to share its focus time for today, this week and this month.")
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colSubtext
                    }

                    Repeater {
                        model: PanadoroService.activeTags

                        ClockSettingsRow {
                            id: publicRow
                            required property var modelData
                            required property int index
                            first: publicRow.index === 0
                            last: publicRow.index === PanadoroService.activeTags.length - 1
                            symbol: String(publicRow.modelData.icon ?? "label")
                            title: String(publicRow.modelData.name ?? "")
                            description: PanadoroService.publicTagIds.indexOf(String(publicRow.modelData.id)) >= 0
                                ? Translation.tr("Visible on the ranks")
                                : Translation.tr("Private · stays here")

                            StyledSwitch {
                                checked: PanadoroService.publicTagIds.indexOf(String(publicRow.modelData.id)) >= 0
                                checkable: false
                                onClicked: root.togglePublic(publicRow.modelData.id)
                            }
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        Layout.topMargin: PanadoroStyle.gapSmall
                        text: Translation.tr("%1 of %2 tags public · habits, tasks and notes are never uploaded to the board.")
                            .arg(String(root.ownPublicTags.length))
                            .arg(String(PanadoroService.activeTags.length))
                        wrapMode: Text.WordWrap
                        font.pixelSize: PanadoroStyle.textSmall
                        color: PanadoroStyle.colSubtext
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: PanadoroStyle.gapSmall
                horizontalAlignment: Text.AlignHCenter
                text: root.updatedLabel.length > 0
                    ? Translation.tr("Updated %1 · the board refreshes every minute").arg(root.updatedLabel)
                    : Translation.tr("Waiting for the first sync.")
                font.pixelSize: PanadoroStyle.textSmall
                color: PanadoroStyle.colSubtext
            }

            Item { Layout.preferredHeight: PanadoroStyle.fabClearance }
        }
    }
}

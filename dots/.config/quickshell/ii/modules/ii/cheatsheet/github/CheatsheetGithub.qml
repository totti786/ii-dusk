pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.common
import qs.modules.common.widgets
import qs.services

/// A GitHub dashboard: who you are, a year of contributions, what needs you (reviews, pull
/// requests, issues, notifications), your latest repositories and what happened lately.
Item {
    id: root

    implicitWidth: 1400
    implicitHeight: 760

    readonly property var gh: GithubService
    readonly property bool wide: width >= 1080
    readonly property bool mid: width >= 760
    property bool reviewTab: false
    readonly property real gap: 16

    // ── what the numbers add up to ──
    readonly property var weekTotals: (root.gh.contrib.weeks ?? []).map(w => w.reduce((a, c) => a + c, 0))
    readonly property var weekdayTotals: {
        const t = [0, 0, 0, 0, 0, 0, 0];
        for (const w of root.gh.contrib.weeks ?? [])
            w.forEach((c, i) => { t[i] += c; });
        return t;
    }
    readonly property int todayCount: {
        const weeks = root.gh.contrib.weeks ?? [];
        const last = weeks.length > 0 ? weeks[weeks.length - 1] : [];
        return last.length > 0 ? last[last.length - 1] : 0;
    }
    readonly property int weekCount: root.weekTotals.length > 0 ? root.weekTotals[root.weekTotals.length - 1] : 0

    // The sections rise in one after another when the data first shows
    property real appear: 0
    NumberAnimation on appear { id: appearAnim; from: 0; to: 1; duration: 1000; running: false; easing.type: Easing.OutCubic }
    function reveal(i: int): real { return Math.max(0, Math.min(1, root.appear * 5 - i * 0.6)); }
    onVisibleChanged: if (visible && root.gh.hasData) appearAnim.restart()
    Connections {
        target: root.gh
        function onHasDataChanged() { if (root.gh.hasData) appearAnim.restart(); }
    }

    Component.onCompleted: { GithubService.retain(); if (root.gh.hasData) appearAnim.restart(); }
    Component.onDestruction: GithubService.release()

    function ciColor(state: string): color {
        switch (state) {
        case "SUCCESS": return "#5cc16f";
        case "FAILURE": case "ERROR": return Appearance.colors.colError;
        case "PENDING": case "EXPECTED": return "#e3b341";
        default: return Appearance.colors.colOutline;
        }
    }
    function ciIcon(state: string): string {
        switch (state) {
        case "SUCCESS": return "check_circle";
        case "FAILURE": case "ERROR": return "cancel";
        case "PENDING": case "EXPECTED": return "pending";
        default: return "radio_button_unchecked";
        }
    }
    function reviewLabel(r: string): string {
        return r === "APPROVED" ? Translation.tr("Approved") : r === "CHANGES_REQUESTED" ? Translation.tr("Changes requested")
            : r === "REVIEW_REQUIRED" ? Translation.tr("Needs review") : "";
    }
    function notifIcon(type: string): string {
        return type === "PullRequest" ? "merge" : type === "Issue" ? "adjust" : type === "Release" ? "sell" : type === "Discussion" ? "forum" : "notifications";
    }

    // ── nothing to show yet ──
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.gh.hasData
        spacing: 14
        width: Math.min(420, root.width - 48)
        MaterialSymbol {
            Layout.alignment: Qt.AlignHCenter
            text: root.gh.error !== "" ? (root.gh.errorKind === "auth" ? "key_off" : "cloud_off") : "hourglass_top"
            iconSize: 56
            color: Appearance.colors.colPrimary
            SequentialAnimation on opacity {
                running: root.gh.error === "" && !root.gh.hasData
                loops: Animation.Infinite
                NumberAnimation { to: 0.35; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
            }
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: root.gh.error === "" ? Translation.tr("Reaching GitHub…")
                : root.gh.errorKind === "auth" ? Translation.tr("Sign in to GitHub")
                : root.gh.errorKind === "missing" ? Translation.tr("The GitHub CLI is missing") : Translation.tr("GitHub did not answer")
            font.pixelSize: Appearance.font.pixelSize.larger
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnSurface
        }
        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: root.gh.error !== ""
            text: root.gh.errorKind === "auth" ? Translation.tr("Run  gh auth login  in a terminal, then come back.") : root.gh.error
            color: Appearance.colors.colOnSurfaceVariant
        }
        RippleButton {
            Layout.alignment: Qt.AlignHCenter
            visible: root.gh.error !== ""
            buttonText: Translation.tr("Try again")
            onClicked: GithubService.refresh()
        }
    }

    Rectangle {
        id: refreshBar
        z: 5
        anchors { left: parent.left; right: parent.right; top: parent.top }
        height: 3
        radius: 1.5
        color: "transparent"
        opacity: root.gh.refreshing && root.gh.hasData ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }
        Rectangle {
            width: parent.width * 0.3
            height: parent.height
            radius: 1.5
            color: Appearance.colors.colPrimary
            SequentialAnimation on x {
                running: refreshBar.opacity > 0
                loops: Animation.Infinite
                NumberAnimation { from: -200; to: refreshBar.width; duration: 1100; easing.type: Easing.InOutQuad }
            }
        }
    }

    Flickable {
        id: flick
        WheelScroll {}
        anchors.fill: parent
        visible: root.gh.hasData
        clip: true
        contentWidth: width
        contentHeight: page.implicitHeight + 24
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: page
            x: 12
            y: 8
            width: flick.width - 24
            spacing: root.gap

            // ── profile and the big numbers ──
            GridLayout {
                Layout.fillWidth: true
                columns: root.wide ? 2 : 1
                columnSpacing: root.gap
                rowSpacing: root.gap
                opacity: root.reveal(0)
                transform: Translate { y: (1 - root.reveal(0)) * 22 }

                ClippingRectangle {
                    id: hero
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    Layout.minimumHeight: 2 * 104 + 12
                    implicitHeight: Math.max(heroRow.implicitHeight + 40, 2 * 104 + 12)
                    radius: 26
                    color: Appearance.colors.colPrimaryContainer

                    Rectangle {
                        width: 320; height: 320; radius: 160
                        x: parent.width - 200; y: -140
                        color: Qt.rgba(Appearance.colors.colPrimary.r, Appearance.colors.colPrimary.g, Appearance.colors.colPrimary.b, 0.18)
                    }
                    Rectangle {
                        width: 180; height: 180; radius: 90
                        x: parent.width - 90; y: parent.height - 70
                        color: Qt.rgba(Appearance.colors.colTertiary.r, Appearance.colors.colTertiary.g, Appearance.colors.colTertiary.b, 0.2)
                    }

                    RowLayout {
                        id: heroRow
                        anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter; margins: 22 }
                        spacing: 20

                        ClippingRectangle {
                            implicitWidth: 96
                            implicitHeight: 96
                            radius: 48
                            color: Appearance.colors.colPrimary
                            border.width: 3
                            border.color: Appearance.colors.colOnPrimaryContainer
                            Image {
                                anchors.fill: parent
                                source: root.gh.user.avatar ? `${root.gh.user.avatar}&s=192` : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 4
                            StyledText {
                                Layout.fillWidth: true
                                text: root.gh.user.name ?? ""
                                elide: Text.ElideRight
                                font.pixelSize: 30
                                font.weight: Font.Bold
                                font.family: Appearance.font.family.title
                                color: Appearance.colors.colOnPrimaryContainer
                            }
                            StyledText {
                                text: `@${root.gh.user.login ?? ""}` + (root.gh.user.location ? `  ·  ${root.gh.user.location}` : "")
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.8
                            }
                            StyledText {
                                Layout.fillWidth: true
                                visible: (root.gh.user.bio ?? "") !== ""
                                text: root.gh.user.bio ?? ""
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                color: Appearance.colors.colOnPrimaryContainer
                                opacity: 0.9
                            }
                            Flow {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 8
                                Repeater {
                                    model: [
                                        { icon: "group", text: Translation.tr("%1 followers").arg(root.gh.user.followers ?? 0) },
                                        { icon: "person_add", text: Translation.tr("%1 following").arg(root.gh.user.following ?? 0) },
                                        { icon: "folder_open", text: Translation.tr("%1 public repos").arg(root.gh.user.publicRepos ?? 0) },
                                        { icon: "star", text: Translation.tr("%1 starred").arg(root.gh.user.starred ?? 0) },
                                        { icon: "today", text: Translation.tr("%1 today").arg(root.todayCount) },
                                        { icon: "date_range", text: Translation.tr("%1 this week").arg(root.weekCount) },
                                        { icon: "history", text: Translation.tr("Since %1").arg(new Date(root.gh.user.since ?? 0).getFullYear()) }
                                    ]
                                    delegate: Rectangle {
                                        required property var modelData
                                        implicitWidth: chipRow.implicitWidth + 20
                                        implicitHeight: 28
                                        radius: 14
                                        color: Qt.rgba(1, 1, 1, 0.14)
                                        Row {
                                            id: chipRow
                                            anchors.centerIn: parent
                                            spacing: 6
                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: parent.parent.modelData.icon
                                                iconSize: 16
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                            StyledText {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: parent.parent.modelData.text
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnPrimaryContainer
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        ColumnLayout {
                            spacing: 8
                            RippleButton {
                                buttonText: Translation.tr("Open GitHub")
                                onClicked: GithubService.open(root.gh.user.url)
                            }
                            RippleButton {
                                buttonText: root.gh.refreshing ? Translation.tr("Refreshing…") : Translation.tr("Refresh")
                                enabled: !root.gh.refreshing
                                onClicked: GithubService.refresh()
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredWidth: 1
                    columns: 2
                    columnSpacing: 12
                    rowSpacing: 12
                    GhStat {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        container: Appearance.colors.colPrimary
                        onContainer: Appearance.colors.colOnPrimary
                        symbol: "local_fire_department"
                        target: root.gh.contrib.current ?? 0
                        caption: Translation.tr("Day streak")
                        hint: Translation.tr("best %1").arg(root.gh.contrib.longest ?? 0)
                    }
                    GhStat {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        symbol: "commit"
                        target: root.gh.contrib.total ?? 0
                        caption: Translation.tr("Contributions, past year")
                        container: Appearance.colors.colSecondaryContainer
                        onContainer: Appearance.colors.colOnSecondaryContainer
                    }
                    GhStat {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        symbol: "merge"
                        target: root.gh.pullRequests.count ?? 0
                        caption: Translation.tr("Open pull requests")
                        container: Appearance.colors.colTertiaryContainer
                        onContainer: Appearance.colors.colOnTertiaryContainer
                    }
                    GhStat {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        symbol: "star"
                        target: root.gh.data.stars ?? 0
                        caption: Translation.tr("Stars received")
                        container: Appearance.colors.colSurfaceContainerHigh
                        onContainer: Appearance.colors.colOnSurface
                    }
                }
            }

            // ── a year of contributions ──
            GhCard {
                Layout.fillWidth: true
                title: Translation.tr("Contributions")
                symbol: "grid_view"
                badge: Translation.tr("%1 in the last year").arg(Number(root.gh.contrib.total ?? 0).toLocaleString(Qt.locale(), "f", 0))
                implicitHeight: 62 + heat.implicitHeight + 76 + 18 + 190
                opacity: root.reveal(1)
                transform: Translate { y: (1 - root.reveal(1)) * 22 }

                GhHeatmap {
                    id: heat
                    width: parent.width
                    weeks: root.gh.contrib.weeks ?? []
                    dates: root.gh.contrib.dates ?? []
                }
                Row {
                    anchors { left: parent.left; right: parent.right; top: heat.bottom; topMargin: 14 }
                    spacing: 10
                    Repeater {
                        model: [
                            { icon: "commit", label: Translation.tr("Commits"), value: root.gh.contrib.commits },
                            { icon: "merge", label: Translation.tr("Pull requests"), value: root.gh.contrib.prs },
                            { icon: "adjust", label: Translation.tr("Issues"), value: root.gh.contrib.issues },
                            { icon: "rate_review", label: Translation.tr("Reviews"), value: root.gh.contrib.reviews },
                            { icon: "lock", label: Translation.tr("Private"), value: root.gh.contrib.private }
                        ]
                        delegate: Rectangle {
                            required property var modelData
                            width: (parent.width - 40) / 5
                            height: 58
                            radius: 18
                            color: Appearance.colors.colSurfaceContainerHigh
                            Row {
                                anchors.centerIn: parent
                                spacing: 10
                                MaterialSymbol {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.parent.modelData.icon
                                    iconSize: 22
                                    color: Appearance.colors.colPrimary
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    StyledText {
                                        text: String(parent.parent.parent.modelData.value ?? 0)
                                        font.pixelSize: Appearance.font.pixelSize.larger
                                        font.weight: Font.Bold
                                        color: Appearance.colors.colOnSurface
                                    }
                                    StyledText {
                                        text: parent.parent.parent.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colOnSurfaceVariant
                                    }
                                }
                            }
                        }
                    }
                }
                Row {
                    anchors { left: parent.left; right: parent.right; top: heat.bottom; topMargin: 14 + 58 + 14 }
                    height: 150
                    spacing: 16
                    Rectangle {
                        width: parent.width * 0.64 - 8
                        height: parent.height
                        radius: 20
                        color: Appearance.colors.colSurfaceContainerHigh
                        GhSpark {
                            anchors { fill: parent; margins: 14 }
                            values: root.weekTotals
                            dates: root.gh.contrib.dates ?? []
                        }
                    }
                    Rectangle {
                        width: parent.width * 0.36 - 8
                        height: parent.height
                        radius: 20
                        color: Appearance.colors.colSurfaceContainerHigh
                        GhWeekdays {
                            anchors { fill: parent; margins: 14 }
                            totals: root.weekdayTotals
                        }
                    }
                }
            }

            // ── what needs you ──
            GridLayout {
                Layout.fillWidth: true
                opacity: root.reveal(2)
                transform: Translate { y: (1 - root.reveal(2)) * 22 }
                columns: root.wide ? 3 : root.mid ? 2 : 1
                columnSpacing: root.gap
                rowSpacing: root.gap

                GhCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: root.reviewTab ? Translation.tr("Review requests") : Translation.tr("Pull requests")
                    symbol: root.reviewTab ? "rate_review" : "merge"
                    accent: Appearance.colors.colTertiary
                    badge: String(root.reviewTab ? root.gh.reviews.count : root.gh.pullRequests.count)
                    implicitHeight: 78 + Math.max(1, list1.count) * 56 + 16
                    headerExtras: [
                        RippleButton {
                            implicitHeight: 28
                            buttonText: root.reviewTab ? Translation.tr("Mine") : Translation.tr("To review")
                            onClicked: root.reviewTab = !root.reviewTab
                        }
                    ]
                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            id: list1
                            model: root.reviewTab ? root.gh.reviews.items : root.gh.pullRequests.items
                            delegate: GhRow {
                                required property var modelData
                                width: parent.width
                                symbol: root.reviewTab ? "rate_review" : modelData.draft ? "edit_note" : root.ciIcon(modelData.ci)
                                tone: root.reviewTab ? Appearance.colors.colTertiary : modelData.draft ? Appearance.colors.colOutline : root.ciColor(modelData.ci)
                                title: modelData.title
                                subtitle: `${modelData.repo} #${modelData.number}` + (root.reviewTab && modelData.author ? ` · ${modelData.author}` : "")
                                trailing: root.reviewTab ? root.gh.ago(modelData.updated) : (root.reviewLabel(modelData.review) || root.gh.ago(modelData.updated))
                                url: modelData.url
                            }
                        }
                        StyledText {
                            visible: list1.count === 0
                            width: parent.width
                            topPadding: 14
                            horizontalAlignment: Text.AlignHCenter
                            text: root.reviewTab ? Translation.tr("Nothing waiting for your review") : Translation.tr("No open pull requests")
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                GhCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Issues")
                    symbol: "adjust"
                    accent: "#e3b341"
                    badge: String(root.gh.issues.count)
                    implicitHeight: 78 + Math.max(1, list2.count) * 56 + 16
                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            id: list2
                            model: root.gh.issues.items
                            delegate: GhRow {
                                required property var modelData
                                width: parent.width
                                symbol: "adjust"
                                tone: "#e3b341"
                                title: modelData.title
                                subtitle: `${modelData.repo} #${modelData.number}`
                                trailing: root.gh.ago(modelData.updated)
                                url: modelData.url
                            }
                        }
                        StyledText {
                            visible: list2.count === 0
                            width: parent.width
                            topPadding: 14
                            horizontalAlignment: Text.AlignHCenter
                            text: Translation.tr("No open issues assigned to you")
                            color: Appearance.colors.colOnSurfaceVariant
                        }
                    }
                }

                GhCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    Layout.alignment: Qt.AlignTop
                    Layout.columnSpan: root.wide || !root.mid ? 1 : 2
                    title: Translation.tr("Notifications")
                    symbol: "notifications"
                    accent: Appearance.colors.colPrimary
                    badge: root.gh.unread > 0 ? Translation.tr("%1 new").arg(root.gh.unread) : ""
                    implicitHeight: 78 + Math.max(1, Math.min(6, list3.count)) * 56 + 16
                    headerExtras: [
                        RippleButton {
                            visible: root.gh.unread > 0
                            implicitHeight: 28
                            buttonText: Translation.tr("Mark all read")
                            onClicked: GithubService.markAllRead()
                        }
                    ]
                    Column {
                        width: parent.width
                        spacing: 2
                        Repeater {
                            id: list3
                            model: root.gh.notifications.slice(0, 6)
                            delegate: GhRow {
                                required property var modelData
                                width: parent.width
                                symbol: root.notifIcon(modelData.type)
                                tone: modelData.unread ? Appearance.colors.colPrimary : Appearance.colors.colOutline
                                title: modelData.title
                                subtitle: `${modelData.repo} · ${modelData.reason}`
                                trailing: root.gh.ago(modelData.updated)
                            }
                        }
                        Column {
                            visible: list3.count === 0
                            width: parent.width
                            topPadding: 10
                            spacing: 6
                            MaterialSymbol {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: "inbox"
                                iconSize: 30
                                color: Appearance.colors.colOutline
                            }
                            StyledText {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                text: Translation.tr("You are all caught up")
                                color: Appearance.colors.colOnSurfaceVariant
                            }
                        }
                    }
                }
            }

            // ── repositories and what happened lately ──
            GridLayout {
                Layout.fillWidth: true
                opacity: root.reveal(3)
                transform: Translate { y: (1 - root.reveal(3)) * 22 }
                columns: root.mid ? 2 : 1
                columnSpacing: root.gap
                rowSpacing: root.gap

                GhCard {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    Layout.alignment: Qt.AlignTop
                    title: Translation.tr("Recently pushed")
                    symbol: "folder_open"
                    badge: String(root.gh.repos.length)
                    implicitHeight: 78 + repoList.count * 74 + 16
                    Column {
                        width: parent.width
                        spacing: 4
                        Repeater {
                            id: repoList
                            model: root.gh.repos
                            delegate: Rectangle {
                                id: repoCard
                                required property var modelData
                                width: parent.width
                                height: 70
                                radius: 18
                                color: repoArea.containsMouse ? Appearance.colors.colSurfaceContainerHigh : "transparent"
                                Behavior on color { ColorAnimation { duration: 120 } }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 10; rightMargin: 14 }
                                    spacing: 12
                                    Rectangle {
                                        implicitWidth: 40
                                        implicitHeight: 40
                                        radius: 14
                                        color: Qt.rgba(1, 1, 1, 0.06)
                                        border.width: 2
                                        border.color: repoCard.modelData.langColor || Appearance.colors.colOutlineVariant
                                        MaterialSymbol {
                                            anchors.centerIn: parent
                                            text: repoCard.modelData.private ? "lock" : "book_2"
                                            iconSize: 20
                                            color: repoCard.modelData.langColor || Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.minimumWidth: 0
                                        spacing: 1
                                        RowLayout {
                                            spacing: 8
                                            StyledText {
                                                text: repoCard.modelData.name
                                                font.weight: Font.DemiBold
                                                color: Appearance.colors.colOnSurface
                                            }
                                            Rectangle {
                                                visible: repoCard.modelData.private
                                                implicitWidth: privText.implicitWidth + 12
                                                implicitHeight: 18
                                                radius: 9
                                                color: Appearance.colors.colSurfaceContainerHighest
                                                StyledText {
                                                    id: privText
                                                    anchors.centerIn: parent
                                                    text: Translation.tr("Private")
                                                    font.pixelSize: Appearance.font.pixelSize.smallest
                                                    color: Appearance.colors.colOnSurfaceVariant
                                                }
                                            }
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            text: repoCard.modelData.commit || repoCard.modelData.desc
                                            elide: Text.ElideRight
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                    Row {
                                        spacing: 14
                                        Row {
                                            visible: repoCard.modelData.lang !== ""
                                            spacing: 5
                                            anchors.verticalCenter: parent.verticalCenter
                                            Rectangle {
                                                anchors.verticalCenter: parent.verticalCenter
                                                width: 10; height: 10; radius: 5
                                                color: repoCard.modelData.langColor || Appearance.colors.colOutline
                                            }
                                            StyledText {
                                                text: repoCard.modelData.lang
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                        Row {
                                            visible: repoCard.modelData.stars > 0
                                            spacing: 3
                                            anchors.verticalCenter: parent.verticalCenter
                                            MaterialSymbol {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "star"
                                                iconSize: 15
                                                fill: 1
                                                color: "#e3b341"
                                            }
                                            StyledText {
                                                text: String(repoCard.modelData.stars)
                                                font.pixelSize: Appearance.font.pixelSize.smaller
                                                color: Appearance.colors.colOnSurfaceVariant
                                            }
                                        }
                                        MaterialSymbol {
                                            visible: repoCard.modelData.ci !== ""
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.ciIcon(repoCard.modelData.ci)
                                            iconSize: 20
                                            fill: 1
                                            color: root.ciColor(repoCard.modelData.ci)
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 74
                                            horizontalAlignment: Text.AlignRight
                                            text: root.gh.ago(repoCard.modelData.pushed)
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }
                                MouseArea {
                                    id: repoArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: GithubService.open(repoCard.modelData.url)
                                }
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.preferredWidth: 2
                    Layout.alignment: Qt.AlignTop
                    spacing: root.gap

                    GhCard {
                        Layout.fillWidth: true
                        title: Translation.tr("Languages")
                        symbol: "code"
                        accent: Appearance.colors.colSecondary
                        implicitHeight: 78 + 30 + langFlow.implicitHeight + 8
                        Column {
                            width: parent.width
                            spacing: 14
                            Row {
                                width: parent.width
                                height: 14
                                spacing: 3
                                Repeater {
                                    model: root.gh.languages
                                    delegate: Rectangle {
                                        required property var modelData
                                        width: Math.max(8, (parent.width - 3 * Math.max(0, root.gh.languages.length - 1)) * modelData.repos / Math.max(1, root.gh.languages.reduce((a, l) => a + l.repos, 0)))
                                        height: 14
                                        radius: 7
                                        color: modelData.color
                                    }
                                }
                            }
                            Flow {
                                id: langFlow
                                width: parent.width
                                spacing: 14
                                Repeater {
                                    model: root.gh.languages
                                    delegate: Row {
                                        required property var modelData
                                        spacing: 6
                                        Rectangle {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 10; height: 10; radius: 5
                                            color: parent.modelData.color
                                        }
                                        StyledText {
                                            text: `${parent.modelData.name}  ${parent.modelData.repos}`
                                            font.pixelSize: Appearance.font.pixelSize.smaller
                                            color: Appearance.colors.colOnSurfaceVariant
                                        }
                                    }
                                }
                            }
                        }
                    }

                    GhCard {
                        Layout.fillWidth: true
                        title: Translation.tr("Recent activity")
                        symbol: "bolt"
                        accent: Appearance.colors.colTertiary
                        implicitHeight: 78 + Math.min(6, feedList.count) * 54 + 16
                        Column {
                            width: parent.width
                            spacing: 2
                            Repeater {
                                id: feedList
                                model: root.gh.feed.slice(0, 6)
                                delegate: GhRow {
                                    required property var modelData
                                    width: parent.width
                                    implicitHeight: 52
                                    symbol: modelData.icon
                                    tone: Appearance.colors.colTertiary
                                    title: modelData.title
                                    subtitle: modelData.detail !== "" ? `${modelData.repo} · ${modelData.detail}` : modelData.repo
                                    trailing: root.gh.ago(modelData.time)
                                    url: `https://github.com/${modelData.repo}`
                                }
                            }
                        }
                    }
                }
            }

            StyledText {
                Layout.alignment: Qt.AlignHCenter
                text: root.gh.error !== "" ? Translation.tr("Offline: showing what was saved. %1").arg(root.gh.error)
                    : Translation.tr("Updated %1").arg(root.gh.ago(root.gh.data.fetched ?? ""))
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colOutline
            }
        }
    }
}

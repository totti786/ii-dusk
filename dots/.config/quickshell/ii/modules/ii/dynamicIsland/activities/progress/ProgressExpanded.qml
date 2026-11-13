pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Every background job in the auxiliary bubble's card: a download, a torrent, a copy, a speed
 * test. Each row says what it is, how far along, how fast and how long is left, and a job the
 * shell started can be stopped from here. Programs that report their own jobs (a file copy)
 * show but stay theirs to stop.
 *
 * Self-contained on purpose: the bubble loads cards by URL, and such a file gets none of its
 * directory's types. It reads ProgressService, which the island already follows.
 */
Item {
    id: root

    readonly property var jobs: ProgressService.jobs
    readonly property var running: ProgressService.runningJobs
    readonly property int maxRows: 5
    readonly property bool onlyPaused: root.running.length === 0 && ProgressService.pausedJobs.length > 0 && ProgressService.pausedJobs.length === root.jobs.length
    readonly property bool anyFailed: root.running.length === 0 && root.jobs.some(j => j.state === "failed")
    readonly property var heroItems: [heroDisc]

    readonly property string title: root.running.length > 1 ? Translation.tr("%1 jobs running").arg(root.running.length)
        : root.running.length === 1 ? (root.running[0].appName || Translation.tr("Background job"))
        : root.onlyPaused ? Translation.tr("Paused")
        : root.anyFailed ? Translation.tr("Something failed")
        : Translation.tr("All done")
    readonly property string subtitle: root.running.length > 0 || root.onlyPaused
        ? Translation.tr("%1% overall").arg(Math.round(ProgressService.overallFraction * 100))
        : (root.jobs.length > root.maxRows ? Translation.tr("+%1 more").arg(root.jobs.length - root.maxRows) : "")

    readonly property real margin: 14
    readonly property real preferredExpandedWidth: 340
    readonly property real preferredExpandedHeight: column.implicitHeight + 2 * root.margin

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: root.margin
        }
        spacing: 12

        // ── Header ──
        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Rectangle {
                id: heroDisc
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                radius: width / 2
                color: root.anyFailed ? Appearance.colors.colErrorContainer : Appearance.colors.colPrimaryContainer
                MaterialSymbol {
                    anchors.centerIn: parent
                    text: root.running.length > 0 ? (root.running[0].icon ?? "downloading") : (root.onlyPaused ? "pause" : (root.anyFailed ? "error" : "check"))
                    iconSize: 22
                    fill: 1
                    color: root.anyFailed ? Appearance.colors.colOnErrorContainer : Appearance.colors.colOnPrimaryContainer
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: text.length > 0
                    text: root.subtitle
                    elide: Text.ElideRight
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.features: ({ "tnum": 1 })
                    color: Appearance.colors.colSubtext
                }
            }

            CornerButton {
                glyph: "download"
                tip: Translation.tr("Open Downloads")
                onClicked: GlobalStates.openDownloadsApp("")
            }
            CornerButton {
                glyph: "downloading"
                tip: Translation.tr("Open Torrents")
                onClicked: GlobalStates.openTorrentsApp("")
            }
        }

        // ── The jobs ──
        ColumnLayout {
            id: jobsColumn
            Layout.fillWidth: true
            spacing: 6

            // Rows are keyed by job id: a new job list on every progress tick must update the
            // rows that are there, not rebuild them (a rebuilt bar animates up from empty).
            ListModel { id: rowIds }
            function syncRows(): void {
                const want = root.jobs.slice(0, root.maxRows).map(j => String(j.id));
                for (let i = 0; i < want.length; i++) {
                    if (i < rowIds.count && rowIds.get(i).jobId === want[i])
                        continue;
                    if (i < rowIds.count)
                        rowIds.set(i, { jobId: want[i] });
                    else
                        rowIds.append({ jobId: want[i] });
                }
                while (rowIds.count > want.length)
                    rowIds.remove(rowIds.count - 1);
            }
            Connections {
                target: root
                function onJobsChanged() { jobsColumn.syncRows(); }
            }
            Component.onCompleted: jobsColumn.syncRows()

            Repeater {
                model: rowIds

                delegate: Rectangle {
                    id: row
                    required property string jobId
                    readonly property var modelData: root.jobs.find(j => String(j.id) === row.jobId) ?? ({})
                    readonly property bool running: row.modelData.state === "running"
                    readonly property bool failed: row.modelData.state === "failed"
                    readonly property bool paused: row.modelData.state === "paused"
                    readonly property string detail: {
                        if (row.paused)
                            return Translation.tr("Paused") + "  ·  " + Math.round(row.modelData.percent ?? 0) + "%";
                        if (!row.running)
                            return row.modelData.doneText || (row.failed ? Translation.tr("Failed") : Translation.tr("Done"));
                        const parts = [Math.round(row.modelData.percent ?? 0) + "%"];
                        if (row.modelData.speedText)
                            parts.push(row.modelData.speedText);
                        if (row.modelData.etaText)
                            parts.push(row.modelData.etaText);
                        return parts.join("  ·  ");
                    }

                    Layout.fillWidth: true
                    implicitHeight: rowLayout.implicitHeight + 20
                    radius: Appearance.rounding.normal
                    color: Appearance.colors.colSurfaceContainerHigh

                    RowLayout {
                        id: rowLayout
                        anchors {
                            left: parent.left
                            right: parent.right
                            verticalCenter: parent.verticalCenter
                            leftMargin: 12
                            rightMargin: 8
                        }
                        spacing: 10

                        MaterialSymbol {
                            text: row.failed ? "error" : (row.paused ? "pause_circle" : (row.running ? (row.modelData.icon ?? "downloading") : "check_circle"))
                            iconSize: 20
                            fill: row.running ? 0 : 1
                            color: row.failed ? Appearance.colors.colError : Appearance.colors.colPrimary
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            spacing: 4

                            StyledText {
                                Layout.fillWidth: true
                                text: row.modelData.message || row.modelData.appName
                                elide: Text.ElideMiddle
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.colors.colOnSurface
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                visible: row.running || row.paused
                                implicitHeight: 4
                                radius: 2
                                color: Appearance.colors.colSurfaceContainerHighest
                                Rectangle {
                                    width: parent.width * Math.max(0, Math.min(1, (row.modelData.percent ?? 0) / 100))
                                    height: parent.height
                                    radius: 2
                                    color: row.paused ? Appearance.colors.colOutline : Appearance.colors.colPrimary
                                    Behavior on width {
                                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                                    }
                                }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                text: row.detail
                                elide: Text.ElideRight
                                font.pixelSize: Appearance.font.pixelSize.smaller
                                font.features: ({ "tnum": 1 })
                                color: row.failed ? Appearance.colors.colError : Appearance.colors.colSubtext
                            }
                        }

                        CornerButton {
                            visible: ProgressService.canResume(row.modelData)
                            glyph: "play_arrow"
                            tip: Translation.tr("Resume")
                            onClicked: ProgressService.resumeJob(row.modelData)
                        }
                        CornerButton {
                            visible: ProgressService.canCancel(row.modelData)
                            glyph: String(row.modelData.id).startsWith("qb:") ? "pause" : "close"
                            tip: String(row.modelData.id).startsWith("qb:") ? Translation.tr("Pause") : Translation.tr("Cancel")
                            onClicked: ProgressService.cancelJob(row.modelData)
                        }
                    }
                }
            }

            StyledText {
                visible: root.jobs.length === 0
                Layout.fillWidth: true
                text: Translation.tr("Nothing is running.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
            }
        }
    }

    component CornerButton: RippleButton {
        id: cornerButton
        property string glyph
        property string tip

        implicitWidth: 32
        implicitHeight: 32
        buttonRadius: Appearance.rounding.full
        colBackground: Appearance.colors.colSurfaceContainerHigh
        colBackgroundHover: Appearance.colors.colSurfaceContainerHighest

        contentItem: Item {
            MaterialSymbol {
                anchors.centerIn: parent
                text: cornerButton.glyph
                iconSize: 18
                color: Appearance.colors.colOnSurface
            }
        }

        StyledToolTip {
            text: cornerButton.tip
        }
    }
}

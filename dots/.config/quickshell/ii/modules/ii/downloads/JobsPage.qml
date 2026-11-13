pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/** The downloads under way (finished: false) or the ones that are over (finished: true). */
Rectangle {
    id: root

    property bool finished: false
    property bool compact: false
    property real layoutWidth: root.width

    readonly property var jobs: root.finished ? DownloadsService.finishedJobs : DownloadsService.activeJobs
    readonly property real padding: 0
    readonly property real contentWidth: root.width

    color: "transparent"

    // Every poll hands over a fresh array of jobs. Feeding that straight to a Repeater tears
    // every card down and builds it again, so a progress bar restarted from nothing each
    // tick. The model holds only the ids and is edited in place; each card looks its job up
    // by id, so a new percentage just moves the bar it already has.
    ListModel {
        id: idModel
    }

    function jobById(id: string): var {
        return root.jobs.find(j => String(j.id) === id) ?? null;
    }

    function syncIds(): void {
        const want = root.jobs.map(j => String(j.id));
        for (let i = idModel.count - 1; i >= 0; i--)
            if (!want.includes(idModel.get(i).jobId))
                idModel.remove(i);
        for (let i = 0; i < want.length; i++) {
            if (i < idModel.count && idModel.get(i).jobId === want[i])
                continue;
            let at = -1;
            for (let k = i + 1; k < idModel.count; k++)
                if (idModel.get(k).jobId === want[i]) { at = k; break; }
            if (at >= 0)
                idModel.move(at, i, 1);
            else
                idModel.insert(i, { jobId: want[i] });
        }
    }

    onJobsChanged: root.syncIds()
    Component.onCompleted: root.syncIds()

    ClockEmptyState {
        visible: root.jobs.length === 0
        anchors.centerIn: parent
        symbol: root.finished ? "history" : "downloading"
        title: root.finished ? Translation.tr("Nothing downloaded yet") : Translation.tr("No downloads in progress")
        subtitle: root.finished ? Translation.tr("Finished downloads stay here until you remove them")
            : Translation.tr("Queue something from the Download tab")
    }

    Flickable {
        WheelScroll {}
        id: flick
        anchors.fill: parent
        visible: root.jobs.length > 0
        contentWidth: width
        contentHeight: list.implicitHeight + root.padding * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: list
            x: Math.max(root.padding, (flick.width - root.contentWidth) / 2)
            y: root.padding
            width: root.contentWidth
            spacing: ClockStyle.paneGap

            ClockHero {
                Layout.fillWidth: true
                compact: root.compact
                symbol: root.finished ? "history" : "downloading"
                title: root.finished ? Translation.tr("Everything you saved") : Translation.tr("Downloads under way")
                text: root.finished ? Translation.tr("Finished downloads stay here until you remove them.") : Translation.tr("Progress of each download, which you can cancel at any time.")
            }

            RowLayout {
                visible: root.finished
                Layout.fillWidth: true
                Item { Layout.fillWidth: true }
                ClockButton {
                    variant: "text"
                    symbol: "folder_open"
                    label: Translation.tr("Open downloads folder")
                    onClicked: DownloadsService.openFolder(DownloadsService.settings.dir ?? "")
                }
                ClockButton {
                    variant: "text"
                    symbol: "delete_sweep"
                    label: Translation.tr("Clear list")
                    onClicked: DownloadsService.clearFinished()
                }
            }

            ClockPane {
                Layout.fillWidth: true
                title: root.finished ? Translation.tr("History") : Translation.tr("Queue")
                symbol: root.finished ? "history" : "downloading"
                count: root.jobs.length
                Repeater {
                    model: idModel
                    delegate: JobCard {
                        required property string jobId
                        readonly property var current: root.jobById(jobId)
                        visible: current !== null
                        job: current ?? ({ status: "", percent: 0 })
                    }
                }
            }
        }
    }
}

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * Shown while recordings are missing, while they download and when a download failed: what
 * is missing, a button to fetch it, then a bar with the sound being fetched.
 */
Rectangle {
    id: root

    readonly property bool failed: !SoundscapesService.downloading && SoundscapesService.downloadError.length > 0
    readonly property bool busy: SoundscapesService.downloading
    readonly property bool lacking: SoundscapesService.missingClips > 0 && !SoundscapesService.needsDownload
    // The recordings average about 1.6 MB each
    readonly property int megabytes: Math.max(1, Math.round(SoundscapesService.missingClips * 1.6))

    visible: root.busy || root.failed || root.lacking
    implicitHeight: row.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusCard
    color: root.failed ? ClockStyle.colErrorContainer : ClockStyle.colSecondaryContainer
    Behavior on color {
        animation: ClockStyle.motionFast.colorAnimation.createObject(this)
    }

    RowLayout {
        id: row
        anchors {
            fill: parent
            margins: ClockStyle.gap
            leftMargin: ClockStyle.gapLarge
            rightMargin: ClockStyle.gapLarge
        }
        spacing: ClockStyle.gapLarge

        ClockBadge {
            size: 48
            text: root.failed ? "error" : root.busy ? "downloading" : "cloud_download"
            shape: root.busy ? MaterialShape.Shape.Sunny : MaterialShape.Shape.Cookie9Sided
            color: root.failed ? ClockStyle.colError : ClockStyle.colPrimary
            colSymbol: root.failed ? ClockStyle.colOnError : ClockStyle.colOnPrimary
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.minimumWidth: 0
            spacing: 2
            StyledText {
                Layout.fillWidth: true
                text: root.failed ? Translation.tr("The download did not finish")
                    : root.busy ? (SoundscapesService.downloadTotal > 0 ? Translation.tr("Downloading the sounds…") : Translation.tr("Contacting the library…"))
                    : Translation.tr("Some sounds are not downloaded")
                elide: Text.ElideRight
                font.family: Appearance.font.family.title
                font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
                font.pixelSize: ClockStyle.textLarge
                color: root.failed ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer
            }
            StyledText {
                Layout.fillWidth: true
                text: root.failed ? SoundscapesService.downloadError
                    : root.busy ? (SoundscapesService.downloadTotal > 0
                        ? `${SoundscapesService.downloadSound} · ${SoundscapesService.downloadDone} / ${SoundscapesService.downloadTotal}` : "")
                    : Translation.tr("%1 of %2 recordings are missing, about %3 MB to fetch.").arg(SoundscapesService.missingClips).arg(SoundscapesService.totalClips).arg(root.megabytes)
                wrapMode: Text.WordWrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.pixelSize: ClockStyle.textSmall
                color: root.failed ? ClockStyle.colOnErrorContainer : ClockStyle.colOnSecondaryContainer
                opacity: 0.85
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: ClockStyle.gapTiny
                visible: root.busy
                implicitHeight: 8
                radius: 4
                color: Qt.rgba(ClockStyle.colOnSecondaryContainer.r, ClockStyle.colOnSecondaryContainer.g, ClockStyle.colOnSecondaryContainer.b, 0.18)
                Rectangle {
                    width: parent.width * SoundscapesService.downloadProgress
                    height: parent.height
                    radius: 4
                    color: ClockStyle.colPrimary
                    Behavior on width {
                        NumberAnimation { duration: Appearance.animation.elementMoveFast.duration; easing.type: Appearance.animation.elementMoveFast.type; easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve }
                    }
                }
            }
        }

        ClockButton {
            visible: !root.busy
            symbol: root.failed ? "refresh" : "download"
            label: root.failed ? Translation.tr("Try again") : Translation.tr("Download")
            variant: "filled"
            danger: root.failed
            onClicked: SoundscapesService.download()
        }
    }
}

import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components
import ".."

/**
 * Side sheet for one sound: what it is, how it plays, and where it comes from. Most of the
 * recordings are CC BY, which asks for credit, so every source is listed with its author,
 * licence and link.
 */
ClockSheet {
    id: root

    required property string soundId

    readonly property var sound: SoundscapesService.sound(root.soundId)
    readonly property var look: SoundscapesService.styleOf(root.sound?.groupId ?? "")
    readonly property bool on: SoundscapesService.isOn(root.soundId)
    readonly property real totalSeconds: (root.sound?.clips ?? []).reduce((sum, c) => sum + c.duration, 0)

    title: root.sound?.name ?? ""
    subtitle: root.sound?.group ?? ""

    function licenseLabel(license) {
        if (!license || license === "unspecified")
            return "";
        return license.replace(/-/g, " ").replace("GPL 3.0 only", "GPL 3.0");
    }
    function clipLength(seconds) {
        return seconds >= 60 ? `${Math.floor(seconds / 60)}:${String(Math.round(seconds % 60)).padStart(2, "0")}` : `${Math.round(seconds)} s`;
    }

    SoundBadge {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: ClockStyle.gapSmall
        size: 104
        icon: root.sound?.icon ?? ""
        shapeName: SoundscapesStyle.morphOf(root.look.shape)
        colShape: SoundscapesStyle.accent(root.look.tone)
        colIcon: SoundscapesStyle.onAccent(root.look.tone)
        spinning: root.on && SoundscapesService.playing
    }

    Flow {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        spacing: 6
        Repeater {
            model: root.sound?.tags ?? []
            delegate: Rectangle {
                required property string modelData
                implicitWidth: tagText.implicitWidth + 20
                implicitHeight: 26
                radius: 13
                color: ClockStyle.colField
                StyledText {
                    id: tagText
                    anchors.centerIn: parent
                    text: parent.modelData
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colOnSurfaceVariant
                }
            }
        }
    }

    // How it plays
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: howRow.implicitHeight + ClockStyle.gap * 2
        radius: ClockStyle.radiusLarge
        color: ClockStyle.colField
        RowLayout {
            id: howRow
            anchors {
                fill: parent
                margins: ClockStyle.gap
            }
            spacing: ClockStyle.gap
            MaterialSymbol {
                text: (root.sound?.silence ?? 0) > 0 ? "timelapse" : "all_inclusive"
                iconSize: ClockStyle.iconLarge
                color: ClockStyle.colPrimary
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    text: (root.sound?.silence ?? 0) > 0 ? Translation.tr("Comes and goes") : Translation.tr("Plays continuously")
                    font.weight: Font.DemiBold
                    font.pixelSize: ClockStyle.textNormal
                    color: ClockStyle.colOnSurface
                }
                StyledText {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: (root.sound?.silence ?? 0) > 0
                        ? Translation.tr("A random clip, then a quiet spell you set with the Often / Rarely slider. %1 clips.").arg((root.sound?.clips ?? []).length)
                        : (root.totalSeconds > 0 ? Translation.tr("One recording, looped (%1).").arg(root.clipLength(root.totalSeconds)) : Translation.tr("One recording, looped."))
                    font.pixelSize: ClockStyle.textSmall
                    color: ClockStyle.colSubtext
                }
            }
        }
    }

    StyledText {
        Layout.topMargin: ClockStyle.gapSmall
        visible: (root.sound?.credits ?? []).length > 0
        text: Translation.tr("Recorded by")
        font.family: Appearance.font.family.title
        font.variableAxes: ({ "wght": 650, "wdth": 100, "ROND": 100 })
        font.pixelSize: ClockStyle.textLarge
        color: ClockStyle.colOnSurface
    }
    Repeater {
        model: root.sound?.credits ?? []
        delegate: Rectangle {
            id: credit
            required property var modelData
            Layout.fillWidth: true
            implicitHeight: creditRow.implicitHeight + ClockStyle.gap * 2
            radius: ClockStyle.radiusLarge
            color: ClockStyle.colField

            RowLayout {
                id: creditRow
                anchors {
                    fill: parent
                    margins: ClockStyle.gap
                }
                spacing: ClockStyle.gapSmall
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        text: credit.modelData.title
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textNormal
                        font.weight: Font.DemiBold
                        color: ClockStyle.colOnSurface
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: [credit.modelData.author, root.licenseLabel(credit.modelData.license)].filter(t => t && t.length > 0).join(" · ")
                        elide: Text.ElideRight
                        font.pixelSize: ClockStyle.textSmall
                        color: ClockStyle.colSubtext
                    }
                }
                ClockIconButton {
                    visible: credit.modelData.url.length > 0
                    symbol: "open_in_new"
                    size: 36
                    iconSize: 18
                    tooltip: Translation.tr("Open the source")
                    onClicked: Qt.openUrlExternally(credit.modelData.url)
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: (root.sound?.credits ?? []).length === 0
        text: Translation.tr("The Noice library lists no outside source for this recording.")
        wrapMode: Text.WordWrap
        font.pixelSize: ClockStyle.textSmall
        color: ClockStyle.colSubtext
    }

    actions: [
        ClockSheetAction {
            visible: !(root.sound?.available ?? true)
            primary: true
            symbol: "download"
            label: SoundscapesService.downloading ? Translation.tr("Downloading…") : Translation.tr("Download the sounds")
            onClicked: SoundscapesService.download()
        },
        ClockSheetAction {
            visible: root.sound?.available ?? false
            primary: !root.on
            symbol: root.on ? "remove" : "add"
            label: root.on ? Translation.tr("Remove from the mix") : Translation.tr("Add to the mix")
            onClicked: SoundscapesService.toggle(root.soundId)
        }
    ]
}

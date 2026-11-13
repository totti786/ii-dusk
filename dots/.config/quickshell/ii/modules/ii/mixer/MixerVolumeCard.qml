pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.ii.clock.components

/**
 * One PipeWire node as a card: what it is, a volume slider that may go past 100 %, a mute
 * button and, for a device, the button that makes it the default.
 */
Rectangle {
    id: root

    required property PwNode node
    /// A sound card's speakers or microphone rather than an app's stream.
    property bool device: false
    property bool isDefault: false
    /// The loudest the slider goes, as a fraction of full volume.
    property real maxVolume: 1.5

    signal makeDefault()

    readonly property var audio: root.node?.audio ?? null
    readonly property bool muted: root.audio?.muted ?? false
    readonly property real volume: root.audio?.volume ?? 0
    readonly property bool isSink: root.node?.isSink ?? true
    readonly property string title: root.device ? Audio.friendlyDeviceName(root.node) : Audio.appNodeDisplayName(root.node)
    readonly property string subtitle: {
        if (root.device)
            return root.node?.description && root.node.description !== root.title ? root.node.description : "";
        return root.node?.properties["media.name"] ?? "";
    }
    readonly property string deviceSymbol: {
        const text = `${root.node?.description ?? ""} ${root.node?.nickname ?? ""}`.toLowerCase();
        if (root.node?.properties["device.api"] === "bluez5")
            return "bluetooth_audio";
        if (/head(phone|set)/.test(text))
            return "headphones";
        if (/hdmi|displayport|\bdp\b/.test(text))
            return "tv";
        return root.isSink ? "speaker" : "mic";
    }
    readonly property string appIcon: {
        const _ = TaskbarApps.iconThemeRevision;
        let icon = AppSearch.guessIcon(root.node?.properties["application.icon-name"] ?? "");
        if (AppSearch.iconExists(icon))
            return Quickshell.iconPath(icon, "");
        icon = AppSearch.guessIcon(root.node?.properties["application.name"] ?? root.node?.properties["node.name"] ?? "");
        return AppSearch.iconExists(icon) ? Quickshell.iconPath(icon, "") : "";
    }

    Layout.fillWidth: true
    implicitHeight: row.implicitHeight + ClockStyle.gap * 2
    radius: ClockStyle.radiusLarge
    color: root.isDefault ? ClockStyle.colActiveCard : ClockStyle.colSurfaceHigh
    opacity: root.muted ? 0.75 : 1

    Behavior on color { ColorAnimation { duration: Appearance.dur(200) } }
    Behavior on opacity { NumberAnimation { duration: Appearance.dur(150) } }

    PwObjectTracker {
        objects: [root.node]
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.margins: ClockStyle.gap
        spacing: ClockStyle.gap

        Rectangle {
            Layout.preferredWidth: 48
            Layout.preferredHeight: 48
            radius: root.device ? ClockStyle.radiusFull : ClockStyle.radiusNormal
            color: root.isDefault ? ClockStyle.colPrimary : ClockStyle.colSurfaceHigh

            Image {
                anchors.centerIn: parent
                width: 30
                height: 30
                visible: !root.device && root.appIcon !== ""
                source: root.appIcon
                sourceSize: Qt.size(60, 60)
                asynchronous: true
            }
            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.device || root.appIcon === ""
                text: root.device ? root.deviceSymbol : (root.isSink ? "music_note" : "mic")
                fill: root.isDefault ? 1 : 0
                iconSize: 26
                color: root.isDefault ? ClockStyle.colOnPrimary : ClockStyle.colOnSurfaceVariant
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                spacing: ClockStyle.gapSmall

                StyledText {
                    Layout.fillWidth: true
                    text: root.title
                    color: root.isDefault ? ClockStyle.colOnActiveCard : ClockStyle.colOnBackground
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                }
                StyledText {
                    text: `${Math.round(root.volume * 100)}%`
                    color: root.volume > 1 ? ClockStyle.colTertiary : (root.isDefault ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext)
                    font.family: ClockStyle.fontNumbers
                    font.pixelSize: ClockStyle.textSmall
                }
            }
            StyledText {
                Layout.fillWidth: true
                visible: text.length > 0
                text: root.subtitle
                color: root.isDefault ? ClockStyle.colOnActiveCard : ClockStyle.colSubtext
                font.pixelSize: ClockStyle.textSmall
                elide: Text.ElideRight
            }
            StyledSlider {
                Layout.fillWidth: true
                from: 0
                to: root.maxVolume
                value: root.volume
                dividerValues: [1]
                stopIndicatorValues: []
                configuration: StyledSlider.Configuration.S
                tooltipContent: `${Math.round(value * 100)}%`
                enabled: root.audio !== null
                onMoved: if (root.audio) root.audio.volume = value
            }
        }

        ClockIconButton {
            symbol: root.muted ? (root.isSink ? "volume_off" : "mic_off") : (root.isSink ? "volume_up" : "mic")
            toggled: root.muted
            tooltip: root.muted ? Translation.tr("Unmute") : Translation.tr("Mute")
            enabled: root.audio !== null
            onClicked: if (root.audio) root.audio.muted = !root.audio.muted
        }

        ClockIconButton {
            visible: root.device
            symbol: root.isDefault ? "check_circle" : "radio_button_unchecked"
            filled: root.isDefault
            tooltip: root.isDefault ? Translation.tr("Default device") : Translation.tr("Make default")
            enabled: !root.isDefault
            onClicked: root.makeDefault()
        }
    }
}

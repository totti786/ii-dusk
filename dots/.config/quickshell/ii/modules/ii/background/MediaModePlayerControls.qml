pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import "MediaModePlayerActions.js" as Actions

// The same player actions serve the classic popup and immersive options sheet.
ColumnLayout {
    id: root
    required property var player
    property bool localSource: false
    property color foreground: Appearance.colors.colOnLayer0
    readonly property bool controllable: player?.canControl ?? false
    readonly property bool volumeAvailable: controllable && (player?.volumeSupported ?? false)
    readonly property real minimumRate: localSource ? 0.25 : (player?.minRate ?? 1)
    readonly property real maximumRate: localSource ? 2 : (player?.maxRate ?? 1)
    readonly property bool rateAvailable: controllable && minimumRate > 0 && maximumRate > minimumRate
    property real unmutedVolume: 0.8
    property bool confirmQuit: false
    spacing: 10
    onPlayerChanged: {
        confirmQuit = false;
        unmutedVolume = player?.volume > 0 ? player.volume : 0.8;
        uriInput.text = "";
    }

    function seekBy(offset) {
        if (!root.controllable || !(root.player?.canSeek ?? false)) return;
        const length = root.localSource ? (root.player.length ?? 0) : MprisController.trackLengthOf(root.player);
        const current = root.localSource ? root.player.position : MprisController.trackPositionOf(root.player);
        const target = Actions.seekTarget(current, length, offset);
        if (root.localSource) root.player.position = target;
        else if (length > 0) MprisController.seekFraction(root.player, target / length);
        else root.player.seek(target - current);
    }
    function setRate(value) {
        const target = Actions.rateTarget(root.minimumRate, root.maximumRate, value);
        if (root.rateAvailable && target !== null) root.player.rate = target;
    }
    function toggleMute() {
        if (!root.volumeAvailable) return;
        if (root.player.volume > 0) {
            root.unmutedVolume = root.player.volume;
            root.player.volume = 0;
        } else root.player.volume = root.unmutedVolume;
    }

    component Action: RippleButton {
        id: action
        required property string symbol
        required property string label
        implicitHeight: 40
        implicitWidth: actionRow.implicitWidth + 24
        buttonRadius: Appearance.rounding.full
        colBackground: ColorUtils.applyAlpha(root.foreground, 0.08)
        colBackgroundHover: ColorUtils.applyAlpha(root.foreground, 0.14)
        colBackgroundActive: ColorUtils.applyAlpha(root.foreground, 0.2)
        Accessible.name: label
        opacity: enabled ? 1 : 0.38
        RowLayout {
            id: actionRow
            anchors.centerIn: parent
            spacing: 6
            MaterialSymbol { text: action.symbol; iconSize: 20; color: root.foreground }
            StyledText { text: action.label; color: root.foreground; font.pixelSize: Appearance.font.pixelSize.small }
        }
        PopupToolTip { text: action.label }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        Action {
            symbol: "replay_10"; label: Translation.tr("Back 10 s")
            enabled: root.controllable && (root.player?.canSeek ?? false)
            onClicked: root.seekBy(-10)
        }
        Action {
            symbol: "forward_10"; label: Translation.tr("Forward 10 s")
            enabled: root.controllable && (root.player?.canSeek ?? false)
            onClicked: root.seekBy(10)
        }
        Action {
            symbol: "stop"; label: Translation.tr("Stop")
            enabled: root.controllable
            onClicked: {
                if (root.localSource) LocalMediaService.stop();
                else root.player.stop();
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.volumeAvailable
        MediaModeImmersiveButton {
            symbol: (root.player?.volume ?? 0) > 0 ? "volume_up" : "volume_off"
            tooltip: (root.player?.volume ?? 0) > 0 ? Translation.tr("Mute player") : Translation.tr("Unmute player")
            foreground: root.foreground
            onClicked: root.toggleMute()
        }
        StyledSlider {
            Layout.fillWidth: true
            from: 0; to: 1
            value: root.player?.volume ?? 0
            onMoved: if (root.volumeAvailable) root.player.volume = value
            Accessible.name: Translation.tr("Player volume")
            highlightColor: root.foreground
            handleColor: root.foreground
            trackColor: ColorUtils.applyAlpha(root.foreground, 0.2)
        }
        StyledText {
            text: Math.round((root.player?.volume ?? 0) * 100) + "%"
            color: root.foreground
            Layout.minimumWidth: 40
            horizontalAlignment: Text.AlignRight
            font.pixelSize: Appearance.font.pixelSize.small
        }
    }

    RowLayout {
        Layout.fillWidth: true
        visible: root.rateAvailable
        StyledText { text: Translation.tr("Speed"); color: root.foreground; Layout.fillWidth: true }
        MediaModeImmersiveButton {
            symbol: "remove"; tooltip: Translation.tr("Slower"); foreground: root.foreground
            enabled: (root.player?.rate ?? 1) > root.minimumRate
            onClicked: root.setRate((root.player.rate ?? 1) - 0.25)
        }
        Action {
            symbol: "speed"; label: Number(root.player?.rate ?? 1).toFixed(2).replace(/0+$/, "").replace(/\.$/, "") + "×"
            enabled: root.minimumRate <= 1 && root.maximumRate >= 1
            Accessible.name: Translation.tr("Reset playback speed")
            onClicked: root.setRate(1)
        }
        MediaModeImmersiveButton {
            symbol: "add"; tooltip: Translation.tr("Faster"); foreground: root.foreground
            enabled: (root.player?.rate ?? 1) < root.maximumRate
            onClicked: root.setRate((root.player.rate ?? 1) + 0.25)
        }
    }

    Flow {
        Layout.fillWidth: true
        spacing: 6
        visible: !root.localSource
        Action {
            visible: root.player?.canRaise ?? false
            symbol: "open_in_new"; label: Translation.tr("Show player")
            onClicked: root.player.raise()
        }
        Action {
            visible: root.player?.canSetFullscreen ?? false
            symbol: (root.player?.fullscreen ?? false) ? "fullscreen_exit" : "fullscreen"
            label: (root.player?.fullscreen ?? false) ? Translation.tr("Leave fullscreen") : Translation.tr("Fullscreen")
            onClicked: root.player.fullscreen = !root.player.fullscreen
        }
        Action {
            visible: root.player?.canQuit ?? false
            symbol: "power_settings_new"
            label: root.confirmQuit ? Translation.tr("Confirm quit") : Translation.tr("Quit player")
            onClicked: {
                if (root.confirmQuit) { root.player.quit(); root.confirmQuit = false; }
                else { root.confirmQuit = true; quitTimer.restart(); }
            }
        }
    }
    Timer { id: quitTimer; interval: 4000; onTriggered: root.confirmQuit = false }

    RowLayout {
        Layout.fillWidth: true
        visible: !root.localSource && (root.player?.supportedUriSchemes?.length ?? 0) > 0
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 42
            radius: Appearance.rounding.small
            color: ColorUtils.applyAlpha(root.foreground, 0.08)
            StyledTextInput {
                id: uriInput
                anchors.fill: parent
                anchors.margins: 10
                color: root.foreground
                clip: true
                selectByMouse: true
                Accessible.name: Translation.tr("Media URI")
                StyledText {
                    visible: uriInput.text.length === 0
                    text: Translation.tr("Media URI…")
                    color: ColorUtils.applyAlpha(root.foreground, 0.6)
                    font: uriInput.font
                }
                onAccepted: if (openUri.enabled) openUri.clicked()
            }
        }
        MediaModeImmersiveButton {
            id: openUri
            symbol: "link"; tooltip: Translation.tr("Open media URI"); foreground: root.foreground
            enabled: root.controllable && Actions.uriAllowed(uriInput.text, root.player?.supportedUriSchemes ?? [])
            onClicked: { root.player.openUri(uriInput.text.trim()); uriInput.text = ""; }
        }
    }
}

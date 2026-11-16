pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common

/**
 * Every source the island has, in one place.
 *
 * The controller stays generic: it asks this object for the source of an activity id and
 * never knows what a clipboard or a workspace is. Adding an activity is a descriptor in
 * IslandRegistry, a source here, and a presentation - no edits to the arbitration.
 *
 * The clock has no source: there is no event that makes a clock happen, it is simply
 * what the centre shows when nothing else needs it. The controller synthesises it.
 */
Item {
    id: sources

    visible: false

    readonly property list<QtObject> all: ([
        // Interrupts first, only because it reads in priority order here; the actual
        // arbitration is IslandRegistry's tier, not this list.
        windowSwitcher, askpass, search, wallpaper, session, colorPicker, displayModes, notification, osd, phoneCall, alarm, reminder, fingerprint,
        // Live and ambient.
        ai, media, mediator, timer, focusSession, recording, audioRecording, dictation, localSend, shelf, progress, songRec, teleprompter,
        // Side glances.
        earbuds, btPhone, weather, batteryGlance, reminderSoon, prayer, privacy, discordVoice, phoneMirror, phoneLink, sports, phoneLive,
        // Announcements.
        health, phoneMirrorError, phoneKeyboard, workspaces, clipboard, battery, wifi, bluetooth, keyboard, mode, update, vpn, systemTray,
        easyEffects, soundscapes, quickShare, monitorAlert
    ]).filter(source => source !== null)

    readonly property WindowSwitcherSource windowSwitcher: WindowSwitcherSource {}
    readonly property AskpassSource askpass: AskpassSource {}
    readonly property SearchSource search: SearchSource {}
    readonly property WallpaperSource wallpaper: WallpaperSource {}
    readonly property SessionSource session: SessionSource {}
    readonly property ColorPickerSource colorPicker: ColorPickerSource {}
    readonly property DisplayModesSource displayModes: DisplayModesSource {}
    readonly property NotificationSource notification: NotificationSource {}
    readonly property OsdSource osd: OsdSource {}
    readonly property PhoneCallSource phoneCall: PhoneCallSource {}
    readonly property FingerprintSource fingerprint: FingerprintSource {}
    readonly property AlarmSource alarm: AlarmSource {}
    readonly property ReminderSource reminder: ReminderSource {}
    readonly property ReminderSoonSource reminderSoon: ReminderSoonSource {}
    readonly property var prayer: optional.item ? optional.item.prayer : null
    readonly property var songRec: optional.item ? optional.item.songRec : null
    readonly property var sports: optional.item ? optional.item.sports : null
    readonly property var phoneLive: optional.item ? optional.item.phoneLive : null
    readonly property var vpn: optional.item ? optional.item.vpn : null
    readonly property var ai: optional.item ? optional.item.ai : null
    readonly property MediaSource media: MediaSource {}
    readonly property var mediator: optional.item ? optional.item.mediator : null
    readonly property TimerSource timer: TimerSource {}
    readonly property var focusSession: optional.item ? optional.item.focusSession : null
    readonly property RecordingSource recording: RecordingSource {}
    readonly property AudioRecordingSource audioRecording: AudioRecordingSource {}
    readonly property TeleprompterSource teleprompter: TeleprompterSource {}
    readonly property DictationSource dictation: DictationSource {}
    readonly property LocalSendSource localSend: LocalSendSource {}
    readonly property var shelf: optional.item ? optional.item.shelf : null
    readonly property ProgressSource progress: ProgressSource {}
    readonly property var earbuds: optional.item ? optional.item.earbuds : null
    readonly property var btPhone: optional.item ? optional.item.btPhone : null
    readonly property var weather: optional.item ? optional.item.weather : null
    readonly property var batteryGlance: optional.item ? optional.item.batteryGlance : null
    readonly property PrivacySource privacy: PrivacySource {}
    readonly property var discordVoice: optional.item ? optional.item.discordVoice : null
    readonly property var phoneMirror: optional.item ? optional.item.phoneMirror : null
    readonly property var phoneMirrorError: optional.item ? optional.item.phoneMirrorError : null
    readonly property var phoneKeyboard: optional.item ? optional.item.phoneKeyboard : null
    readonly property var phoneLink: optional.item ? optional.item.phoneLink : null
    readonly property WorkspaceSource workspaces: WorkspaceSource {}
    readonly property ClipboardSource clipboard: ClipboardSource {}
    readonly property BatterySource battery: BatterySource {}
    readonly property WifiSource wifi: WifiSource {}
    readonly property BluetoothSource bluetooth: BluetoothSource {}
    readonly property KeyboardLayoutSource keyboard: KeyboardLayoutSource {}
    readonly property var mode: optional.item ? optional.item.mode : null
    readonly property var update: optional.item ? optional.item.update : null
    readonly property SystemTraySource systemTray: SystemTraySource {}
    readonly property var easyEffects: optional.item ? optional.item.easyEffects : null
    readonly property var soundscapes: optional.item ? optional.item.soundscapes : null
    readonly property var quickShare: optional.item ? optional.item.quickShare : null
    readonly property var health: optional.item ? optional.item.health : null
    readonly property var monitorAlert: optional.item ? optional.item.monitorAlert : null

    // The clock, media and interrupt sources draw the island's first frame.
    // Optional integrations attach afterward without replacing the surface.
    Loader {
        id: optional
        active: StartupState.desktopReady
        source: active ? Qt.resolvedUrl("DeferredIslandSources.qml") : ""
        onLoaded: console.info("[Startup] Optional island sources attached; total:", sources.all.length)
    }

    function sourceFor(activityId) {
        for (let i = 0; i < sources.all.length; i++) {
            if (sources.all[i].activityId === activityId)
                return sources.all[i];
        }
        return null;
    }

    /** Tell every source whether the pointer is on its activity, to hold TTLs open. */
    function setHovered(activityId, hovered) {
        const source = sources.sourceFor(activityId);
        if (source)
            source.hovered = hovered;
    }
}

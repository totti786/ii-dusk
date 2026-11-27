pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.common
import qs.modules.ii.dynamicIsland.core

/**
 * Every source the island has, in one place.
 *
 * The controller stays generic: it asks this object for the source of an activity id and
 * never knows what a clipboard or a workspace is. Adding an activity is a descriptor in
 * IslandRegistry, a source here, and a presentation - no edits to the arbitration.
 *
 * Core / explicit-surface sources stay eager; optional activity sources load via URL
 * only while enabled in `IslandPolicy.widgetEnabled(...)`, avoiding compiling unused
 * sources and waking their `qs.services` singletons at boot. Optional integrations
 * marked `deferred` also wait for the desktop's first frame.
 */
Item {
    id: sources

    visible: false

    // Helper for optional sources loaded by URL only when enabled in IslandPolicy.
    component OptionalSourceLoader: Loader {
        required property string policyId
        required property string fileName
        property bool deferred: false
        active: (!deferred || StartupState.desktopReady) && IslandPolicy.widgetEnabled(policyId)
        source: active ? Qt.resolvedUrl(fileName) : ""
    }

    // ── Core / explicit surfaces (always active) ──────────────────────────────
    readonly property WindowSwitcherSource windowSwitcher: WindowSwitcherSource {}
    readonly property AskpassSource askpass: AskpassSource {}
    readonly property SearchSource search: SearchSource {}
    readonly property WallpaperSource wallpaper: WallpaperSource {}
    readonly property SessionSource session: SessionSource {}
    readonly property ColorPickerSource colorPicker: ColorPickerSource {}
    readonly property DisplayModesSource displayModes: DisplayModesSource {}
    readonly property NotificationSource notification: NotificationSource {}
    readonly property OsdSource osd: OsdSource {}
    readonly property LocalSendSource localSend: LocalSendSource {}
    readonly property WifiSource wifi: WifiSource {}
    readonly property TeleprompterSource teleprompter: TeleprompterSource {}

    // ── Optional activity sources (URL-loaded only while enabled) ─────────────
    OptionalSourceLoader { id: phoneCallLoader; policyId: "phoneCall"; fileName: "PhoneCallSource.qml" }
    OptionalSourceLoader { id: fingerprintLoader; policyId: "fingerprint"; fileName: "FingerprintSource.qml" }
    OptionalSourceLoader { id: alarmLoader; policyId: "alarm"; fileName: "AlarmSource.qml" }
    OptionalSourceLoader { id: reminderLoader; policyId: "reminder"; fileName: "ReminderSource.qml" }
    OptionalSourceLoader { id: reminderSoonLoader; policyId: "reminderSoon"; fileName: "ReminderSoonSource.qml" }
    OptionalSourceLoader { id: prayerLoader; policyId: "prayer"; fileName: "PrayerSource.qml"; deferred: true }
    OptionalSourceLoader { id: songRecLoader; policyId: "songRec"; fileName: "SongRecSource.qml"; deferred: true }
    OptionalSourceLoader { id: sportsLoader; policyId: "sports"; fileName: "SportsSource.qml"; deferred: true }
    OptionalSourceLoader { id: phoneLiveLoader; policyId: "phoneLive"; fileName: "PhoneLiveSource.qml"; deferred: true }
    OptionalSourceLoader { id: vpnLoader; policyId: "vpn"; fileName: "VpnSource.qml"; deferred: true }
    OptionalSourceLoader { id: aiLoader; policyId: "ai"; fileName: "AiSource.qml"; deferred: true }
    OptionalSourceLoader { id: companionLoader; policyId: "companion"; fileName: "CompanionSource.qml" }
    OptionalSourceLoader { id: mediaLoader; policyId: "media"; fileName: "MediaSource.qml" }
    OptionalSourceLoader { id: mediatorLoader; policyId: "mediator"; fileName: "MediatorSource.qml"; deferred: true }
    OptionalSourceLoader { id: timerLoader; policyId: "timer"; fileName: "TimerSource.qml" }
    OptionalSourceLoader { id: focusSessionLoader; policyId: "focus"; fileName: "FocusSource.qml"; deferred: true }
    OptionalSourceLoader { id: recordingLoader; policyId: "recording"; fileName: "RecordingSource.qml" }
    OptionalSourceLoader { id: audioRecordingLoader; policyId: "audioRecording"; fileName: "AudioRecordingSource.qml" }
    OptionalSourceLoader { id: dictationLoader; policyId: "dictation"; fileName: "DictationSource.qml" }
    OptionalSourceLoader { id: shelfLoader; policyId: "shelf"; fileName: "ShelfSource.qml"; deferred: true }
    OptionalSourceLoader { id: progressLoader; policyId: "progress"; fileName: "ProgressSource.qml" }
    OptionalSourceLoader { id: earbudsLoader; policyId: "earbuds"; fileName: "EarbudsSource.qml"; deferred: true }
    OptionalSourceLoader { id: btPhoneLoader; policyId: "bluetooth"; fileName: "BluetoothPhoneSource.qml"; deferred: true }
    OptionalSourceLoader { id: weatherLoader; policyId: "weather"; fileName: "WeatherSource.qml"; deferred: true }
    OptionalSourceLoader { id: batteryGlanceLoader; policyId: "batteryGlance"; fileName: "BatteryGlanceSource.qml"; deferred: true }
    OptionalSourceLoader { id: dateGlanceLoader; policyId: "date"; fileName: "DateGlanceSource.qml"; deferred: true }
    OptionalSourceLoader { id: privacyLoader; policyId: "privacy"; fileName: "PrivacySource.qml" }
    OptionalSourceLoader { id: discordVoiceLoader; policyId: "discordVoice"; fileName: "DiscordVoiceSource.qml"; deferred: true }
    OptionalSourceLoader { id: phoneMirrorLoader; policyId: "phoneMirror"; fileName: "PhoneMirrorSource.qml"; deferred: true }
    OptionalSourceLoader { id: phoneMirrorErrorLoader; policyId: "phoneMirrorError"; fileName: "PhoneMirrorErrorSource.qml"; deferred: true }
    OptionalSourceLoader { id: phoneKeyboardLoader; policyId: "phoneKeyboard"; fileName: "PhoneKeyboardSource.qml"; deferred: true }
    OptionalSourceLoader { id: phoneLinkLoader; policyId: "phoneLink"; fileName: "PhoneLinkSource.qml"; deferred: true }
    OptionalSourceLoader { id: workspacesLoader; policyId: "workspaces"; fileName: "WorkspaceSource.qml" }
    OptionalSourceLoader { id: clipboardLoader; policyId: "clipboard"; fileName: "ClipboardSource.qml" }
    OptionalSourceLoader { id: batteryLoader; policyId: "battery"; fileName: "BatterySource.qml" }
    OptionalSourceLoader { id: bluetoothLoader; policyId: "bluetooth"; fileName: "BluetoothSource.qml" }
    OptionalSourceLoader { id: keyboardLoader; policyId: "keyboard"; fileName: "KeyboardLayoutSource.qml" }
    OptionalSourceLoader { id: modeLoader; policyId: "mode"; fileName: "ModeSource.qml"; deferred: true }
    OptionalSourceLoader { id: updateLoader; policyId: "update"; fileName: "UpdateSource.qml"; deferred: true }
    OptionalSourceLoader { id: systemTrayLoader; policyId: "systemTray"; fileName: "SystemTraySource.qml" }
    OptionalSourceLoader { id: easyEffectsLoader; policyId: "easyEffects"; fileName: "EasyEffectsSource.qml"; deferred: true }
    OptionalSourceLoader { id: soundscapesLoader; policyId: "soundscapes"; fileName: "SoundscapesSource.qml"; deferred: true }
    OptionalSourceLoader { id: quickShareLoader; policyId: "quickShare"; fileName: "QuickShareSource.qml"; deferred: true }
    OptionalSourceLoader { id: healthLoader; policyId: "health"; fileName: "HealthSource.qml"; deferred: true }
    OptionalSourceLoader { id: monitorAlertLoader; policyId: "monitorAlert"; fileName: "MonitorAlertSource.qml"; deferred: true }

    readonly property var phoneCall: phoneCallLoader.item
    readonly property var fingerprint: fingerprintLoader.item
    readonly property var alarm: alarmLoader.item
    readonly property var reminder: reminderLoader.item
    readonly property var reminderSoon: reminderSoonLoader.item
    readonly property var prayer: prayerLoader.item
    readonly property var songRec: songRecLoader.item
    readonly property var sports: sportsLoader.item
    readonly property var phoneLive: phoneLiveLoader.item
    readonly property var vpn: vpnLoader.item
    readonly property var ai: aiLoader.item
    readonly property var companion: companionLoader.item
    readonly property var media: mediaLoader.item
    readonly property var mediator: mediatorLoader.item
    readonly property var timer: timerLoader.item
    readonly property var focusSession: focusSessionLoader.item
    readonly property var recording: recordingLoader.item
    readonly property var audioRecording: audioRecordingLoader.item
    readonly property var dictation: dictationLoader.item
    readonly property var shelf: shelfLoader.item
    readonly property var progress: progressLoader.item
    readonly property var earbuds: earbudsLoader.item
    readonly property var btPhone: btPhoneLoader.item
    readonly property var weather: weatherLoader.item
    readonly property var batteryGlance: batteryGlanceLoader.item
    readonly property var dateGlance: dateGlanceLoader.item
    readonly property var privacy: privacyLoader.item
    readonly property var discordVoice: discordVoiceLoader.item
    readonly property var phoneMirror: phoneMirrorLoader.item
    readonly property var phoneMirrorError: phoneMirrorErrorLoader.item
    readonly property var phoneKeyboard: phoneKeyboardLoader.item
    readonly property var phoneLink: phoneLinkLoader.item
    readonly property var workspaces: workspacesLoader.item
    readonly property var clipboard: clipboardLoader.item
    readonly property var battery: batteryLoader.item
    readonly property var bluetooth: bluetoothLoader.item
    readonly property var keyboard: keyboardLoader.item
    readonly property var mode: modeLoader.item
    readonly property var update: updateLoader.item
    readonly property var systemTray: systemTrayLoader.item
    readonly property var easyEffects: easyEffectsLoader.item
    readonly property var soundscapes: soundscapesLoader.item
    readonly property var quickShare: quickShareLoader.item
    readonly property var health: healthLoader.item
    readonly property var monitorAlert: monitorAlertLoader.item

    readonly property var all: [
        // Interrupts first, only because it reads in priority order here; the actual
        // arbitration is IslandRegistry's tier, not this list.
        windowSwitcher, askpass, search, wallpaper, session, colorPicker, displayModes, notification, osd, phoneCall, alarm, reminder, fingerprint,
        // Live and ambient.
        ai, companion, media, mediator, timer, focusSession, recording, audioRecording, dictation, localSend, shelf, progress, songRec, teleprompter,
        // Side glances.
        earbuds, btPhone, weather, batteryGlance, dateGlance, reminderSoon, prayer, privacy, discordVoice, phoneMirror, phoneLink, sports, phoneLive,
        // Announcements.
        health, phoneMirrorError, phoneKeyboard, workspaces, clipboard, battery, wifi, bluetooth, keyboard, mode, update, vpn, systemTray,
        easyEffects, soundscapes, quickShare, monitorAlert
    ].filter(s => s !== null)

    function sourceFor(activityId) {
        const list = sources.all;
        for (let i = 0; i < list.length; i++) {
            if (list[i] && list[i].activityId === activityId)
                return list[i];
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

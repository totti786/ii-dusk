pragma ComponentBehavior: Bound
import QtQuick

Item {
    visible: false
    readonly property PrayerSource prayer: PrayerSource {}
    readonly property SongRecSource songRec: SongRecSource {}
    readonly property SportsSource sports: SportsSource {}
    readonly property PhoneLiveSource phoneLive: PhoneLiveSource {}
    readonly property VpnSource vpn: VpnSource {}
    readonly property AiSource ai: AiSource {}
    readonly property MediatorSource mediator: MediatorSource {}
    readonly property FocusSource focusSession: FocusSource {}
    readonly property ShelfSource shelf: ShelfSource {}
    readonly property EarbudsSource earbuds: EarbudsSource {}
    readonly property BluetoothPhoneSource btPhone: BluetoothPhoneSource {}
    readonly property WeatherSource weather: WeatherSource {}
    readonly property BatteryGlanceSource batteryGlance: BatteryGlanceSource {}
    readonly property DiscordVoiceSource discordVoice: DiscordVoiceSource {}
    readonly property PhoneMirrorSource phoneMirror: PhoneMirrorSource {}
    readonly property PhoneMirrorErrorSource phoneMirrorError: PhoneMirrorErrorSource {}
    readonly property PhoneKeyboardSource phoneKeyboard: PhoneKeyboardSource {}
    readonly property PhoneLinkSource phoneLink: PhoneLinkSource {}
    readonly property ModeSource mode: ModeSource {}
    readonly property UpdateSource update: UpdateSource {}
    readonly property EasyEffectsSource easyEffects: EasyEffectsSource {}
    readonly property SoundscapesSource soundscapes: SoundscapesSource {}
    readonly property QuickShareSource quickShare: QuickShareSource {}
    readonly property HealthSource health: HealthSource {}
    readonly property MonitorAlertSource monitorAlert: MonitorAlertSource {}
}

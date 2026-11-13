import QtQuick
import Quickshell
import qs
import qs.services

// Panels load by URL (PanelUrlLoader); these imports are how the QmlScanner reaches each
// panel's module, so keep one for every panel listed below.
import qs.modules.common
import qs.modules.common.panels.shellSwitcher
import qs.modules.common.panels.windowSwitcher
import qs.modules.lite
import qs.modules.ii.alarmRingingPopup
import qs.modules.ii.discordoVoice
import qs.modules.ii.bluetoothPairing
import qs.modules.ii.calculator
import qs.modules.ii.anki
import qs.modules.ii.books
import qs.modules.ii.camera
import qs.modules.ii.imageViewer
import qs.modules.ii.audioPlayer
import qs.modules.ii.soundscapes
import qs.modules.ii.fileManager
import qs.modules.ii.textEditor
import qs.modules.ii.cheatsheet
import qs.modules.ii.clock
import qs.modules.ii.downloads
import qs.modules.ii.mixer
import qs.modules.ii.torrents
import qs.modules.ii.packages
import qs.modules.ii.bluetoothManager
import qs.modules.ii.patchbay
import qs.modules.ii.lock
import qs.modules.ii.mediator
import qs.modules.ii.quran
import qs.modules.ii.diwan
import qs.modules.ii.modes
import qs.modules.ii.easyEffects
import qs.modules.ii.usage
import qs.modules.ii.health
import qs.modules.ii.colorPickerPopup
import qs.modules.ii.displayModesPopup
import qs.modules.ii.wallpaperSelector
import qs.modules.ii.monitor
import qs.modules.ii.music
import qs.modules.ii.notes
import qs.modules.ii.notificationPopup
import qs.modules.ii.onScreenDisplay.minimalist
import qs.modules.ii.polkit
import qs.modules.ii.regionSelector
import qs.modules.ii.reminderAlertPopup
import qs.modules.ii.screenshotOverlay
import qs.modules.ii.sessionScreen

/**
 * Lite: the panel family for low-powered machines.
 *
 * What it leaves out is most of what the desktop family keeps resident: the background
 * widgets and parallax, the dock, the dynamic island, both sidebars, the overview with its
 * live window thumbnails, the overlays, the game HUD, tiling hints, touch gestures and
 * edit mode. What it keeps is what a desktop cannot do without: a bar, a wallpaper, a
 * launcher, a quick settings panel, notifications, volume and brightness feedback, the lock screen, the session
 * menu, authentication prompts, screenshots, and the small apps (each of those builds its
 * window only while open).
 *
 * The bar, wallpaper, launcher and quick settings are written for it (modules/lite) as plain items, so they
 * do not pull the desktop bar's widget registry, layout engine and animation set into memory.
 */
Scope {
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/lite/LiteBar.qml")
        priority: 4 // First paint (see PanelSchedule)
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/lite/LiteWallpaper.qml")
        priority: 3
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/lite/LiteLauncher.qml")
    }

    // Always on: switches the power profile to saver on a low battery (see LitePowerManager)
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/lite/LitePowerManager.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/lite/LiteQuickSettings.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/lite/LiteNotificationShade.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/notificationPopup/NotificationPopup.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/onScreenDisplay/minimalist/MinimalistOsd.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/lock/Lock.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/sessionScreen/SessionScreen.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/polkit/Polkit.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/bluetoothPairing/BluetoothPairing.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/regionSelector/RegionSelector.qml")
    }

    PanelUrlLoader {
        extraCondition: GlobalStates.screenshotOverlayOpen
        panelUrl: Qt.resolvedUrl("../modules/ii/screenshotOverlay/ScreenshotOverlay.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/cheatsheet/Cheatsheet.qml")
    }

    // The chooser is loaded by every family on purpose, so the way back always exists.
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/panels/shellSwitcher/ShellSwitcher.qml")
    }

    // Alt+Tab; always loaded so its binds can be taken away when the setting goes off.
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/panels/windowSwitcher/WindowSwitcherPanel.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/common/panels/windowSwitcher/WindowSwitcherPeek.qml")
    }

    // What Lite leaves out until asked for: the Lite page in Settings switches each one on. They are
    // the same panels the desktop family runs, loaded only while their switch is on.
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.modes
        panelUrl: Qt.resolvedUrl("../modules/ii/modes/ModesApp.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.easyEffects
        panelUrl: Qt.resolvedUrl("../modules/ii/easyEffects/EasyEffectsApp.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.usage
        panelUrl: Qt.resolvedUrl("../modules/ii/usage/UsageApp.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.health
        panelUrl: Qt.resolvedUrl("../modules/ii/health/HealthApp.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.colorPicker
        panelUrl: Qt.resolvedUrl("../modules/ii/colorPickerPopup/ColorPickerPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.displayModes
        panelUrl: Qt.resolvedUrl("../modules/ii/displayModesPopup/DisplayModesPopup.qml")
    }
    PanelUrlLoader {
        extraCondition: Config.options.lite.extras.wallpaperSelector
        panelUrl: Qt.resolvedUrl("../modules/ii/wallpaperSelector/WallpaperSelector.qml")
    }

    // The small apps: each Scope holds its keybind and IPC target, and its window is built only while open.
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/quran/QuranApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/diwan/DiwanApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/calculator/CalculatorApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/anki/AnkiApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/books/BooksApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/audioRecorder/AudioRecorderApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/qanun/QanunApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/camera/CameraApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/imageViewer/ImageViewerApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/audioPlayer/AudioPlayerApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/fileManager/FileManagerApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/textEditor/EditorApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/wikipedia/WikipediaApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/youtubeApp/YouTubeApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/discordoVoice/DiscordoVoiceApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/quickShare/QuickShareApp.qml")
    }
    PanelUrlLoader {
        // Holds the shortcuts and IPC target; the window exists only while Syncplay is open.
        panelUrl: Qt.resolvedUrl("../modules/ii/syncplay/SyncplayApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/bar/popups/passwordManager/PasswordManagerOverlay.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/mediator/MediatorApp.qml")
    }

    PanelUrlLoader {
        extraCondition: Config.options.notes.enable
        panelUrl: Qt.resolvedUrl("../modules/ii/notes/NotesApp.qml")
    }

    PanelUrlLoader {
        extraCondition: Config.options.clockApp?.enable ?? true
        panelUrl: Qt.resolvedUrl("../modules/ii/clock/ClockApp.qml")
    }

    PanelUrlLoader {
        extraCondition: Config.options.weatherApp?.enable ?? true
        panelUrl: Qt.resolvedUrl("../modules/ii/weather/WeatherApp.qml")
    }

    PanelUrlLoader {
        extraCondition: Config.options.soundscapes?.enable ?? true
        panelUrl: Qt.resolvedUrl("../modules/ii/soundscapes/SoundscapesApp.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/downloads/DownloadsApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/mixer/MixerApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/torrents/TorrentsApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/packages/PackagesApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/bluetoothManager/BluetoothManagerApp.qml")
    }
    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/patchbay/PatchbayApp.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/music/MusicApp.qml")
    }

    PanelUrlLoader {
        panelUrl: Qt.resolvedUrl("../modules/ii/monitor/MonitorApp.qml")
    }

    PanelUrlLoader {
        extraCondition: AlarmService.ringingAlarmIndex !== -1 && Config.options.time.alarms.useFullscreenPopup
        panelUrl: Qt.resolvedUrl("../modules/ii/alarmRingingPopup/AlarmRingingPopup.qml")
    }

    PanelUrlLoader {
        extraCondition: RemindersService.ringingId.length > 0
        panelUrl: Qt.resolvedUrl("../modules/ii/reminderAlertPopup/ReminderAlertPopup.qml")
    }
}

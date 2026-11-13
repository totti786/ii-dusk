pragma Singleton

import QtQuick
import Quickshell
import qs
import qs.modules.common
import qs.services

// Compatibility-first facade. Touch gestures keep their public API while the
// Search consumes this shell-wide registry as its single action source.
Singleton {
    id: root
    function keywordsFor(action) {
        const base = [action.id, action.name.toLowerCase()];
        const extras = {
            usage: ["app usage", "usage", "uso", "stats", "statistics", "screen time", "tempo de tela", "daily limits",
                "app limits", "limites", "battery usage", "battery history", "bateria", "energy", "digital wellbeing"],
            modes: ["modes and routines", "modes & routines", "modes", "modos", "routines", "rotinas", "automation",
                "automacao", "automação", "focus mode", "work mode", "do not disturb"],
            colorPicker: ["color picker", "cor", "hex"], wallpaperSelector: ["wallpaper", "papel de parede"],
            overlay: ["overlay", "widgets"], osk: ["osk", "teclado"],
            session: ["session", "logout", "desligar"], regionOcr: ["ocr", "texto da tela"],
            screenTranslate: ["translate screen", "traduzir tela"], regionRecord: ["record", "gravar"],
            regionScreenshot: ["screenshot", "print", "snip"], localSend: ["localsend", "enviar arquivo"],
            videoEditor: ["video editor", "editar video"], notes: ["notes", "notas", "quick notes"], scratchpad: ["scratchpad"],
            clock: ["clock", "relogio", "relógio", "alarm", "alarme", "despertador", "world clock", "fuso", "timer", "temporizador", "stopwatch", "cronometro", "cronômetro", "pomodoro"],
            soundscapes: ["soundscapes", "ambient", "ambience", "noice", "white noise", "brown noise", "pink noise", "rain sounds", "nature sounds", "relax", "sleep", "focus sounds", "sleep timer", "mixer", "thunder", "campfire", "ocean", "forest", "calm"],
            weather: ["weather", "forecast", "temperature", "rain", "snow", "wind", "humidity", "air quality", "aqi", "pollen", "climate", "meteo", "clima", "tempo", "chuva", "neve", "vento", "umidade", "qualidade do ar", "pólen"],
            grit: ["grit", "habit", "habits", "habito", "hábito", "habitos", "hábitos", "habit tracker", "tasks", "tarefas", "todo", "focus", "foco", "pomodoro", "tomato", "streak", "ofensiva", "routine", "rotina"],
            qanun: ["qanun", "tuner", "metronome", "maqam", "maqams", "scale", "scales", "sheet music", "music sheet", "flashcards", "note reading", "music theory", "recorder", "tracks", "ear training", "interval", "chord", "قانون", "مقام", "مقامات", "موسيقى"],
            music: ["music", "player", "youtube music", "songs", "lyrics", "spotify", "musica", "música"],
            monitor: ["monitor", "system monitor", "btop", "htop", "top", "task manager", "processes", "cpu", "ram", "memory", "latency", "ping", "network", "internet", "monitor do sistema"],
            downloads: ["downloads", "download", "yt-dlp", "youtube", "youtube-dl", "video downloader", "music downloader", "baixar"],
            quran: ["quran", "qur'an", "koran", "mushaf", "recitation", "ayah", "surah", "juz", "tilawa", "قرآن", "القرآن", "مصحف", "تلاوة", "سورة", "آية"],
            diwan: ["diwan", "poetry", "poems", "poem", "arabic poetry", "qafiyah", "verse", "shi'r", "ديوان", "شعر", "قصيدة", "قصائد", "شعراء"],
            torrents: ["torrents", "torrent", "qbittorrent", "magnet", "download", "seed", "bittorrent", "p2p"],
            mixer: ["mixer", "sound", "volume", "volume mixer", "pavucontrol", "audio", "speakers", "microphone", "output", "input", "som", "volume"],
            packages: ["packages", "package manager", "software", "updates", "update", "upgrade", "pacman", "yay", "aur", "install", "uninstall", "apps", "store"],
            books: ["books", "library", "reader", "read", "pdf", "epub", "ebook", "e-book", "zathura", "sioyek", "novel", "كتب", "مكتبة"],
            editor: ["text editor", "editor", "notepad", "code", "edit file", "محرر"],
            fileManager: ["file manager", "files", "folders", "explorer", "thunar", "nautilus", "browse", "directory", "ملفات"],
            audioPlayer: ["audio player", "music player", "player", "songs", "local music", "mp3", "flac", "library", "tracks"],
            imageViewer: ["image viewer", "images", "photos", "pictures", "gallery", "viewer"],
            camera: ["camera", "webcam", "photo", "selfie", "cheese", "câmera"],
            audioRecorder: ["audio recorder", "recorder", "record", "microphone", "mic", "voice", "gravador", "áudio"],
            wikipedia: ["wikipedia", "wiki", "encyclopedia", "article", "search"],
            youtube: ["youtube", "video", "videos", "watch", "yt"],
            discordoVoice: ["discordo", "discordo voice", "voice", "voice channel", "call", "microphone", "headset", "audio"],
            stremio: ["stremio", "stream", "movies", "shows", "anime"],
            manga: ["manga", "mangadex", "comics", "reader"],
            mediator: ["mediator", "media", "watch", "anime", "shows", "movies", "series", "tv", "film", "episodes", "mpv", "jellyfin", "افلام", "مسلسلات"],
            anki: ["anki", "flashcards", "flash cards", "review", "study", "cards", "spaced repetition", "srs", "vocabulary", "vocab", "deutsch"],
            bluetoothManager: ["bluetooth", "pair", "pairing", "headphones", "earbuds", "airpods", "speaker", "keyboard", "mouse", "controller", "devices", "wireless"],
            patchbay: ["patchbay", "pipewire", "graph", "routing", "qpwgraph", "helvum", "connections", "jack", "midi", "audio routing"],
            quickshare: ["quick share", "quickshare", "nearby share", "send to phone", "android share", "airdrop"],
            syncplay: ["syncplay", "sync play", "watch together", "watch party", "together", "room", "shared playback", "movie night"],
            calculator: ["calculator", "calc", "calculadora", "calcular", "math", "matematica", "matemática"],
            easyEffects: ["easyeffects", "easy effects", "equalizer", "equalizador", "eq", "audio preset", "preset", "sound effects", "efeitos"],
            health: ["health", "system health", "smart", "disk", "temperature", "sensors", "battery health", "journal", "failed services"],
            mediaControls: ["media controls", "player"], barToggle: ["bar", "barra"],
            hubMode: ["hub mode", "dock", "display", "relogio", "clock", "ambient"],
            liveDraw: ["draw", "desenhar", "desenho", "sketch", "pen", "caneta", "stylus", "annotate", "anotar"]
        };
        return base.concat(extras[action.id] ?? []);
    }

    readonly property var extraActions: [
        { id: "notes", name: "Notes", icon: "note_stack", category: "shell", searchable: true, enabled: () => true },
        { id: "clock", name: "Clock", icon: "alarm", category: "shell", searchable: true, enabled: () => Config.options.clockApp?.enable ?? true },
        { id: "grit", name: "Grit", icon: "local_fire_department", category: "shell", searchable: true, enabled: () => true },
        { id: "weather", name: "Weather", icon: "cloud", category: "shell", searchable: true, enabled: () => Config.options.weatherApp?.enable ?? true },
        { id: "soundscapes", name: "Soundscapes", icon: "waves", category: "shell", searchable: true, enabled: () => Config.options.soundscapes?.enable ?? true },
        { id: "qanun", name: "Qanun", icon: "music_note", category: "shell", searchable: true, enabled: () => true },
        { id: "calculator", name: "Calculator", icon: "calculate", category: "shell", searchable: true, enabled: () => true },
        { id: "quickshare", name: "Quick Share", icon: "send_to_mobile", category: "shell", searchable: true, enabled: () => true },
        { id: "syncplay", name: "Syncplay", icon: "group", category: "shell", searchable: true, enabled: () => true },
        { id: "easyEffects", name: "EasyEffects", icon: "graphic_eq", category: "shell", searchable: true, enabled: () => Config.options.easyEffects?.appEnable ?? true },
        { id: "music", name: "Music", icon: "library_music", category: "shell", searchable: true, enabled: () => true },
        { id: "monitor", name: "Monitor", icon: "monitoring", category: "shell", searchable: true, enabled: () => true },
        { id: "downloads", name: "Downloads", icon: "download", category: "shell", searchable: true, enabled: () => true },
        { id: "packages", name: "Packages", icon: "package_2", category: "shell", searchable: true, enabled: () => true },
        { id: "anki", name: "Anki Review", icon: "style", category: "shell", searchable: true, enabled: () => true },
        { id: "mediator", name: "Mediator", icon: "movie", category: "shell", searchable: true, enabled: () => true },
        { id: "books", name: "Books", icon: "menu_book", category: "shell", searchable: true, enabled: () => true },
        { id: "fileManager", name: "Files", icon: "folder", category: "shell", searchable: true, enabled: () => true },
        { id: "editor", name: "Editor", icon: "edit_note", category: "shell", searchable: true, enabled: () => true },
        { id: "audioPlayer", name: "Audio Player", icon: "headphones", category: "shell", searchable: true, enabled: () => true },
        { id: "imageViewer", name: "Image Viewer", icon: "image", category: "shell", searchable: true, enabled: () => true },
        { id: "camera", name: "Camera", icon: "photo_camera", category: "shell", searchable: true, enabled: () => true },
        { id: "audioRecorder", name: "Audio Recorder", icon: "mic", category: "shell", searchable: true, enabled: () => true },
        { id: "wikipedia", name: "Wikipedia", icon: "menu_book", category: "shell", searchable: true, enabled: () => true },
        { id: "youtube", name: "YouTube", icon: "play_circle", category: "shell", searchable: true, enabled: () => true },
        { id: "discordoVoice", name: "Discordo Voice", icon: "headset_mic", category: "shell", searchable: true, enabled: () => true },
        { id: "stremio", name: "Stremio", icon: "live_tv", category: "shell", searchable: true, enabled: () => true },
        { id: "manga", name: "Manga (MangaDex)", icon: "auto_stories", category: "shell", searchable: true, enabled: () => true },
        { id: "bluetoothManager", name: "Bluetooth", icon: "bluetooth", category: "shell", searchable: true, enabled: () => true },
        { id: "patchbay", name: "Patchbay", icon: "account_tree", category: "shell", searchable: true, enabled: () => true },
        { id: "mixer", name: "Sound Mixer", icon: "tune", category: "shell", searchable: true, enabled: () => true },
        { id: "torrents", name: "Torrents", icon: "downloading", category: "shell", searchable: true, enabled: () => true },
        { id: "diwan", name: "Diwan", icon: "auto_stories", category: "shell", searchable: true, enabled: () => true },
        { id: "quran", name: "Quran", icon: "menu_book", category: "shell", searchable: true, enabled: () => true },
        { id: "health", name: "System Health", icon: "monitor_heart", category: "shell", searchable: true, enabled: () => true }
    ]

    /// The shell's own windowed apps. Search lists them as apps rather than as actions.
    readonly property var appIds: ["notes", "clock", "grit", "weather", "soundscapes", "qanun", "calculator", "quickshare", "syncplay", "easyEffects", "usage", "modes", "downloads", "mixer", "packages", "anki", "books", "mediator", "bluetoothManager", "patchbay", "torrents", "diwan", "quran", "music", "monitor", "audioRecorder", "camera", "imageViewer", "audioPlayer", "fileManager", "editor", "wikipedia", "youtube", "discordoVoice", "health"]

    readonly property var actions: TouchGestureActionRegistry.actions.concat(root.extraActions).map(action => Object.assign({}, action, {
        keywords: action.keywords ?? root.keywordsFor(action),
        app: root.appIds.includes(action.id),
        prominent: action.prominent === true,
        category: action.category ?? "shell",
        searchable: action.searchable !== false,
        enabled: action.enabled ?? (() => true)
    }))

    function actionById(actionId) {
        return actions.find(action => action.id === actionId) ?? actions[0];
    }

    function trigger(actionId, screenName) {
        if (actionId === "notes") {
            GlobalStates.openNotes();
            return;
        }
        if (actionId === "clock") {
            GlobalStates.openClockApp("");
            return;
        }
        if (actionId === "grit") {
            GlobalStates.openGritApp("");
            return;
        }
        if (actionId === "weather") {
            GlobalStates.openWeatherApp("");
            return;
        }
        if (actionId === "soundscapes") {
            GlobalStates.openSoundscapesApp("");
            return;
        }
        if (actionId === "qanun") {
            GlobalStates.openQanunApp("");
            return;
        }
        if (actionId === "calculator") {
            GlobalStates.openCalculatorApp();
            return;
        }
        if (actionId === "quickshare") {
            GlobalStates.openQuickShareApp();
            return;
        }
        if (actionId === "syncplay") {
            GlobalStates.openSyncplayApp();
            return;
        }
        if (actionId === "monitor") {
            GlobalStates.openMonitorApp("");
            return;
        }
        if (actionId === "music") {
            GlobalStates.openMusicApp("");
            return;
        }
        if (actionId === "downloads") {
            GlobalStates.openDownloadsApp("");
            return;
        }
        if (actionId === "packages") {
            GlobalStates.openPackagesApp("");
            return;
        }
        if (actionId === "anki") {
            GlobalStates.openAnkiApp("");
            return;
        }
        if (actionId === "mediator") {
            GlobalStates.openMediatorApp("", true);
            return;
        }
        if (actionId === "books") {
            GlobalStates.openBooksApp();
            return;
        }
        if (actionId === "editor") {
            GlobalStates.openEditorApp();
            return;
        }
        if (actionId === "fileManager") {
            GlobalStates.openFileManagerApp();
            return;
        }
        if (actionId === "audioPlayer") {
            GlobalStates.openAudioPlayerApp();
            return;
        }
        if (actionId === "imageViewer") {
            GlobalStates.openImageViewerApp();
            return;
        }
        if (actionId === "camera") {
            GlobalStates.openCameraApp();
            return;
        }
        if (actionId === "audioRecorder") {
            GlobalStates.openAudioRecorderApp();
            return;
        }
        if (actionId === "wikipedia") {
            GlobalStates.openWikipediaApp();
            return;
        }
        if (actionId === "youtube") {
            GlobalStates.openYouTubeApp();
            return;
        }
        if (actionId === "discordoVoice") {
            GlobalStates.openDiscordoVoiceApp();
            return;
        }
        if (actionId === "stremio") {
            GlobalStates.openMediatorApp("stream", true);
            return;
        }
        if (actionId === "manga") {
            GlobalStates.openBooksApp();
            BooksService.openSource("manga");
            return;
        }
        if (actionId === "bluetoothManager") {
            GlobalStates.openBluetoothManagerApp("");
            return;
        }
        if (actionId === "patchbay") {
            GlobalStates.patchbayOpen = true;
            return;
        }
        if (actionId === "torrents") {
            GlobalStates.openTorrentsApp("");
            return;
        }
        if (actionId === "quran") {
            GlobalStates.openQuranApp();
            return;
        }
        if (actionId === "diwan") {
            GlobalStates.openDiwanApp();
            return;
        }
        if (actionId === "mixer") {
            GlobalStates.openMixerApp("");
            return;
        }
        if (actionId === "health") {
            GlobalStates.openHealthApp("");
            return;
        }
        if (actionId === "easyEffects") {
            GlobalStates.openEasyEffectsApp("");
            return;
        }
        // Opening from search must not close an app that is already open behind it; the
        // gesture registry toggles, which is right for a swipe and wrong here.
        if (actionId === "usage" && !PanelFamily.nativeAppWindows) {
            GlobalStates.openUsageApp("");
            return;
        }
        if (actionId === "modes" && !PanelFamily.nativeAppWindows) {
            GlobalStates.openModesApp("");
            return;
        }
        TouchGestureActionRegistry.trigger(actionId, screenName);
    }
}

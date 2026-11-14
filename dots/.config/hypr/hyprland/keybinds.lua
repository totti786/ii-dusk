require("hyprland.lib")
require("hyprland.variables")
if is_file_exists(HOME .. "/.config/hypr/custom/variables.lua") then
    require("custom.variables")
end

-- Super alone opens the shell's search on release. The shell cancels that when another
-- key is used with Super held (Super+Enter must not open search afterwards). That used to
-- be one catch-all bind, but Hyprland 0.57 only allows catch-all binds inside submaps, so
-- every Super+key bind now also fires the interrupt itself. Installed before any bind below.
do
    local plainBind = hl.bind
    local interrupt = hl.dsp.global("quickshell:searchToggleReleaseInterrupt")

    local function isSuperChord(key)
        if type(key) ~= "string" then
            return false
        end
        local parts = {}
        for chunk in key:gmatch("[^+]+") do
            parts[#parts + 1] = chunk:match("^%s*(.-)%s*$")
        end
        local last = parts[#parts]
        if #parts < 2 or last == "" or last:lower():match("^mouse") or last:lower():match("^super_[lr]$") then
            return false
        end
        for i = 1, #parts - 1 do
            if parts[i]:upper() == "SUPER" then
                return true
            end
        end
        return false
    end

    hl.bind = function(key, action, opts)
        plainBind(key, action, opts)
        if isSuperChord(key) and not (opts and opts.release) then
            plainBind(key, interrupt, { non_consuming = true })
        end
    end
end

local qsScripts = "$HOME/.config/quickshell/$qsConfig/scripts"
local hyprScripts = "$HOME/.config/hypr/hyprland/scripts"
local qsIpcCall = "qs -c $qsConfig ipc call"
local qsIsAlive = qsIpcCall .. " TEST_ALIVE"

-- Cheatsheet sections may repeat: equal names are merged across both keybind files.
-- Keep registration order unchanged; only these headings assign categories.
--##! Launcher
-- Super taps are release binds: since Hyprland 0.57 a plain "SUPER + SUPER_L" bind
-- fires on the press and always delivers its release, even after Super+A. A release
-- bind is shadowed by any key pressed in between, so only a lone tap reaches it.
hl.bind("SUPER + SUPER_L", hl.dsp.global("quickshell:searchToggleRelease"), { release = true, description = "Shell: Toggle search" })
hl.bind("SUPER + SUPER_R", hl.dsp.global("quickshell:searchToggleRelease"), { release = true })
hl.bind("SUPER + SUPER_L", hl.dsp.exec_cmd(qsIsAlive .. " || pkill fuzzel || fuzzel"), { release = true })
hl.bind("SUPER + SUPER_R", hl.dsp.exec_cmd(qsIsAlive .. " || pkill fuzzel || fuzzel"), { release = true })

hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true })
hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true })
hl.bind("SUPER_L", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true, release = true })
hl.bind("SUPER_R", hl.dsp.global("quickshell:workspaceNumber"), { ignore_mods = true, transparent = true, release = true })
hl.bind("SUPER + Tab", hl.dsp.global("quickshell:overviewWorkspacesToggle"), { description = "Shell: Toggle overview" })
-- hl.bind("CTRL + Space", hl.dsp.global("quickshell:searchOnlyToggle"), { description = "Shell: Open search only" }) -- Disabled by default for those who play games
hl.bind("SUPER + V", hl.dsp.global("quickshell:overviewClipboardToggle"))
hl.bind("SUPER + Period", hl.dsp.global("quickshell:overviewEmojiToggle"))
-- Super+Shift+C is already the Color Picker. Keep that established shortcut
-- and give Commands its own conflict-free entry point.
hl.bind("SUPER + ALT + C", hl.dsp.global("quickshell:overviewCommandsOpen"),
    { description = "Shell: Open Search commands" })
--##! Bar & panels
hl.bind("SUPER + ALT + A", hl.dsp.global("quickshell:sidebarLeftToggleDetach"), { description = "Shell: Detach the left sidebar" })
hl.bind("SUPER + B", hl.dsp.global("quickshell:sidebarLeftToggle"), { description = "Shell: Toggle left sidebar" })
hl.bind("SUPER + O", hl.dsp.global("quickshell:settingsToggle"), { description = "Shell: Settings" })
hl.bind("SUPER + N", hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Shell: Toggle right sidebar" })
--##! Modules
--##! Bar & panels
hl.bind("SUPER + Slash", hl.dsp.global("quickshell:cheatsheetToggle"), { description = "Shell: Toggle cheatsheet" })
--##! Modules
-- Super+Shift+N is already Next track, further down. The notes keep the same letter
-- with the other modifier rather than moving to a key nobody would guess.
--##! Overlays
hl.bind("SUPER + ALT + N", hl.dsp.global("quickshell:notesToggle"), { description = "Shell: Toggle notes" })
--##! Modules
--##! Overlays
hl.bind("SUPER + ALT + T", hl.dsp.global("quickshell:clockToggle"), { description = "Shell: Toggle clock" })
--##! Modules
--##! Overlays
hl.bind("SUPER + ALT + G", hl.dsp.global("quickshell:gritToggle"), { description = "Grit: Toggle habits, tasks and focus" })
--##! Modules
--##! Overlays
hl.bind("SUPER + ALT + E", hl.dsp.global("quickshell:easyEffectsToggle"), { description = "Shell: Toggle EasyEffects" })
--##! Modules
--##! Bar & panels
hl.bind("SUPER + U", hl.dsp.global("quickshell:sidebarLeftToggle"), { description = "Shell: Toggle left sidebar" })
--##! Modules
--##! Overlays
hl.bind("SUPER + ALT + U", hl.dsp.global("quickshell:usageToggle"), { description = "Shell: Toggle app usage stats" })
--##! Modules
--##! Overlays
hl.bind("SUPER + ALT + Y", hl.dsp.global("quickshell:modesToggle"), { description = "Shell: Toggle modes & routines" })
--##! Modules
--##! System apps
hl.bind("CTRL + ALT + H", hl.dsp.global("quickshell:healthToggle"), { description = "Shell: Toggle System Health" })
--##! Modules
--##! Screen & input
--##! Overlays
hl.bind("SUPER + ALT + K", hl.dsp.global("quickshell:oskToggle"), { description = "Shell: Toggle on-screen keyboard" })
--##! Screen & input
hl.bind("ALT + Space", hl.dsp.global("quickshell:dictationHold"), { description = "Dictation: Hold to talk" })
hl.bind("ALT + SHIFT + Space", hl.dsp.global("quickshell:dictationToggle"), { description = "Dictation: Start/stop" })
--##! Bar & panels
hl.bind("SUPER + SHIFT + E", hl.dsp.global("quickshell:editModeToggle"), { description = "Shell: Edit desktop layout" })
--##! Media
hl.bind("SUPER + M", hl.dsp.global("quickshell:mediaControlsToggle"), { description = "Shell: Toggle media controls" })
--##! Shell apps
hl.bind("SUPER + CTRL + M", hl.dsp.global("quickshell:mediatorToggle"), { description = "Mediator: Browse the library" })
hl.bind("SUPER + CTRL + SHIFT + M", hl.dsp.global("quickshell:mediatorWindowToggle"), { description = "Mediator: Open as a window" })
hl.bind("SUPER + CTRL + W", hl.dsp.global("quickshell:quranToggle"), { description = "Quran: Toggle the reader" })
hl.bind("SUPER + CTRL + Y", hl.dsp.global("quickshell:diwanToggle"), { description = "Diwan: Toggle the poetry reader" })
hl.bind("SUPER + CTRL + SHIFT + Y", hl.dsp.global("quickshell:diwanWindowToggle"), { description = "Diwan: Open as a window" })
hl.bind("SUPER + CTRL + SHIFT + W", hl.dsp.global("quickshell:quranWindowToggle"), { description = "Quran: Open as a window" })
hl.bind("SUPER + CTRL + D", hl.dsp.global("quickshell:downloadsToggle"), { description = "Downloads: Toggle the downloader" })
hl.bind("SUPER + CTRL + A", hl.dsp.global("quickshell:musicToggle"), { description = "Music: Toggle the player" })
--##! System apps
hl.bind("CTRL + ALT + V", hl.dsp.global("quickshell:mixerToggle"), { description = "Mixer: Toggle the sound mixer" })
--##! Shell apps
--##! System apps
hl.bind("CTRL + ALT + U", hl.dsp.global("quickshell:packagesToggle"), { description = "Packages: Toggle updates and package manager" })
--##! Shell apps
--##! System apps
hl.bind("CTRL + ALT + B", hl.dsp.global("quickshell:bluetoothManagerToggle"), { description = "Bluetooth: Toggle the Bluetooth manager" })
--##! Shell apps
--##! System apps
hl.bind("CTRL + ALT + G", hl.dsp.global("quickshell:patchbayToggle"), { description = "Patchbay: Toggle the PipeWire patchbay" })
--##! Shell apps
hl.bind("SUPER + CTRL + S", hl.dsp.global("quickshell:soundscapesToggle"), { description = "Soundscapes: Toggle the ambient sound mixer" })
hl.bind("SUPER + CTRL + E", hl.dsp.global("quickshell:torrentsToggle"), { description = "Torrents: Toggle the torrent client" })
-- App shortcuts: Super+Ctrl+letter opens an app you use, Ctrl+Alt+letter a system or hardware
-- app, Super+Alt+letter an overlay (Notes, Clock and Usage live there). Shift on an app
-- chord opens it as a window where it has one.
hl.bind("SUPER + CTRL + X", hl.dsp.global("quickshell:calculatorToggle"), { description = "Calculator: Toggle the calculator" })
--##! System apps
hl.bind("CTRL + ALT + D", hl.dsp.global("quickshell:displayModesToggle"), { description = "Display: Toggle display modes" })
--##! Shell apps
--##! Overlays
hl.bind("SUPER + ALT + H", hl.dsp.global("quickshell:perfMonitorToggle"), { description = "Performance: Toggle the performance monitor" })
--##! Shell apps
--##! System apps
hl.bind("CTRL + ALT + M", hl.dsp.global("quickshell:monitorToggle"), { description = "Monitor: Toggle the system and latency monitor" })
--##! Shell apps
-- K is the existing-workspace focus pair (Ctrl+J/K/L/;); Q is free.
hl.bind("SUPER + CTRL + Q", hl.dsp.global("quickshell:ankiToggle"), { description = "Anki: Review flashcards" })
hl.bind("SUPER + CTRL + B", hl.dsp.global("quickshell:booksOverlayToggle"), { description = "Books: Immersive browser (scroll and type to find)" })
hl.bind("SUPER + CTRL + SHIFT + B", hl.dsp.global("quickshell:booksToggle"), { description = "Books: Open the library window" })
hl.bind("SUPER + CTRL + F", hl.dsp.global("quickshell:weatherToggle"), { description = "Weather: Forecast, rain and air quality" })
hl.bind("SUPER + CTRL + U", hl.dsp.global("quickshell:youTubeToggle"), { description = "YouTube: Search and watch videos" })
hl.bind("SUPER + CTRL + N", hl.dsp.global("quickshell:wikipediaToggle"), { description = "Wikipedia: Read articles" })
--##! System apps
hl.bind("CTRL + ALT + C", hl.dsp.global("quickshell:cameraToggle"), { description = "Camera: Webcam preview and photos" })
--##! Shell apps
--##! Bar & panels
--##! Overlays
hl.bind("SUPER + ALT + O", hl.dsp.global("quickshell:overlayToggle"), { description = "Shell: Toggle widget overlay" })
--##! Bar & panels
--##! Session
hl.bind("CTRL + ALT + Delete", hl.dsp.global("quickshell:sessionToggle"), { description = "Shell: Toggle session menu" })
--##! Bar & panels
hl.bind("SUPER + J", hl.dsp.global("quickshell:barToggle"), { description = "Shell: Toggle bar" })
--##! Session
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd(qsIsAlive .. " || pkill wlogout || wlogout -p layer-shell"))
--##! Modules
--##! Bar & panels
hl.bind("SHIFT + SUPER + ALT + Slash", hl.dsp.exec_cmd("qs -c ii ipc call welcome toggle"), { description = "Shell: Toggle welcome" })
--##! Modules

--##! Screen & input
-- Toggle keyboard layout safely without triggering search release
--##! Window
hl.bind("SUPER + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Window: Toggle floating" })
--##! Screen & input

--##! Screen & input
-- The keys write the backlight themselves, so they still work while the shell reloads or is
-- down; the shell watches the backlight for its OSD. See the script's header.
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd(qsScripts .. "/brightness/brightness-key.sh up"),
    { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(qsScripts .. "/brightness/brightness-key.sh down"),
    { locked = true, repeating = true })
-- Caps Lock / Num Lock pills, on release: xkb turns a lock off only when the second press
-- is released, so the state is read then. The keys still reach apps (non-consuming).
hl.bind("Caps_Lock", hl.dsp.global("quickshell:osdCapsLock"),
    { non_consuming = true, ignore_mods = true, release = true }) -- # [hidden]
hl.bind("Num_Lock", hl.dsp.global("quickshell:osdNumLock"),
    { non_consuming = true, ignore_mods = true, release = true }) -- # [hidden]
-- Touchpad keys, with an OSD pill. Some laptops send the toggle with Ctrl+Super held.
-- hl.bind("XF86TouchpadToggle", hl.dsp.exec_cmd(hyprScripts .. "/touchpad-toggle.sh"),
--     { locked = true, ignore_mods = true, description = "Input: Toggle touchpad" })
-- hl.bind("XF86TouchpadOn", hl.dsp.exec_cmd(hyprScripts .. "/touchpad-toggle.sh on"),
--     { locked = true, ignore_mods = true }) -- # [hidden]
-- hl.bind("XF86TouchpadOff", hl.dsp.exec_cmd(hyprScripts .. "/touchpad-toggle.sh off"),
--     { locked = true, ignore_mods = true }) -- # [hidden]
--##! Media
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%+ -l 1.5"),
    { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 2%-"),
    { locked = true, repeating = true })

--##! Appearance
hl.bind("CTRL + ALT + W", hl.dsp.global("quickshell:wallpaperSelectorRandom"),
    { description = "Shell: Select random wallpaper" })
hl.bind("CTRL + ALT + W", hl.dsp.exec_cmd(qsIsAlive .. " || " .. "$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh --random"))
hl.bind("CTRL + ALT + SHIFT + W", hl.dsp.exec_cmd(qsIpcCall .. " wallpaperSelector toggleLockscreen"),
    { description = "Shell: Choose the lock screen wallpaper" })
hl.bind("CTRL + ALT + SHIFT + L", hl.dsp.exec_cmd(qsIpcCall .. " wallpaperSelector toggleLightmode"),
    { description = "Shell: Choose the light-mode wallpaper" })
hl.bind("CTRL + SUPER + SHIFT + D", hl.dsp.global("quickshell:toggleLightDark"),
    { description = "Shell: Toggle light/dark mode" })
--##! User
-- `qs kill` is the only shutdown that also takes the shell's child processes
-- down with it, and it returns once the instance is really gone; killall is
-- kept for an instance too wedged to answer over IPC. MALLOC_CONF and the guard:
-- see execs.lua.
-- One restart at a time. The shell takes several seconds to answer over IPC after it starts, so
-- a second press in that window found nothing to `qs kill`, fell back to killall, and left the
-- first press's guard running: it restarted its own shell next to the new one (two shells at once).
-- The lock is held until the new shell answers (or 30 s), so presses during that are ignored, and
-- the guard (a bash script, so matched on its command line) is stopped along with every shell
-- instance, not just the one `qs kill` finds. The lock fd is closed for the shell itself (9>&-),
-- or the shell would keep it for as long as it lives.
--##! Bar & panels
hl.bind("CTRL + SUPER + R",
--##! User
    hl.dsp.exec_cmd("exec 9>\"${XDG_RUNTIME_DIR:-/tmp}/qs-restart.lock\"; flock -n 9 || exit 0; "
        .. "pkill -f '^bash [^ ]*/qs-guard[.]sh'; killall ydotool; qs kill -c $qsConfig; killall qs quickshell 2>/dev/null; "
        .. "for i in $(seq 50); do pgrep -x qs >/dev/null || break; sleep 0.1; done; "
        .. "g=" .. qsScripts .. "/quickshell-guard/qs-guard.sh; "
        .. "if [ -x \"$g\" ]; then MALLOC_CONF=narenas:1 setsid -f \"$g\" -c $qsConfig 9>&-; "
        .. "else MALLOC_CONF=narenas:1 qs -c $qsConfig 9>&- & fi; "
        .. "for i in $(seq 60); do qs ipc show -c $qsConfig >/dev/null 2>&1 && break; sleep 0.5; done"),
    { description = "Shell: Restart widgets" })
--##! Bar & panels
--##! Appearance
hl.bind("CTRL + SUPER + P", hl.dsp.global("quickshell:panelFamilyPicker"), { description = "Shell: Choose the panel family" })
--##! Bar & panels

--##! Launcher
--# Clipboard history and emoji search
hl.bind("SUPER + V", hl.dsp.exec_cmd(
    qsIsAlive .. " || pkill fuzzel || cliphist list | fuzzel --match-mode fzf --dmenu | cliphist decode | wl-copy"),
    { description = "Utilities: Clipboard history >> clipboard" })
hl.bind("SUPER + Period", hl.dsp.exec_cmd(
    qsIsAlive .. " || pkill fuzzel || " .. hyprScripts .. "/fuzzel-emoji.sh copy"),
    { description = "Utilities: Emoji >> clipboard" })
--##! Apps
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("gtk-launch spotify-adblock || gtk-launch spotify"), { description = "Apps: Spotify" })

--##! Tools
hl.bind("SUPER + SHIFT + A", hl.dsp.global("quickshell:regionSearch"), { description = "Utilities: Google Lens" })

--# OCR
hl.bind("SUPER + SHIFT + X", hl.dsp.global("quickshell:regionOcr"),
    { description = "Utilities: Character recognition >> clipboard" })
hl.bind("SUPER + SHIFT + T", hl.dsp.global("quickshell:screenTranslate"),
    { description = "Utilities: Translate screen content" })

--# Color picker
hl.bind("SUPER + SHIFT + C", hl.dsp.global("quickshell:colorPickerLaunch"),
    { description = "Utilities: Pick color #RRGGBB >> clipboard" })

--##! Window
--# Pin the window on top
hl.bind("SUPER + ALT + P", hl.dsp.window.pin({ action = "toggle" }),
--##! Tools
    { description = "Window: Pin on top" })
--##! Overlays
--# Live draw (annotate the screen over every app)
hl.bind("SUPER + ALT + D", hl.dsp.global("quickshell:liveDrawToggle"),
--##! Tools
    { description = "Utilities: Draw on screen" })
--##! Screenshot & recording
--# Recording stuff
hl.bind("SUPER + SHIFT + R", hl.dsp.global("quickshell:regionRecord"),
    { locked = true, description = "Utilities: Record region (no sound)" })
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd(qsIsAlive .. " || " .. qsScripts .. "/videos/record.sh"), { locked = true })
--# Video Editor
hl.bind("SUPER + SHIFT + V", hl.dsp.global("quickshell:videoEditorToggle"),
    { description = "Utilities: Video editor" })
--# Screenshots (quickshell native)
hl.bind("Print", hl.dsp.global("quickshell:fullScreenshot"),
    { locked = true, description = "Utilities: Screenshot (full screen)" })
hl.bind("SUPER + Print", hl.dsp.exec_cmd("grim - | wl-copy"),
    { locked = true, description = "Utilities: Screenshot (fullscreen) >> clipboard" })
--##! Tools
--# AI
hl.bind("SUPER + SHIFT + ALT + mouse:273", hl.dsp.exec_cmd(hyprScripts .. "/ai/primary-buffer-query.sh"),
    { description = "Utilities: Generate AI summary for selected text" })
-- (requires a running ollama model)

--#!
--##! Window
--# Window switcher: bound at runtime by the shell (services/WindowSwitcher.qml) while
--# Settings > Windows > Window switcher is on, so it is documented here only
--#/# bind = ALT, Tab,, # Switch windows (hold Alt, Tab to cycle)
--#/# bind = ALT + SHIFT, Tab,, # Switch windows backwards
--#/# bind = ALT, grave,, # Switch between this app's windows (the key above Tab)
--# Focusing
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Window: Move" })
hl.bind("SUPER + mouse:274", hl.dsp.window.drag(), { mouse = true })
hl.bind("SUPER + mouse:273", hl.dsp.window.resize(), { mouse = true, description = "Window: Resize" })
--# Tiling assistant: report the drag to the shell alongside Hyprland's own move
--# and resize, so the zone overlay knows a window is being dragged
hl.bind("SUPER + mouse:272", hl.dsp.global("quickshell:tilingDragMove"))   -- # [hidden]
hl.bind("SUPER + mouse:274", hl.dsp.global("quickshell:tilingDragMove"))   -- # [hidden]
hl.bind("SUPER + mouse:273", hl.dsp.global("quickshell:tilingDragResize")) -- # [hidden]
--#/# bind = SUPER, ←/↑/→/↓,, # Focus in direction
for i = 1, 6 do
    local arrowkey = { "Left", "Right", "Up", "Down", "BracketLeft", "BracketRight" }
    local focusdir = { "l", "r", "u", "d", "l", "r" }
    hl.bind("SUPER + " .. arrowkey[i], hl.dsp.focus({ direction = focusdir[i] }))
end
--#/# bind = SUPER + SHIFT, ←/↑/→/↓,, # Move in direction
for i = 1, 4 do
    local arrowkey = { "Left", "Right", "Up", "Down" }
    local focusdir = { "l", "r", "u", "d" }
    hl.bind("SUPER + SHIFT + " .. arrowkey[i], hl.dsp.window.move({ direction = focusdir[i] }))
end
--# Tiling assistant: walk the focused window through the tiling zones, leaving
--# the move-in-direction above to Hyprland's own layout
--#/# bind = SUPER + ALT, ←/↑/→/↓,, # Quick-tile in direction (again at the edge to untile)
for i = 1, 4 do
    local arrowkey = { "Left", "Right", "Up", "Down" }
    hl.bind("SUPER + ALT + " .. arrowkey[i], hl.dsp.global("quickshell:tilingTile" .. arrowkey[i]))
end
--# Tiling assistant: swap the focused monitor between zone layouts without
--# opening settings
--#/# bind = SUPER + ALT, Tab,, # Next tiling layout
hl.bind("SUPER + ALT + Tab", hl.dsp.global("quickshell:tilingLayoutCycle"))
--#/# bind = SUPER + ALT + SHIFT, Tab,, # Previous tiling layout
hl.bind("SUPER + ALT + SHIFT + Tab", hl.dsp.global("quickshell:tilingLayoutCyclePrev"))

-- hl.bind("ALT + F4",
--     function() hl.exec_cmd(
--         "notify-send \"Wrong close keybind\" \"Super+Q to close. Use Alt+F4 for Windows VMs\" -a Hyprland") end,
--     { non_consuming = true })
hl.bind("SUPER + Q", hl.dsp.exec_cmd(qsScripts .. "/hyprland/close_window.sh"), { description = "Window: Close (not while a shell overlay is open)" })
hl.bind("SUPER + SHIFT + ALT + Q", hl.dsp.exec_cmd("hyprctl kill"), { description = "Window: Forcefully zap a window" })
hl.bind("SUPER + SHIFT + CTRL + Q", hl.dsp.global("quickshell:reopenClosedWindow"),
    { description = "Window: Reopen the last closed window" })

--# Window split ratio
--#/# binde = SUPER, ;/',, # Adjust split ratio
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
--# Positioning mode
hl.bind("SUPER + D", hl.dsp.workspace.toggle_special("special"),
    { description = "Window: Show/hide the special workspace" })
--##! Apps
hl.bind("SUPER + F", hl.dsp.exec_cmd("firefox"), { description = "App: Browser" })
--##! Window
hl.bind("SUPER + ALT + F", hl.dsp.window.fullscreen_state({ internal = 0, client = 3, action = "toggle" }),
    { description = "Window: Fullscreen spoof" })

--##! Workspace
--#/# bind = SUPER+ALT, Hash,, # Silently send to workspace (1, 2, 3,...)
--# We use raw keycodes because some keyboard layouts register number keys as different chars. The codes can be verified with `wev`
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }

    hl.bind("SUPER + ALT + code:" .. numberkey[i], function()
        hl.dispatch(
            hl.dsp.window.move({
                workspace = workspace_in_group(i),
                follow = false,
                silent = true
            })
        )
    end)
end
--# keypad numbers
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }

    hl.bind("SUPER + ALT + code:" .. numpadkey[i], function()
        hl.dispatch(
            hl.dsp.window.move({
                workspace = workspace_in_group(i),
                follow = false,
                silent = true
            })
        )
    end)
end

--#/# bind = SUPER+SHIFT, Scroll ↑/↓,, # Send to workspace left/right
for i = 1, 4 do
    local key = { "SUPER + SHIFT + mouse_", "SUPER + ALT + mouse_" }
    local keycombos = { key[1] .. "up", key[1] .. "down", key[2] .. "up", key[2] .. "down" }
    local prefix = { "r-", "r+", "-", "+" }
    hl.bind(keycombos[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" }))
end

--#/# bind = SUPER+SHIFT, Page_↑/↓,, # Send to workspace left/right
for i = 1, 6 do
    local key = { "SUPER + ALT + Page_", "SUPER + SHIFT + Page_", "CTRL + SUPER + SHIFT + " }
    local keycombos = { key[1] .. "down", key[1] .. "up", key[2] .. "down", key[2] .. "up", key[3] .. "Right", key[3] ..
    "Left" }
    local prefix = { "+", "-", "+", "-", "+", "-" }
    hl.bind(keycombos[i], hl.dsp.window.move({ workspace = prefix[i] .. "1" })) -- # [hidden]
end

hl.bind("CTRL + SUPER + C", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger"),
    { description = "Workspaces: Close gaps (renumber into 1..N)" })
--# Insert an empty workspace and go to it, shifting the ones in the way up by one; SUPER+ALT also
--# takes the focused window along
hl.bind("CTRL + SUPER + I", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=after"),
    { description = "Workspaces: Insert empty workspace after current" })
hl.bind("CTRL + SUPER + SHIFT + I", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=before"),
    { description = "Workspaces: Insert empty workspace before current" })
hl.bind("CTRL + SUPER + Home", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=first"),
    { description = "Workspaces: Insert empty workspace first" })
hl.bind("SUPER + ALT + I", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=after --take"),
    { description = "Window: Send to new workspace after current" })
hl.bind("SUPER + ALT + SHIFT + I", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=before --take"),
    { description = "Window: Send to new workspace before current" })
hl.bind("SUPER + ALT + Home", hl.dsp.exec_cmd(qsScripts .. "/hyprland/workspace_arranger --insert=first --take"),
    { description = "Window: Send to new workspace first" })

--##! Window
hl.bind("SUPER + ALT + S", function()
    local ok, err = pcall(function()
        local w = hl.get_active_window()
        if not w then return end
        
        local is_special = false
        if w.workspace and w.workspace.name then
            if w.workspace.name:sub(1, 7) == "special" then
                is_special = true
            end
        end
        
        if is_special then
            local active_mon = hl.get_active_monitor()
            local target_ws = nil
            if active_mon and active_mon.activeWorkspace and active_mon.activeWorkspace.name then
                target_ws = active_mon.activeWorkspace.name
            else
                local active_ws = hl.get_active_workspace()
                if active_ws and active_ws.name and active_ws.name:sub(1, 7) ~= "special" then
                    target_ws = active_ws.name
                end
            end
            
            if target_ws then
                hl.dispatch(hl.dsp.window.move({ workspace = target_ws, silent = false }))
            end
        else
            hl.dispatch(hl.dsp.window.move({ workspace = "special:special", silent = true }))
        end
    end)
    if not ok then
        os.execute("notify-send 'Scratchpad Error' '" .. tostring(err):gsub("'", "\\'") .. "'")
    end
end, {description = "Window: Toggle scratchpad"})


--##! Workspace
--# Switching
--#/# bind = SUPER, Hash,, # Focus workspace (1, 2, 3,...)
--# We use raw keycodes because some keyboard layouts register number keys as different chars. The codes can be verified with `wev`
for i = 1, 10 do
    local numberkey = { 10, 11, 12, 13, 14, 15, 16, 17, 18, 19 }
    hl.bind("SUPER + code:" .. numberkey[i], function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end)
end
--# keypad numbers
for i = 1, 10 do
    local numpadkey = { 87, 88, 89, 83, 84, 85, 79, 80, 81, 90 }
    hl.bind("SUPER + code:" .. numpadkey[i], function()
        hl.dispatch(hl.dsp.focus({ workspace = workspace_in_group(i) }))
    end)
end

--#/# bind = CTRL+SUPER, ←/→,, # Focus left/right
--#/# bind = CTRL+SUPER+ALT, ←/→,, # [hidden] Focus busy left/right
for i = 1, 4 do
    local key = { "CTRL + SUPER + ", "CTRL + SUPER + ALT + " }
    local keycombos = { key[1] .. "Right", key[1] .. "Left", key[2] .. "Right", key[2] .. "Left" }
    local prefix = { "+", "-", "m+", "m-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
--#/# bind = SUPER, Page_↑/↓,, # Focus left/right
for i = 1, 4 do
    local key = { "SUPER + Page_Down", "SUPER + Page_Up" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix = { "+", "-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
--#/# bind = SUPER, Scroll ↑/↓,, # Focus left/right
for i = 1, 4 do
    local key = { "SUPER + mouse_down", "SUPER + mouse_up" }
    local keycombos = { key[1], key[2], "CTRL + " .. key[1], "CTRL + " .. key[2] }
    local prefix = { "+", "-", "r+", "r-" }
    hl.bind(keycombos[i], hl.dsp.focus({ workspace = prefix[i] .. "1" }))
end
--##! Screenshot & recording
hl.bind("SUPER + S", hl.dsp.exec_cmd(qsIpcCall .. " region edit"), { description = "Utilities: Screenshot edit" })
--##! Workspace
--## Special
hl.bind("SUPER + mouse:275", hl.dsp.workspace.toggle_special("special"))
for i = 1, 2 do
    local key = { "BracketLeft", "BracketRight" }
    local prefix = { "-1", "+1" }
    hl.bind("CTRL + SUPER + " .. key[i], hl.dsp.focus({ workspace = prefix[i] }))
end

--##! Session
hl.define_submap("virtual-machine", function()
    hl.bind("SUPER + ALT + F1", function()
        local currentsubmap = hl.get_current_submap()
        if currentsubmap == "virtual-machine" then
            hl.dispatch(hl.dsp.exec_cmd(
            "notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland'"))
            hl.dispatch(hl.dsp.submap("reset"))
        elseif currentsubmap == "" then
            hl.dispatch(hl.dsp.exec_cmd(
            "notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. hit SUPER+ALT+F1 to escape' -a 'Hyprland'"))
            hl.dispatch(hl.dsp.submap("virtual-machine"))
        end
    end, { submap_universal = true })
end)


--#!
--# Testing

--##! Session
hl.bind("SUPER + L", hl.dsp.exec_cmd(qsIpcCall .. " lock activate; loginctl lock-session"), { description = "Session: Lock" })
hl.bind("SUPER + SHIFT + L", hl.dsp.exec_cmd("systemctl suspend || loginctl suspend"),
    { locked = true, description = "Session: Suspend system" })                                                                                   -- Sleep
-- hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("systemctl suspend || loginctl suspend"), {locked = true} ) -- # [hidden] Suspend when laptop lid is closed, uncomment if for whatever reason it's not the default behavior

hl.bind("CTRL + SHIFT + ALT + SUPER + Delete", hl.dsp.exec_cmd("systemctl poweroff || loginctl poweroff"),
    { description = "Session: Shut down" })                                                                                                       -- # [hidden] Power off

--##! Screen & input
--# Zoom
local function zoomfunction(value)
    local zoomvalue = hl.get_config("cursor:zoom_factor")
    if (zoomvalue + value) > 3.0 then
        hl.config({ cursor = { zoom_factor = 3.0 } })
    elseif (zoomvalue + value) < 1.0 then
        hl.config({ cursor = { zoom_factor = 1.0 } })
    else
        hl.config({ cursor = { zoom_factor = zoomvalue + value } })
    end
end

hl.bind("SUPER + Minus", function() zoomfunction(-0.3) end, { repeating = true, description = "Screen: Zoom out" })
hl.bind("SUPER + Equal", function() zoomfunction(0.3) end, { repeating = true, description = "Screen: Zoom in" })
hl.bind("SUPER + code:82", function() zoomfunction(-0.3) end, { repeating = true })
hl.bind("SUPER + code:86", function() zoomfunction(0.3) end, { repeating = true })
hl.bind("SUPER + XF86MonBrightnessDown", hl.dsp.exec_cmd("auto-brightness"), { locked = true })

--# Zoom with keypad

-- Toggle the Always On Display (OLED saver) on the focused monitor
hl.bind("SUPER + R", hl.dsp.global("quickshell:oledSaverToggle"),
    { locked = true, description = "Utilities: Toggle Always On Display" })

--##! Media
local mediaNextCommand =
"playerctl next || playerctl position `bc <<< \"100 * $(playerctl metadata mpris:length) / 1000000 / 100\"`"
hl.bind("SUPER + SHIFT + N", hl.dsp.exec_cmd(mediaNextCommand), { locked = true, description = "Media: Next track" })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd(mediaNextCommand), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("SUPER + SHIFT + ALT + mouse:275", hl.dsp.exec_cmd("playerctl previous"))
hl.bind("SUPER + SHIFT + ALT + mouse:276", hl.dsp.exec_cmd(mediaNextCommand))
hl.bind("SUPER + SHIFT + B", hl.dsp.exec_cmd("playerctl previous"), { locked = true, description = "Media: Previous track" })
hl.bind("SUPER + SHIFT + P", hl.dsp.exec_cmd("playerctl play-pause"),
    { locked = true, description = "Media: Play/pause" })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"), { locked = true })
hl.bind("SUPER + SHIFT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SINK@ toggle"),
    { locked = true, description = "Media: Mute sound" })
hl.bind("ALT + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"), { locked = true })
hl.bind("SUPER + ALT + M", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_SOURCE@ toggle"),
    { locked = true, description = "Media: Mute microphone" })
hl.bind("SUPER + Z", hl.dsp.global("quickshell:mediaModeToggle"), { locked = true, description = "Shell: Toggle media mode" })

--##! Apps
hl.bind("SUPER + Return", hl.dsp.exec_cmd(terminal), { description = "App: Terminal" })
hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(terminal))
hl.bind("SUPER + E", hl.dsp.exec_cmd(fileManager), { description = "App: File manager" })
hl.bind("SUPER + W", hl.dsp.exec_cmd(textEditor), { description = "App: Text editor" })
hl.bind("SUPER + C", hl.dsp.exec_cmd(codeEditor), { description = "App: Code editor" })
hl.bind("CTRL + SUPER + SHIFT + ALT + W", hl.dsp.exec_cmd(officeSoftware), { description = "App: Office software" })
--##! Session
hl.bind("SUPER + X", hl.dsp.global("quickshell:sessionToggle"), { description = "Shell: Toggle session menu" })
--##! Apps
--##! User
--##! Bar & panels
hl.bind("SUPER + I", hl.dsp.global("quickshell:sidebarRightToggle"), { description = "Shell: Toggle right sidebar" })
--##! User
--##! Apps
-- Hyprland cancels kill mode on ANY Escape event, press or release (handleInternalKeybinds), so
-- the script waits until Escape and Super are physically up before arming it.
hl.bind("SUPER + Escape", hl.dsp.exec_cmd("$HOME/.config/hypr/hyprland/scripts/kill-mode.py"), { description = "Window: Kill mode (click a window to kill it)" })

--##! Window
--# Cursed stuff
--## Make window not amogus large

-- ---- Our keybinds (standard) ----
-- Hyprland's bind is additive: a key bound by the stock file would fire alongside ours.
-- rebind() releases the stock bind on a key the first time this file binds it, then binds.
-- Later binds on the same key only add, so a shell bind and its fallback exec (the same
-- pattern the stock file uses) both stay.
local released = {}

-- Hyprland keeps a bind's modifier list in the order it was written and matches
-- unbind calls against that order, so unbinding "SUPER + CTRL + left" does not
-- release a stock bind spelled "CTRL + SUPER + Left" - the two live side by side
-- and both fire. The key name itself is matched case-insensitively.
local MOD_NAMES = { SUPER = true, SHIFT = true, CTRL = true, ALT = true, CAPS = true }

-- The same chord with its modifiers in the other order, or nil when the key has
-- fewer than two modifiers (there is then only one spelling to try).
local function alternate_mod_order(key)
    local parts = {}
    for chunk in key:gmatch("[^+]+") do
        local part = chunk:match("^%s*(.-)%s*$")
        if part ~= "" then
            parts[#parts + 1] = part
        end
    end
    local nmods = 0
    for i = 1, #parts - 1 do
        if not MOD_NAMES[parts[i]] then
            break
        end
        nmods = i
    end
    if nmods < 2 then
        return nil
    end
    local out = {}
    for i = nmods, 1, -1 do
        out[#out + 1] = parts[i]
    end
    for i = nmods + 1, #parts do
        out[#out + 1] = parts[i]
    end
    return table.concat(out, " + ")
end

local function rebind(key, action, opts)
    if not released[key] then
        hl.unbind(key)
        -- Release the other spelling of the same chord too, so taking a key over
        -- works whichever way round the stock file wrote its modifiers.
        local alternate = alternate_mod_order(key)
        if alternate then
            hl.unbind(alternate)
        end
        released[key] = true
    end
    hl.bind(key, action, opts)
end

-- Keybinds migrated from keybinds.conf.
-- Only dispatchers confirmed in the 0.56 Lua docs are active here. Anything else
-- is kept in the TODO block at the bottom with its original hyprlang line, so the
-- file loads cleanly. Move each line back up once you have checked its Lua form.

local qsConfig = "ii"
local qs = "qs -c " .. qsConfig
local mainMod = "SUPER"
local terminal = "terminal" -- your own wrapper script on PATH


---------------
---- SHELL ----
---------------

-- Super alone opens quickshell's search/overview on release. Any other key or click
-- cancels that, so Super+key combos do not open it (the Interrupt binds below).
-- "SUPER + " is the empty catch-all key with Super held (hyprlang "catchall")
rebind("CTRL + SUPER_L", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
rebind("SUPER + mouse:276", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
rebind("SUPER + mouse:277", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
rebind("SUPER + mouse_up", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))
rebind("SUPER + mouse_down", hl.dsp.global("quickshell:searchToggleReleaseInterrupt"))

-- Shows workspace numbers while Super is held

--##! Bar & panels
-- Launcher (quickshell, falls back to rofi)
rebind(mainMod .. " + SHIFT + W", hl.dsp.exec_cmd(qs .. " ipc call TEST_ALIVE || $HOME/.config/quickshell/ii/scripts/colors/switchwall.sh --pick"))
rebind(mainMod .. " + SHIFT + SLASH", hl.dsp.global("quickshell:settingsToggle"), { description = "Shell: Settings" })

-- OCR (fallback pipeline, the quickshell global version is in the TODO block)


-------------------
---- WORKSPACES ----
-------------------
--##! Workspace

-- Switch to workspace N
--
-- The number row is already bound by keycode in the stock section above (SUPER + code:10..19),
-- and that bind resolves to the group-relative workspace through workspace_in_group(). Binding
-- the same physical key a second time by symbol ("SUPER + 1") makes both fire on one keypress -
-- the group-relative one first, the absolute one second - so the group feature never takes
-- effect and Super+1 always lands on workspace 1. The stock keycode bind is therefore left
-- alone; only the move binds are added here, on the same group-relative target.
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    -- The target is resolved when the key is pressed, not when the config is read, so the
    -- window goes to the workspace of the group you are currently on. follow = false leaves
    -- the focus where it is: the window moves to the workspace, the cursor stays behind.
    -- The old conf called this movetoworkspacesilent.
    rebind(mainMod .. " + SHIFT + " .. key, function()
        hl.dispatch(hl.dsp.window.move({ workspace = workspace_in_group(i), follow = false }))
    end)
end

--#/# bind = SUPER+SHIFT, 1…0,, # Send window to workspace and stay
-- Scroll through workspaces with mainMod + scroll
rebind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
rebind(mainMod .. " + mouse_up", hl.dsp.focus({ workspace = "e-1" }))

-- Previous/next workspace with Super+Ctrl and the left/right arrows
-- These take over the stock "CTRL + SUPER + Left/Right/Up/Down", which the stock file
-- spells in the other modifier order and which bound "-1"/"+1" on Left/Right and a
-- ten-workspace jump ("r-10"/"r+10") on Up/Down. rebind() releases both spellings,
-- so only the action below is left on those four chords.
-- "-1"/"+1" is a plain relative ID: it lands on that workspace and creates it when
-- it is empty, where "e-1"/"e+1" (the existing-workspace variant) skipped empty ones.
-- No repeating flag: holding the key would walk backwards creating a trail of empty
-- workspaces, one per repeat.
rebind(mainMod .. " + CTRL + left", hl.dsp.focus({ workspace = "-1" }))
rebind(mainMod .. " + CTRL + right", hl.dsp.focus({ workspace = "+1" }))


---------------------
---- WINDOWS ----
---------------------
--##! Window

rebind(mainMod .. " + SHIFT + Space", hl.dsp.window.pseudo(), { description = "Window: Toggle pseudotile" })
rebind(mainMod .. " + SHIFT + G", hl.dsp.group.toggle(), { description = "Window: Toggle group" })
-- Cycle the active tab in a group (repeats like the original binde)
rebind(mainMod .. " + SHIFT + Tab", hl.dsp.group.next(), { repeating = true, description = "Window: Cycle tabs in group" })

-- Focus with the arrow keys
rebind(mainMod .. " + left", hl.dsp.focus({ direction = "left" }))
rebind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
rebind(mainMod .. " + up", hl.dsp.focus({ direction = "up" }))
rebind(mainMod .. " + down", hl.dsp.focus({ direction = "down" }))

-- Move the focused window (repeats, like the original binde)
rebind(mainMod .. " + SHIFT + left", hl.dsp.window.move({ direction = "left" }), { repeating = true, description = "Window: Move window left" })
rebind(mainMod .. " + SHIFT + right", hl.dsp.window.move({ direction = "right" }), { repeating = true, description = "Window: Move window right" })
rebind(mainMod .. " + SHIFT + up", hl.dsp.window.move({ direction = "up" }), { repeating = true, description = "Window: Move window up" })
rebind(mainMod .. " + SHIFT + down", hl.dsp.window.move({ direction = "down" }), { repeating = true, description = "Window: Move window down" })

-- Real fullscreen (mode 0) and maximize (mode 1)
rebind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = 0 }), { description = "Window: Fullscreen" })
rebind("CTRL + ALT + F", hl.dsp.window.fullscreen({ mode = 1 }), { description = "Window: Maximize" })

-- Special workspaces (scratchpads)
-- Move the active window to the "special" scratchpad without switching to it
rebind(mainMod .. " + SHIFT + D", hl.dsp.window.move({ workspace = "special:special" }), { description = "Window: Send to the special workspace" })
--##! Apps
rebind("ALT + Return", hl.dsp.workspace.toggle_special("drop"), { description = "Apps: Drop-down terminal" })

-- Mouse: move and resize windows


-----------------
---- APPS ----
-----------------

--##! Apps
-- Floating terminal (the terminal script's --float flag)
rebind(mainMod .. " + SHIFT + Return", hl.dsp.exec_cmd(terminal .. " --float"), { description = "Apps: Floating Terminal" })
--##! System apps
rebind("CTRL + SHIFT + Return", hl.dsp.global("quickshell:monitorOverlayToggle"), { description = "Monitor: Toggle the full-screen system overview" })
--##! Apps

-- Rofi tools


---------------------
---- WALLPAPER / SESSION ----
---------------------

--##! Appearance

--##! Session
rebind("XF86PowerOff", hl.dsp.exec_cmd("systemctl suspend"), { locked = true })


---------------------
---- SCREENSHOTS ----
---------------------

--##! Screenshot & recording
rebind("SHIFT + Print", hl.dsp.global("quickshell:regionScreenshot"), { description = "Screenshot: Screen snip" })
rebind("ALT + Print", hl.dsp.global("quickshell:regionOcr"), { description = "Screenshot: Extract text" })

-- Zoom


---------------
---- VOLUME / MEDIA ----
---------------



rebind("XF86AudioMedia", hl.dsp.exec_cmd("playerctl -a play-pause"), { locked = true })
rebind("XF86AudioStop", hl.dsp.exec_cmd("playerctl -a stop"), { locked = true })

rebind(mainMod .. " + XF86AudioRaiseVolume", hl.dsp.exec_cmd("playerctl volume 0.05+"), { locked = true })
rebind(mainMod .. " + XF86AudioLowerVolume", hl.dsp.exec_cmd("playerctl volume 0.05-"), { locked = true })

--##! Media
--#/# bind = CTRL+ALT, ←/→,, # Previous/next track
--#/# bind = CTRL+ALT, ↑/↓,, # Volume up/down
rebind("CTRL + ALT + right", hl.dsp.exec_cmd("playerctl next"), { locked = true })
rebind("CTRL + ALT + left", hl.dsp.exec_cmd("playerctl previous"), { locked = true })
rebind("CTRL + ALT + up", hl.dsp.exec_cmd("playerctl volume 0.05+"), { locked = true, repeating = true })
rebind("CTRL + ALT + down", hl.dsp.exec_cmd("playerctl volume 0.05-"), { locked = true, repeating = true })


---------------------
---- WINDOW EXTRAS ----
---------------------

--##! Window
-- Resize the focused window by 30px (repeats)
rebind(mainMod .. " + ALT + left", hl.dsp.window.resize({ x = -30, y = 0, relative = true }), { repeating = true, description = "Window: Resize left" })
rebind(mainMod .. " + ALT + right", hl.dsp.window.resize({ x = 30, y = 0, relative = true }), { repeating = true, description = "Window: Resize right" })
rebind(mainMod .. " + ALT + up", hl.dsp.window.resize({ x = 0, y = -30, relative = true }), { repeating = true, description = "Window: Resize up" })
rebind(mainMod .. " + ALT + down", hl.dsp.window.resize({ x = 0, y = 30, relative = true }), { repeating = true, description = "Window: Resize down" })



-------------------------
---- QUICKSHELL GLOBALS ----
-------------------------

-- Press-only shortcuts from quickshell. Each one calls the global shortcut by name.
--##! Bar & panels
--##! Appearance
rebind(mainMod .. " + SHIFT + W", hl.dsp.global("quickshell:wallpaperSelectorToggle"), { description = "Shell: Toggle wallpaper selector" })
--##! Bar & panels


-----------------------------------------------------------------------
---- TODO: not yet migrated ----
-----------------------------------------------------------------------
-- Each line is the original hyprlang bind. Uncomment after checking the Lua form
-- against the dispatcher docs. Hyprland 0.56's `hyprctl configerrors` will flag bad ones.
--
-- Quickshell global shortcuts (bindid/bindd/bind ... global, quickshell:*).
-- The `global` dispatcher form is not verified in Lua yet.
-- bindid = Super, Super_L, Toggle search, global, quickshell:searchToggleRelease
-- binditn = Super, catchall, global, quickshell:searchToggleReleaseInterrupt
-- bind = Ctrl, Super_L, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse:272, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse:273, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse:274, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse:275, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse:276, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse:277, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse_up, global, quickshell:searchToggleReleaseInterrupt
-- bind = Super, mouse_down, global, quickshell:searchToggleReleaseInterrupt
--
-- Window and workspace dispatchers not verified yet.
-- bind = Super, Q, killactive  (currently mapped to window.close)
--
-- Special workspace exec-rule launch
--
-- Virtual machine submap (disables keybinds). Needs the Lua submap API.
-- bind = Super+Alt, F1, exec, notify-send 'Entered Virtual Machine submap' 'Keybinds disabled. Hit Super+Alt+F1 to escape' -a 'Hyprland' && hyprctl dispatch submap virtual-machine
-- submap = virtual-machine
-- bind = Super+Alt, F1, exec, notify-send 'Exited Virtual Machine submap' 'Keybinds re-enabled' -a 'Hyprland' && hyprctl dispatch submap global
-- submap = global
--
-- Required first line from keybinds.conf: "exec = hyprctl dispatch submap global".
-- Without it, binds in the global submap may not be active. Check after the first
-- Lua launch and add it in the hyprland.start callback if needed.

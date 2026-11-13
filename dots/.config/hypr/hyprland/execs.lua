-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function()

    -- Splash: ii takes ~6-8 s to load, so show the greeter's wallpaper straight away.
    -- Quits itself once the shell has drawn its own wallpaper. Installed by
    -- ~/Projects/qs-greeter/install.sh; skipped when absent.
    hl.exec_cmd("[ -f /etc/greetd/qs-greeter/splash.qml ] && exec qs -p /etc/greetd/qs-greeter/splash.qml")

    -- Tray watcher: holds org.kde.StatusNotifierWatcher across shell restarts, so
    -- tray icons survive one. Started before the shell, which then uses it
    -- instead of registering a watcher of its own. See
    -- ~/.config/quickshell/ii/scripts/tray/README.md; a no-op until the helper
    -- is built (scripts/rust-helpers.sh build sni_watcher).
    hl.exec_cmd("$HOME/.config/quickshell/$qsConfig/scripts/tray/sni_watcher")

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    -- jemalloc defaults to 4 arenas per CPU, and the shell's ~50 threads each leave
    -- half-filled pages in their own: one arena measured ~100 MB less RAM with no
    -- change in startup time. It is read before main(), so it has to be in the
    -- environment here (and at every other place that starts the shell) - a
    -- `//@ pragma Env` in shell.qml is applied too late to reach the allocator.
    -- Started through qs-guard.sh: the shell is the notification daemon, so when it
    -- cannot start (a Qt update it was not rebuilt for, most often) the guard says
    -- so with Hyprland's own notifications and opens a terminal to rebuild it.
    -- Plain qs when the guard is missing.
    hl.exec_cmd("g=$HOME/.config/quickshell/$qsConfig/scripts/quickshell-guard/qs-guard.sh; "
        .. "if [ -x \"$g\" ]; then MALLOC_CONF=narenas:1 exec \"$g\" -c $qsConfig; "
        .. "else MALLOC_CONF=narenas:1 exec qs -c $qsConfig; fi")
    -- Relaunches the video or Wallpaper Engine wallpaper; switchwall.sh writes this script.
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")

    -- Core components (authentication, lock screen, notification daemon)
    hl.exec_cmd("gnome-keyring-daemon --start --components=secrets")
    -- An enabled hypridle.service is started by hyprland-session.target below. A second
    -- daemon runs every hook twice, and a duplicate `lock sleep` landing after a quick
    -- wake puts the sleep shade back up and blocks the fingerprint reader for 20 s.
    hl.exec_cmd("systemctl --user -q is-enabled hypridle.service || hypridle")
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target")


    -- Audio (wait for Quickshell's tray watcher so EasyEffects registers its tray icon successfully).
    -- Which build runs follows Settings > Overlays (easyEffects.preferFlatpak), as in
    -- services/EasyEffects.qml: the Flatpak when asked for or when it is the only one.
    hl.exec_cmd(
        "until busctl --user status org.kde.StatusNotifierWatcher >/dev/null 2>&1; do sleep 0.2; done; "
        .. "pf=$(jq -r '.easyEffects.preferFlatpak // false' ~/.config/illogical-impulse/config.json 2>/dev/null); "
        .. "if flatpak info com.github.wwmm.easyeffects >/dev/null 2>&1 && { [ \"$pf\" = true ] || ! command -v easyeffects >/dev/null 2>&1; }; "
        .. "then flatpak run --env=TMPDIR=$XDG_RUNTIME_DIR/app/com.github.wwmm.easyeffects com.github.wwmm.easyeffects --hide-window --service-mode; "
        .. "else easyeffects --hide-window --service-mode; fi")

    -- Clipboard: history
    -- Kill existing instances
    hl.exec_cmd("killall wl-paste wl-clip-persist 2>/dev/null")
    -- Start wl-clip-persist to retain clipboard contents after apps exit (with delay for Wayland display readiness)
    hl.exec_cmd("sleep 1.5 && wl-clip-persist --clipboard both")
    -- Start cliphist watchers with quickshell integration
    hl.exec_cmd(
        "sleep 1.5 && wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd(
        "sleep 1.5 && wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd(
        "sleep 1.5 && wl-paste --type text/uri-list --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

    -- Cursor: reapply the theme and size env.lua exported, so a size saved in Settings survives a relogin
    hl.exec_cmd(
        'hyprctl setcursor "${HYPRCURSOR_THEME:-${XCURSOR_THEME:-Bibata-Modern-Classic}}" "${HYPRCURSOR_SIZE:-${XCURSOR_SIZE:-24}}"')
end)

hl.on("hyprland.shutdown", function()
    os.execute("systemctl --user stop hyprland-session.target && sleep 0.1")
end)

-- ---- Our autostart (standard) ----
-- Our autostart, only the lines the stock hyprland/execs.lua does not already run.
-- Dropped from ours because the stock file starts them: qs, hypridle, the dbus and
-- systemd environment lines, gnome-keyring, the cliphist watchers and wl-clip-persist.
hl.on("hyprland.start", function()
    -- Wallpaper and colors
    hl.exec_cmd("$HOME/.config/quickshell/ii/scripts/colors/switchwall.sh --restore")

    -- Optional
    hl.exec_cmd("kdeconnectd")
    hl.exec_cmd("gesture-hold") -- 4-finger hold to play/pause, replaces fusuma

    -- Our own launches. The "[workspace N silent]" form is not a Lua exec: it reached the
    -- shell as a literal "[" command. Kept here, commented, until it is rewritten.
    -- hl.exec_cmd("[workspace 2 silent] firefox")
    -- hl.exec_cmd("[workspace 3 silent] thunar")
    -- hl.exec_cmd("[workspace 3 silent] geany")
    hl.exec_cmd("proto-recall --shoot")
end)

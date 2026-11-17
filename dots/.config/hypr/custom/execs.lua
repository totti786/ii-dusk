-- Your autostart commands go here.

-- Lid policy: holds logind's lid inhibitor and decides what a closed lid does (blank,
-- disable the panel when docked, or suspend). Replaces the old switch binds + lid.sh.
-- If it dies logind's own lid handling comes back. Config: ~/.config/ii-lid.json.
hl.on("hyprland.start", function()
    hl.exec_cmd("python3 $HOME/.config/quickshell/$qsConfig/scripts/lid/lid_handler.py")
end)

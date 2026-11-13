-- Your keybinds go here. Loaded after hyprland/keybinds.lua; use rebind() to replace a stock bind.

-- Lid switch. Close blanks the internal panel on AC (or while the shell's
-- keep-awake toggle is on) and suspends on battery; open brings it back.
-- logind's HandleLidSwitch stays "ignore" so the event is handled once, here.
hl.bind("switch:on:Lid Switch", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/lid.sh close"),
    { locked = true, description = "Lid: blank panel on AC, suspend on battery [hidden]" })
hl.bind("switch:off:Lid Switch", hl.dsp.exec_cmd("$HOME/.config/hypr/custom/scripts/lid.sh open"),
    { locked = true, description = "Lid: restore panel [hidden]" })

--##! Shell apps
-- Passwords popup (Bitwarden/rbw/pass). Opens as an overlay with the keyboard when the bar has no Passwords widget.
hl.bind("SUPER + CTRL + Z", hl.dsp.exec_cmd("qs -c ii ipc call passwordManager toggle"), { description = "Passwords: Toggle the vault popup" })

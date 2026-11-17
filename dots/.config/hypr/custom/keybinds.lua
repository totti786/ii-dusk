-- Your keybinds go here. Loaded after hyprland/keybinds.lua; use rebind() to replace a stock bind.

--##! Shell apps
-- Passwords popup (Bitwarden/rbw/pass). Opens as an overlay with the keyboard when the bar has no Passwords widget.
hl.bind("SUPER + CTRL + Z", hl.dsp.exec_cmd("qs -c ii ipc call passwordManager toggle"), { description = "Passwords: Toggle the vault popup" })

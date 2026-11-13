-- Your overrides for hyprland/general.lua go here. Loaded after the standard file.

-- >>> quickshell:managed:begin v1 - written by Settings -> Hyprland. Edits here are overwritten; put your own Lua above.
hl.config({ input = { kb_layout = "us,ara" } })                 --@k input:kb_layout
hl.config({ input = { kb_options = "grp:alt_shift_toggle" } })  --@k input:kb_options
hl.config({ general = { layout = "dwindle" } })                 --@k general:layout
-- <<< quickshell:managed:end

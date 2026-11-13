---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout = "us",
        kb_variant = "",
        kb_options = "",
        kb_rules = "",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,

        follow_mouse = 1,
        off_window_axis_events = 2,

        sensitivity = 0.5,
        accel_profile = "flat",
        special_fallthrough = true,

        touchpad = {
            disable_while_typing = true,
            natural_scroll = false,
            clickfinger_behavior = true,
            middle_button_emulation = true,
            tap_to_click = true, -- TODO: confirm key name (hyprlang used tap-to-click)
            scroll_factor = 0.5,
        },
    },
})

-- Gestures from the gestures {} block.
-- TODO: confirm these keys still exist in 0.56 (hyprctl configerrors will report them).
hl.config({
    gestures = {
        workspace_swipe_use_r = true,
        workspace_swipe_invert = false,
        workspace_swipe_forever = false,
        workspace_swipe_create_new = true,
        workspace_swipe_direction_lock = false,
        workspace_swipe_min_speed_to_force = 30,
    },
})

-- MONITOR CONFIG
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = "1"
})

-- Touchpad gestures live in hyprland/gestures.lua, which registers the defaults or
-- the set chosen in the shell's settings. Required from here rather than from
-- hyprland.lua so this file and that one can only ever be installed together.
do
    local ok, err = pcall(require, "hyprland.gestures")
    if not ok then
        hl.exec_cmd("notify-send 'Hyprland Lua Error' 'Failed to load hyprland.gestures: "
            .. tostring(err):gsub("'", "\\'") .. "' -u critical -a 'Hyprland'")
    end
end

hl.config({
    gestures = {
        workspace_swipe_distance = 700,
        workspace_swipe_cancel_ratio = 0.2,
        workspace_swipe_min_speed_to_force = 5,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true
    },
    general = {
        -- Gaps and border
        gaps_in = 10,
        gaps_out = 11,
        gaps_workspaces = 50,

        border_size = 3,

        col = {
            active_border = "rgba(f61680FF)",
            inactive_border = "rgba(31313600)"
        },
        resize_on_border = true,

        no_focus_fallback = true,
        allow_tearing = true, -- This just allows the `immediate` window rule to work
        snap = {
            enabled = true,
            window_gap = 4,
            monitor_gap = 5,
            respect_gaps = true
        }
    },
    decoration = {
        -- 2 = circle, higher = squircle, 4 = very obvious squircle
        -- Fuck clearly visible squircles. 100% Apple brainrot.
        rounding_power = 4,
        rounding = 18,

        blur = {
            enabled = true,
            xray = false,
            -- Let Hyprland blur the desktop behind special workspaces (the scratchpad).
            -- This is compositor-side blur, so the background stays smooth without
            -- creating a fullscreen blur window in Quickshell.
            special = true,
            new_optimizations = true,
            size = 10,
            passes = 3,
            brightness = 1,
            noise = 0.05,
            contrast = 0.89,
            vibrancy = 0.2,
            vibrancy_darkness = 0.2,
            popups = false,
            popups_ignorealpha = 0.6,
            input_methods = true,
            input_methods_ignorealpha = 0.8
        },
        shadow = {
            enabled = true,
            range = 20,
            offset = {0, 2},
            render_power = 4, -- Hyprland 0.57 caps this at 4
            color = "rgba(00000020)"

        },
        -- Dim
        dim_inactive = true,
        dim_strength = 0.05,
        dim_special = 0.2
    },
    animations = {
        enabled = true
    },
    dwindle = {
        preserve_split = true,
        smart_split = false,
        smart_resizing = false
        -- precise_mouse_move = true,
    },
})
-- Curves
hl.curve("expressiveFastSpatial", {
    type = "bezier",
    points = {{0.42, 1.67}, {0.21, 0.90}}
})
hl.curve("expressiveSlowSpatial", {
    type = "bezier",
    points = {{0.39, 1.29}, {0.35, 0.98}}
})
hl.curve("expressiveDefaultSpatial", {
    type = "bezier",
    points = {{0.38, 1.21}, {0.22, 1.00}}
})
hl.curve("emphasizedDecel", {
    type = "bezier",
    points = {{0.05, 0.7}, {0.1, 1}}
})
hl.curve("emphasizedAccel", {
    type = "bezier",
    points = {{0.3, 0}, {0.8, 0.15}}
})
hl.curve("standardDecel", {
    type = "bezier",
    points = {{0, 0}, {0, 1}}
})
hl.curve("menu_decel", {
    type = "bezier",
    points = {{0.1, 1}, {0, 1}}
})
hl.curve("menu_accel", {
    type = "bezier",
    points = {{0.52, 0.03}, {0.72, 0.08}}
})
hl.curve("stall", {
    type = "bezier",
    points = {{1, -0.1}, {0.7, 0.85}}
})
-- Window open/close curves. Quickshell re-pushes these (and the chosen Scale/Slide
-- preset) from Settings -> Windows after every reload; the values here match the Scale preset.
hl.curve("iiAppOpen", {
    type = "bezier",
    points = {{0.22, 1}, {0.36, 1}}
})
hl.curve("iiAppSlide", {
    type = "bezier",
    points = {{0.3, 0.7}, {0.1, 1}}
})
hl.curve("iiAppClose", {
    type = "bezier",
    points = {{0.32, 0.72}, {0, 1}}
})
hl.curve("iiAppFade", {
    type = "bezier",
    points = {{0.2, 0.6}, {0.35, 1}}
})
-- Configs
-- windows
hl.animation({
    leaf = "windowsIn",
    enabled = true,
    speed = 4,
    bezier = "iiAppOpen",
    style = "popin 20%"
})
hl.animation({
    leaf = "fadeIn",
    enabled = true,
    speed = 2.8,
    bezier = "iiAppFade"
})
hl.animation({
    leaf = "windowsOut",
    enabled = true,
    speed = 2.6,
    bezier = "iiAppClose",
    style = "popin 60%"
})
hl.animation({
    leaf = "fadeOut",
    enabled = true,
    speed = 2.6,
    bezier = "iiAppClose"
})
hl.animation({
    leaf = "windowsMove",
    enabled = true,
    speed = 4,
    bezier = "iiAppOpen",
    style = "slide"
})
hl.animation({
    leaf = "border",
    enabled = true,
    speed = 10,
    bezier = "emphasizedDecel"
})

-- layers
hl.animation({
    leaf = "layersIn",
    enabled = true,
    speed = 2.7,
    bezier = "emphasizedDecel",
    style = "popin 93%"
})
hl.animation({
    leaf = "layersOut",
    enabled = true,
    speed = 2.4,
    bezier = "menu_accel",
    style = "popin 94%"
})
-- fade
hl.animation({
    leaf = "fadeLayersIn",
    enabled = true,
    speed = 2.7,
    bezier = "stall"
})
hl.animation({
    leaf = "fadeLayersOut",
    enabled = true,
    speed = 2.7,
    bezier = "stall"
})
-- workspaces
hl.animation({
    leaf = "workspaces",
    enabled = true,
    speed = 7,
    bezier = "menu_decel",
    style = "slide"
})
-- specialWorkspace
hl.animation({
    leaf = "specialWorkspaceIn",
    enabled = true,
    speed = 2.8,
    bezier = "emphasizedDecel",
    style = "slidevert"
})
hl.animation({
    leaf = "specialWorkspaceOut",
    enabled = true,
    speed = 1.2,
    bezier = "emphasizedAccel",
    style = "slidevert"
})
-- zoom
hl.animation({
    leaf = "zoomFactor",
    enabled = true,
    speed = 3,
    bezier = "standardDecel"
})

hl.config({
    input = {
        kb_layout = "us",
        numlock_by_default = true,
        repeat_delay = 250,
        repeat_rate = 35,

        follow_mouse = 1,
        off_window_axis_events = 2,

        touchpad = {
            natural_scroll = true,
            disable_while_typing = true,
            clickfinger_behavior = true,
            scroll_factor = 0.7
        }
    },

    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        vrr = 0,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
        enable_swallow = false,
        swallow_regex = "(foot|kitty|allacritty|Alacritty)",
        on_focus_under_fullscreen = 2,
        allow_session_lock_restore = true,
        session_lock_xray = true,
        initial_workspace_tracking = false,
        focus_on_activate = true
    },

    binds = {
        scroll_event_delay = 0,
        hide_special_on_workspace_change = true
    },

    cursor = {
        zoom_factor = 1,
        zoom_rigid = false,
        zoom_disable_aa = true,
        hotspot_padding = 1,
        no_hardware_cursors = true
    },

    xwayland = {
        force_zero_scaling = true
    }
})

-- ---- Our look and feel (standard) ----
-- Our look and feel, animations and misc settings. Loaded after the stock defaults,
-- so the values here win and anything not set here keeps the stock value.
require("monitors") -- generated by nwg-displays
local colors = require("colors")

--------------------
---- LOOK AND FEEL ----
--------------------

hl.config({
    general = {
        gaps_in = 5,
        gaps_out = 5,
        border_size = 2,

        col = {
            active_border = { colors = { colors.green, colors.cyan }, angle = 45 },
            inactive_border = { colors = { colors.magenta, colors.yellow }, angle = 60 },
        },

        allow_tearing = true,
        resize_on_border = true,
        layout = "dwindle",

        snap = {
            enabled = true,
            window_gap = 15,
            monitor_gap = 15,
            border_overlap = false,
            respect_gaps = true,
        },
    },

    group = {
        auto_group = true,
        insert_after_current = true,
        focus_removed_window = true,
        drag_into_group = 1,
        merge_groups_on_drag = true,
        merge_groups_on_groupbar = true,
        merge_floated_into_tiled_on_groupbar = false,
        group_on_movetoworkspace = false,

        col = {
            -- Border follows the tab colours so tab bar and window read as one frame.
            border_active = colors.magenta,
            border_inactive = "rgba(151409f2)",
            border_locked_active = colors.yellow,
            border_locked_inactive = "rgba(151409f2)",
        },

        groupbar = {
            enabled = true,
            font_family = "JetBrains Mono Medium",
            font_size = 12,
            font_weight_active = "Bold",
            font_weight_inactive = "Normal",
            gradients = true,
            height = 20,
            indicator_gap = 0,
            indicator_height = 0,
            stacked = false,
            priority = 3,
            render_titles = true,
            text_offset = 0,
            scrolling = true,
            -- Pill tabs: solid fills, fully rounded, detached from the window edge.
            rounding = 4,
            round_only_edges = true,
            gradient_rounding = 4,
            gradient_round_only_edges = true,
            text_color = "rgba(151409ff)",          -- dark text on the accent (active) tab
            text_color_inactive = colors.white,     -- light text on the dark inactive tabs
            col = {
                active = colors.magenta,
                inactive = "rgba(151409f2)",
                locked_active = colors.yellow,
                locked_inactive = "rgba(151409f2)",
            },
            gaps_in = 2,
            gaps_out = 0,
            keep_upper_gap = false,
        },
    },

    dwindle = {
        force_split = 2,
        preserve_split = true,
        use_active_for_splits = true,
        -- special_scale_factor dropped: deprecated in 0.57, and no longer read
        -- by the dwindle layout.
    },

    decoration = {
        rounding = 16,

        blur = {
            enabled = true,
            size = 8,
            passes = 2,
            xray = false,
            new_optimizations = true,
            noise = 0.0117,
            contrast = 0.8916,
            brightness = 0.8172,
            vibrancy = 0.1696,
            vibrancy_darkness = 0.0,
            special = false,
            popups = false,
            popups_ignorealpha = 0.2,
        },

        shadow = {
            enabled = false,
            range = 30,
            offset = "0 2",
            render_power = 4,
            scale = 1.0,
            color = colors.black,
        },

        dim_inactive = false,
        dim_strength = 0.5,
        dim_special = 0,
    },
})


----------------
---- ANIMATIONS ----
----------------

hl.config({ animations = { enabled = true } })

-- Curves (bezier = name, x1, y1, x2, y2)
hl.curve("linear",          { type = "bezier", points = { {0, 0},     {1, 1}   } })
hl.curve("md3_standard",    { type = "bezier", points = { {0.2, 0},   {0, 1}   } })
hl.curve("md3_decel",       { type = "bezier", points = { {0.05, 0.7},{0.1, 1} } })
hl.curve("md3_accel",       { type = "bezier", points = { {0.3, 0},   {0.8, 0.15} } })
hl.curve("menu_decel",      { type = "bezier", points = { {0.1, 1},   {0, 1}   } })
hl.curve("menu_accel",      { type = "bezier", points = { {0.38, 0.04}, {1, 0.07} } })
hl.curve("overshot",        { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.1} } })
hl.curve("crazyshot",       { type = "bezier", points = { {0.1, 1.5}, {0.76, 0.92} } })
hl.curve("hyprnostretch",   { type = "bezier", points = { {0.05, 0.9}, {0.1, 1.0} } })
hl.curve("fluent_decel",    { type = "bezier", points = { {0.1, 1},   {0, 1}   } })
hl.curve("easeInOutCirc",   { type = "bezier", points = { {0.85, 0}, {0.15, 1} } })
hl.curve("easeOutCirc",     { type = "bezier", points = { {0, 0.55}, {0.45, 1} } })
hl.curve("easeOutExpo",     { type = "bezier", points = { {0.16, 1}, {0.3, 1} } })

-- Animations (leaf, speed, curve, optional style)
hl.animation({ leaf = "windows",        enabled = true, speed = 3,   bezier = "md3_decel", style = "popin 60%" })
hl.animation({ leaf = "windowsIn",      enabled = true, speed = 3,   bezier = "md3_decel", style = "popin 60%" })
hl.animation({ leaf = "windowsOut",     enabled = true, speed = 3,   bezier = "md3_accel", style = "popin 60%" })
hl.animation({ leaf = "border",         enabled = true, speed = 10,  bezier = "default" })
hl.animation({ leaf = "fade",           enabled = true, speed = 2.5, bezier = "md3_decel" })
hl.animation({ leaf = "workspaces",     enabled = true, speed = 7,   bezier = "fluent_decel", style = "slidevert" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 3, bezier = "md3_decel", style = "slidevert" })
hl.animation({ leaf = "layersIn",       enabled = true, speed = 3,   bezier = "menu_decel", style = "slide 10%" })
hl.animation({ leaf = "layersOut",      enabled = true, speed = 1.6, bezier = "menu_accel", style = "slide 10%" })
hl.animation({ leaf = "fadeLayersIn",   enabled = true, speed = 3,   bezier = "menu_decel" })
hl.animation({ leaf = "fadeLayersOut",  enabled = true, speed = 1.6, bezier = "menu_accel" })


---------------
---- MISC ----
---------------

hl.config({
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        focus_on_activate = true,
        allow_session_lock_restore = true,
        initial_workspace_tracking = true,
        mouse_move_enables_dpms = true,
        key_press_enables_dpms = true,
        close_special_on_empty = true,
        vrr = true,
        middle_click_paste = true,
        enable_swallow = false,
        session_lock_xray = true,
        animate_manual_resizes = false,
        animate_mouse_windowdragging = false,
    },

    cursor = {
        zoom_factor = 1.0,
        zoom_rigid = false,
        no_hardware_cursors = false,
        min_refresh_rate = 24,
        hotspot_padding = 1,
        inactive_timeout = 0,
    },

    binds = {
        allow_workspace_cycles = true,
        allow_pin_fullscreen = true,
        scroll_event_delay = 0,
        hide_special_on_workspace_change = false,
    },

    ecosystem = {
        no_update_news = true,
        no_donation_nag = true,
        enforce_permissions = false,
    },

    debug = {
        disable_logs = false,
    },
})

-- >>> quickshell:managed:begin v1 - written by Settings -> Hyprland. Edits here are overwritten; put your own Lua above.
hl.config({ input = { touchpad = { natural_scroll = false } } })  --@k input:touchpad:natural_scroll
-- <<< quickshell:managed:end

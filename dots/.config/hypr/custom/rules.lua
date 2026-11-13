-- Your window and layer rules go here. Loaded after hyprland/rules.lua.

require("hyprland.lib")
if is_file_exists(HOME .. "/.config/hypr/custom/variables.lua") then
    require("custom.variables")
end

-- Waydroid multi-window exposes each Android package as its own toplevel. Its
-- compositor owns a fixed 1920x1080 buffer on this system, so forcing an
-- arbitrary host size crops landscape apps. Keep the default native size for
-- unknown/orientation-flexible packages and only compact the known portrait
-- apps whose Android frame is 464x824 on this 180dpi setup.
hl.window_rule({
    match = {
        class = "^waydroid\\.(com\\.android\\.settings|com\\.android\\.documentsui|com\\.android\\.calculator2|com\\.android\\.deskclock|com\\.whatsapp|com\\.damarkets\\.portal\\.webpreview|com\\.instagram\\.android|com\\.google\\.android\\.apps\\.messaging|com\\.metrolist\\.music|com\\.google\\.android\\.contacts|com\\.x8bit\\.bitwarden|com\\.looker\\.droidify|org\\.kde\\.kdeconnect_tp|org\\.lineageos\\.(recorder|jelly|eleven|etar|aperture)|org\\.adaway|moe\\.shizuku\\.privileged\\.api|wedl\\.yqva\\.dlu\\.y\\.ev)$",
    },
    float = true,
    center = true,
    size = { "488", "842" },
})

-- Landscape games (for example Alto and Infinitode 2) retain the Android
-- display-sized surface so their 1920x1080 buffer is not cropped.
hl.window_rule({
    match = { class = "^waydroid\\..*$" },
    float = true,
    center = true,
})

-- Keep workspaces 1-10 alive even when they are empty, so an empty gap can sit between
-- the ones you actually use: Hyprland deletes an empty workspace the moment you leave
-- it, so without this a gap only existed while you stood on it. A workspace rule with
-- persistent = true keeps it alive.
--
-- The number row is group-relative (workspaceGroupSize), so the ten slots of the first
-- group are 1-10; those are the ones kept here. The later groups are not: Super+1 from
-- workspace 13 lands on 11, but 11 is deleted again once you leave it.
--
-- Workspace rules replace rather than merge, so the monitor field is repeated here:
-- lib/init.lua sets monitor = "" on every workspace so they float freely, and that
-- rule is the one being replaced.
local PERSISTENT_WORKSPACES = 10
for ws = 1, PERSISTENT_WORKSPACES do
    hl.workspace_rule({ workspace = tostring(ws), monitor = "", persistent = true })
end

-- The file manager is a FloatingWindow to Qt, which Hyprland floats on map. A tile rule in
-- hyprland/rules.lua loses to something later in the load, so it is declared last, here.
hl.window_rule({match = {title = "^(ii File Manager)$" }, tile = true})

-- ii-iced (Rust shell, ~/Projects/ii-iced). Own namespaces, so none of the Quickshell patterns above
-- apply (some of them, like bar[0-9]*, also match as substrings). Blur is the compositor's job.
for _, ns in ipairs({ "ii-iced:bar", "ii-iced:sidebar", "ii-iced:island", "ii-iced:selector", "ii-iced:overview" }) do
    hl.layer_rule({ match = { namespace = "^" .. ns .. "$" }, blur = true })
    hl.layer_rule({ match = { namespace = "^" .. ns .. "$" }, ignore_alpha = 0.2 })
end
hl.layer_rule({ match = { namespace = "^ii-iced:wallpaper$" }, blur = false })
hl.layer_rule({ match = { namespace = "^ii-iced:bar$" }, animation = "slide", order = 5 })
hl.layer_rule({ match = { namespace = "^ii-iced:island$" }, no_anim = true })
-- Windows the shell spawns are ordinary windows: Super+drag moves them, Super+Q closes them
hl.window_rule({ match = { class = "^ii-iced-settings$" }, float = true })
hl.window_rule({ match = { class = "^ii-iced-settings$" }, center = true })
hl.window_rule({ match = { class = "^ii-iced-settings$" }, size = { "820", "560" } })

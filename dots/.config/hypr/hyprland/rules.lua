-- ######## Window rules ########

-- Disable blur for xwayland context menus
hl.window_rule({match = {class = "^()$", title = "^()$" },                   no_blur = true })


-- Floating
-- Tablet Family shell tools are regular xdg toplevels, so they behave like apps on the
-- empty workspace selected by GlobalStates rather than like layer-shell overlays.
--
-- Deliberately NOT floated: they were, and the result was a shell tool sitting in a
-- centred box on an otherwise empty workspace while every real application on the same
-- workspace fills it. Tiled, they take the whole work area — which is what "open the
-- Keybinds app" should look like — and they still respect the bar's and the dock's
-- reserved edges, which a maximised floating window would have to be told about.
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      center = true})
-- The file manager is a FloatingWindow to Qt, which Hyprland floats on map. Rules for it
-- here do not stick (something later in the load overrides them), so the tile rule that
-- works is declared last, in custom/rules.lua.
-- The notes app is a real toplevel, not a layer surface: it belongs to a workspace
-- and a click elsewhere must not dismiss it. Floated and centred so it opens as a
-- document window rather than taking over the tile layout.
hl.window_rule({match = {title = "^(ii Notes)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Notes)$" },                           center = true})
hl.window_rule({match = {title = "^(ii Notes)$" },                           size = "1500 940"})
-- The clock app, like the notes app: a real toplevel that floats, centred. Usage, Modes
-- and EasyEffects are built from the clock's parts and open at its size, so the
-- whole-app windows read as one family.
hl.window_rule({match = {title = "^(ii Clock)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Clock)$" },                           center = true})
-- Grit: the habit tracker and focus timer, the same kind of toplevel as the clock.
hl.window_rule({match = {title = "^(ii Grit)$" },                            float = true})
hl.window_rule({match = {title = "^(ii Grit)$" },                            center = true})
hl.window_rule({match = {title = "^(ii Calculator)$" },                      float = true})
hl.window_rule({match = {title = "^(ii Calculator)$" },                      center = true})
hl.window_rule({match = {title = "^(ii EasyEffects)$" },                     float = true})
hl.window_rule({match = {title = "^(ii EasyEffects)$" },                     center = true})
hl.window_rule({match = {title = "^(ii Usage)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Usage)$" },                           center = true})
hl.window_rule({match = {title = "^(ii Downloads)$" },                       float = true})
hl.window_rule({match = {title = "^(ii Downloads)$" },                       center = true})
hl.window_rule({match = {title = "^(ii Mixer)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Mixer)$" },                           center = true})
hl.window_rule({match = {title = "^(ii Soundscapes)$" },                     float = true})
hl.window_rule({match = {title = "^(ii Soundscapes)$" },                     center = true})
hl.window_rule({match = {title = "^(ii Packages)$" },                        float = true})
hl.window_rule({match = {title = "^(ii Packages)$" },                        center = true})
hl.window_rule({match = {title = "^(ii Bluetooth)$" },                       float = true})
hl.window_rule({match = {title = "^(ii Bluetooth)$" },                       center = true})
hl.window_rule({match = {title = "^(ii Patchbay)$" },                        float = true})
hl.window_rule({match = {title = "^(ii Patchbay)$" },                        center = true})
hl.window_rule({match = {title = "^(ii Torrents)$" },                        float = true})
hl.window_rule({match = {title = "^(ii Torrents)$" },                        center = true})
hl.window_rule({match = {title = "^(ii Music)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Music)$" },                           center = true})
hl.window_rule({match = {title = "^(ii Monitor)$" },                         float = true})
hl.window_rule({match = {title = "^(ii Monitor)$" },                         center = true})
hl.window_rule({match = {title = "^(ii Anki)$" },                            float = true})
hl.window_rule({match = {title = "^(ii Anki)$" },                            center = true})
hl.window_rule({match = {title = "^(ii Books)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Books)$" },                           center = true})
hl.window_rule({match = {class = "^(org.pwmt.zathura|sioyek)$" },             fullscreen = true})
hl.window_rule({match = {title = "^(ii Mediator)$" },                        float = true})
hl.window_rule({match = {title = "^(ii Mediator)$" },                        center = true})
hl.window_rule({match = {title = "^(ii Quran)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Quran)$" },                           center = true})
hl.window_rule({match = {title = "^(ii Diwan)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Diwan)$" },                           center = true})
hl.window_rule({match = {title = "^(ii Modes)$" },                           float = true})
hl.window_rule({match = {title = "^(ii Modes)$" },                           center = true})
hl.window_rule({match = {title = "^(ii System Health)$" },                   float = true})
hl.window_rule({match = {title = "^(ii System Health)$" },                   center = true})
-- The throwaway mirror the shell opens only so a phone's lockscreen can be
-- dismissed from here. It lives for a few seconds, so it must not be tiled
-- into the current layout.
hl.window_rule({match = {title = "^(ii-phone-unlock)$" },                    float = true})
hl.window_rule({match = {title = "^(ii-phone-unlock)$" },                    center = true})
-- The scrcpy window the Phone sidebar embeds. It is a real window kept exactly
-- under a cut-out in the panel's input region, which is what makes touches and
-- the keyboard reach the phone natively; the panel paints the captured picture
-- over it, so it is never actually seen and every decoration below would be
-- work thrown away. It opens on a hidden special workspace and the shell moves
-- it into place, so it never flashes through the tiling layout on the way in.
-- Off the monitor rather than on a special workspace: `silent` is not read in
-- any spelling the Lua parser accepts without complaint, so parking it there
-- pulled an empty scratchpad into view — overlay and all — on every start. The
-- offset is relative to the monitor and is not clamped, so nothing is ever seen
-- until the shell moves it under the panel's cut-out.
hl.window_rule({match = {title = "^(ii-phone-embed-)(.*)$" },               move = "9000 9000"})
hl.window_rule({match = {title = "^(ii-phone-embed-)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(ii-phone-embed-)(.*)$" },               no_initial_focus = true})
hl.window_rule({match = {title = "^(ii-phone-embed-)(.*)$" },               no_anim = true})
hl.window_rule({match = {title = "^(ii-phone-embed-)(.*)$" },               no_blur = true})
hl.window_rule({match = {title = "^(ii-phone-embed-)(.*)$" },               no_shadow = true})
hl.window_rule({match = {title = "^(Open File)(.*)$" },                      float = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  center = true})
hl.window_rule({match = {title = "^(Select a File)(.*)$" },                  float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               center = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               float = true})
hl.window_rule({match = {title = "^(Choose wallpaper)(.*)$" },               size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(Open Folder)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(Select the mod file to import)(.*)$" },  center = true}) -- Gale
hl.window_rule({match = {title = "^(Select the mod file to import)(.*)$" },  float = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Save As)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        center = true})
hl.window_rule({match = {title = "^(Library)(.*)$" },                        float = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    center = true})
hl.window_rule({match = {title = "^(File Upload)(.*)$" },                    float = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to save)$" },                  float = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  center = true})
hl.window_rule({match = {title = "^(.*)(wants to open)$" },                  float = true})
hl.window_rule({match = {class = "^(blueberry\\.py)$" },                     float = true})
hl.window_rule({match = {class = "^(guifetch)$" },                           float = true}) -- FlafyDev/guifetch
hl.window_rule({match = {class = "^(pavucontrol)$" },                        float = true})
hl.window_rule({match = {class = "^(pavucontrol)$" },                        size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(pavucontrol)$" },                        center = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         float = true})
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(org.pulseaudio.pavucontrol)$" },         center = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               float = true})
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })
hl.window_rule({match = {class = "^(nm-connection-editor)$" },               center = true})
hl.window_rule({match = {class = ".*plasmawindowed.*" },                     float = true})
hl.window_rule({match = {class = "kcm_.*" },                                  float = true})
hl.window_rule({match = {class = ".*bluedevilwizard" },                      float = true})
hl.window_rule({match = {title = ".*Welcome.*" },                              float = true})
hl.window_rule({match = {title = ".*Settings.*" },                             float = true, no_blur = false})
hl.window_rule({match = {title = ".*Shell conflicts.*" },                    float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, float = true})
hl.window_rule({match = {class = "org.freedesktop.impl.portal.desktop.kde" }, size = {"(monitor_w*0.60)", "(monitor_h*0.65)"} })
hl.window_rule({match = {class = "^(Zotero)$" },                             float = true})
hl.window_rule({match = {class = "^(Zotero)$" },                             size = {"(monitor_w*0.45)", "(monitor_h*0.45)"} })

-- Move
-- kde-material-you-colors spawns a window when changing dark/light theme. This is to make sure it doesn't interfere at all.
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, float = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, no_initial_focus = true})
hl.window_rule({match = {class = "^(plasma-changeicons)$" }, move = {999999, 999999}})
-- stupid dolphin copy
hl.window_rule({match = {title = "^(Copying — Dolphin)$" }, move = {40, 80}})

-- Tiling
hl.window_rule({match = {class = "^dev\\.warp\\.Warp$" }, tile = true})

-- Picture-in-Picture
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, keep_aspect_ratio = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, move = {"(monitor_w*0.73)", "(monitor_h*0.72)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, size = {"(monitor_w*0.25)", "(monitor_h*0.25)"} })
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, float = true})
hl.window_rule({match = {title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture)(.*)$" }, pin = true})

-- Screen sharing
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, float = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, pin = true})
hl.window_rule({match = {title = ".*is sharing (a window|your screen).*" }, move = {"(monitor_w*.5-window_w*.5)", "(monitor_h-window_h-12)"} })

-- --- Tearing ---
hl.window_rule({match = {title = ".*\\.exe" }, immediate = true})
hl.window_rule({match = {title = ".*minecraft.*" }, immediate = true})
hl.window_rule({match = {class = "^(steam_app).*" }, immediate = true})

-- No shadow for tiled windows
hl.window_rule({match = {float = 0 }, no_shadow = true})

-- ######## Workspace rules ########
hl.workspace_rule({ workspace = "special:special", gaps_out = 30 })

-- ######## Layer rules ########
hl.layer_rule({ match = { namespace = ".*" }, xray = false})
hl.layer_rule({ match = { namespace = "walker" }, no_anim = true})
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true})
hl.layer_rule({ match = { namespace = "overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "anyrun" }, no_anim = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, no_anim = true})
hl.layer_rule({ match = { namespace = "osk" }, no_anim = true})
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true})

hl.layer_rule({ match = { namespace = "noanim" }, no_anim = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, blur = true})
hl.layer_rule({ match = { namespace = "gtk-layer-shell" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "launcher" }, blur = true})
hl.layer_rule({ match = { namespace = "launcher" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "notifications" }, blur = true})
hl.layer_rule({ match = { namespace = "notifications" }, ignore_alpha = 0.69})
hl.layer_rule({ match = { namespace = "logout_dialog" }, blur = true}) -- wlogout

-- ags
hl.layer_rule({ match = { namespace = "sideleft.*" }, animation = "slide left"})
hl.layer_rule({ match = { namespace = "sideright.*" }, animation = "slide right"})
hl.layer_rule({ match = { namespace = "session[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "bar[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "barcorner.*" }, blur = true})
hl.layer_rule({ match = { namespace = "barcorner.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "dock[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "overview[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "cheatsheet[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideright[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "sideleft[0-9]*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "indicator.*" }, blur = true})
hl.layer_rule({ match = { namespace = "indicator.*" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, blur = true})
hl.layer_rule({ match = { namespace = "osk[0-9]*" }, ignore_alpha = 0.6})

-- Quickshell
-- Quickshell: illogical-impulse
hl.layer_rule({ match = { namespace = "quickshell.*" }, blur_popups = true})
hl.layer_rule({ match = { namespace = "quickshell.*" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell.*" }, ignore_alpha = 0.19})
hl.layer_rule({ match = { namespace = "quickshell.*" }, xray = false})
-- Background is a Bottom-layer wallpaper surface; compositor blur here causes double-blur
hl.layer_rule({ match = { namespace = "quickshell:background" }, blur = false})
-- Off until the shell pushes its own per-screen rule (Appearance.backgroundWidgetsRules): on for
-- see-through widgets, off on a screen whose widgets blur themselves under open windows
-- (a hard-edged patch otherwise). One namespace per screen: quickshell:backgroundWidgets:<screen>
hl.layer_rule({ match = { namespace = "quickshell:backgroundWidgets:.*" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:workspaceBlurOverlay" }, order = -1})
hl.layer_rule({ match = { namespace = "quickshell:workspaceBlurOverlay" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:workspaceBlurOverlay" }, ignore_alpha = 0.0})
hl.layer_rule({ match = { namespace = "quickshell:workspaceBlurOverlay" }, animation = "fade"})
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide", order = 5})
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:notes" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:notes" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "quickshell:notes" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%", order = 10})
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true})
-- Lower order is drawn on top: keeps the popup over the dock, bar and corner surfaces during its slide.
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade", order = -2})
hl.layer_rule({ match = { namespace = "quickshell:idleDim" }, above_lock = 1, no_anim = true, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:desktopMenu" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 0.3})
hl.layer_rule({ match = { namespace = "quickshell:floatingNotch" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:floatingNotch" }, ignore_alpha = 0.2})
hl.layer_rule({ match = { namespace = "quickshell:floatingNotch" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, ignore_alpha = 0.19})
hl.layer_rule({ match = { namespace = "quickshell:overview" }, xray = false})
-- overviewWindowTransition: window captures that scale with the wallpaper zoom
hl.layer_rule({ match = { namespace = "quickshell:overviewWindowTransition" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:overviewWindowTransition" }, xray = false})
hl.layer_rule({ match = { namespace = "quickshell:overviewWindowTransition" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:overviewWindowTransition" }, ignore_alpha = 0.0})
-- editMode: a screen-sized chrome whose only opaque pixels are its toolbar and panel.
-- Under the blanket `quickshell.*` rule its shadows and translucent edges were blurred,
-- and re-blurred on every frame the toolbar or the panel moved. Blur the opaque body only.
hl.layer_rule({ match = { namespace = "quickshell:editMode" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:editMode" }, ignore_alpha = 1})

hl.layer_rule({ match = { namespace = "quickshell:osk" }, animation = "slide bottom"})
hl.layer_rule({ match = { namespace = "quickshell:polkit" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 0.19})
hl.layer_rule({ match = { namespace = "quickshell:onScreenDisplay" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:onScreenDisplay" }, ignore_alpha = 0.19})
hl.layer_rule({ match = { namespace = "quickshell:.*[pP]opup" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:.*[pP]opup" }, ignore_alpha = 0.5})
hl.layer_rule({ match = { namespace = "quickshell:reloadPopup" }, animation = "slide"})
hl.layer_rule({ match = { namespace = "quickshell:regionSelector" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:session" }, ignore_alpha = 0})
-- Alt+Tab panel: animates itself (fade + scale); blur only behind the panel, not its shadow
hl.layer_rule({ match = { namespace = "quickshell:windowSwitcher" }, blur = true})
hl.layer_rule({ match = { namespace = "quickshell:windowSwitcher" }, ignore_alpha = 0.6})
hl.layer_rule({ match = { namespace = "quickshell:windowSwitcher" }, no_anim = true})
-- Alt+Tab's peek covers the screen under the island and the switcher panel, never over them
-- (in the overlay level, order 1 is drawn beneath the default 0). Named outside quickshell.*
-- so that blur rule misses it: blur under a fading peek pops off at the end of the fade.
hl.layer_rule({ match = { namespace = "ii-alt-tab-peek" }, no_anim = true})
hl.layer_rule({ match = { namespace = "ii-alt-tab-peek" }, order = 1})
-- The invisible surface that takes a click outside the switcher while a search waits with Alt
-- up, under the island and the panel in the same way.
hl.layer_rule({ match = { namespace = "ii-alt-tab-catcher" }, no_anim = true})
hl.layer_rule({ match = { namespace = "ii-alt-tab-catcher" }, order = 1})
-- The shell slides the sidebars itself (Appearance.animation.sidebarSlide), so the wallpaper
-- parallax can follow the same curve; a compositor slide on top would move them twice.
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, no_anim = true, order = 5})
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, no_anim = true, order = 5})
-- Tablet shade. Compositor blur is deliberately off: a layer rule can only switch blur on or
-- off, and its strength is the layer's own fade alpha, which the client cannot drive per frame.
-- The shade blurs a frozen screencopy of the desktop itself so the strength can follow the drag.
hl.layer_rule({ match = { namespace = "quickshell:tabletShade" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:tabletShade" }, no_anim = true})
-- App drawer, same reasoning: the shell's `ignore_alpha` rule makes compositor blur a
-- threshold, so it snapped in part-way through the open animation instead of ramping. The
-- drawer blurs its own frozen screencopy so the strength can follow the gesture.
hl.layer_rule({ match = { namespace = "quickshell:tabletAppDrawer" }, blur = false})
-- Recents animates itself: the app shrinks into its card and grows back into its window.
-- Without this the compositor ran its own close animation on the unmap, over a last frame
-- that is the app at full size — so every exit ended looking like the app had closed.
-- Blur is off for the same reason as the drawer: the surface draws its own backdrop.
hl.layer_rule({ match = { namespace = "quickshell:tabletRecents" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:tabletRecents" }, no_anim = true})
-- Live draw is ink on transparency: there is no surface of its own for a blur to sit
-- behind, and the strokes that are opaque cover whatever it would have blurred. The
-- blanket `quickshell.*` rule above would otherwise run a full-screen blur pass for as
-- long as a drawing is on the workspace.
hl.layer_rule({ match = { namespace = "quickshell:tabletLiveDraw" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:tabletLiveDraw" }, no_anim = true})
-- The desktop's live draw, same reasoning; and above every other overlay (lower order is
-- drawn on top), since annotating the screen means annotating the island and the OSK too.
hl.layer_rule({ match = { namespace = "quickshell:liveDraw" }, blur = false})
hl.layer_rule({ match = { namespace = "quickshell:liveDraw" }, no_anim = true, order = -5})
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, animation = "slide", order = 5})
hl.layer_rule({ match = { namespace = "quickshell:osk" }, order = -1})
-- Quickshell: waffles
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top"})
hl.layer_rule({ match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:onScreenDisplay" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wStartMenu" }, no_anim = true})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0})
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, no_anim = true})

-- Launchers need to be FAST
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true})

-- ---- Our window rules (standard) ----
-- Window, layer and workspace rules migrated from hyprland.conf and custom.conf.
-- Effects confirmed in the 0.56 Lua docs are active. Others are kept as TODO
-- comments with the original line, so check them before enabling.


---------------------
---- WINDOW RULES ----
---------------------

-- Float rules
hl.window_rule({ match = { class = "^(org.*|com.*|app.*|io.*|nwg-*)$" }, float = true })
hl.window_rule({ match = { title = "^(Open File)(.*)$" }, center = true })

hl.window_rule({ match = { class = "^(notification|error|splash|feh|mpv|eog|wpg|dialog|confirm)$" }, float = true })
hl.window_rule({ match = { class = "^(file_progress|viewnior|confirmreset|steam|waypaper|xarchiver)$" }, float = true })
hl.window_rule({ match = { class = "^(nm-connection-editor|yad|xdg-desktop-portal-gtk|papers-previewer)$" }, float = true })
hl.window_rule({ match = { class = "^(blueman-manager|trackma-gtk|pavucontrol)$" }, float = true })
hl.window_rule({ match = { class = "^(Signal|AppImageLauncher|wihotspot|zenity|syncplay)$" }, float = true })
hl.window_rule({ match = { title = "^(branchdialog|KDE Connect URL handler|Network Manager|Quickshell Settings)$" }, float = true })
hl.window_rule({ match = { class = "^(firefox)$", title = "^(Extension:.*)$" }, float = true })

-- Misc
hl.window_rule({ match = { class = "^(hyprland-share-picker)$" }, pin = true })
hl.window_rule({ match = { initial_class = "^(firefox)$", initial_title = "^Extension: .* - Mozilla Firefox$" }, float = true })

-- Picture-in-picture
hl.window_rule({ match = { title = "^([Pp]icture[-\\s]?[Ii]n[-\\s]?[Pp]icture).*$" }, float = true, pin = true, border_size = 0 })
-- TODO: PiP position and size used move/size with monitor math, and no_initial_focus and keep_aspect_ratio.
-- Original:
-- windowrule = match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$, move (monitor_w*.735) (monitor_h*.065)
-- windowrule = match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture)(.*)$, size (monitor_w*.25) (monitor_h*.25)
-- windowrule = match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture).*$, keep_aspect_ratio 1
-- windowrule = match:title ^([Pp]icture[-\s]?[Ii]n[-\s]?[Pp]icture).*$, no_initial_focus 0

-- Dialogs
hl.window_rule({ match = { title = "^(Open File|Select a File|Choose wallpaper|Open Folder|Save As|Library|File|Confirm).*$" }, float = true, center = true })
-- TODO: tile rules for quickshell and Nautilus. Not verified in Lua yet.
-- windowrule = match:title ^(quickshell)$, tile 1
-- windowrule = match:class ^(org.gnome.Nautilus)$, tile 1

-- Media
-- TODO: keep_aspect_ratio for mpv. Not verified in Lua yet.
-- windowrule = match:class ^(mpv)$, keep_aspect_ratio 1

-- Idle inhibit
hl.window_rule({ match = { class = "^(com.usebottles.bottles|Bottles)$" }, idle_inhibit = "fullscreen" })
hl.window_rule({ match = { class = "^(firefox)$" }, idle_inhibit = "fullscreen" })
hl.window_rule({ match = { title = "^(Picture-in-Picture)$" }, idle_inhibit = "always" })

-- Visual tweaks
hl.window_rule({ match = { class = "^(org.gnome.Loupe)$" }, border_size = 0 })
-- Telegram: the conf suppressed "activatefocus". The Lua docs list "activate" as the suppressible event, so verify this one.
hl.window_rule({ match = { class = "^(org.telegram.desktop)$" }, suppress_event = "activate" })

-- Find and rename dialogs
-- TODO: "move onscreen cursor" is not verified in Lua yet.
hl.window_rule({ match = { title = "^(Find.*|Rename.*)$" }, float = true })
-- windowrule = match:title ^(Find.*|Rename.*)$, move onscreen cursor

hl.window_rule({ match = { title = "^(Question.*)$" }, stay_focused = true })

-- Tearing / immediate
hl.window_rule({ match = { title = ".*\\.exe$" }, immediate = true })
hl.window_rule({ match = { title = ".*minecraft.*" }, immediate = true })
hl.window_rule({ match = { class = "^(steam_app).*" }, immediate = true })

-- No shadow for tiled windows
hl.window_rule({ match = { float = false }, no_shadow = true })

-- Opacity rules (commented out in the conf, kept for reference)
-- windowrule = match:class .*, opacity 0.89 0.89 override
-- windowrule = match:class ^(thunar|geany|org.pwmt.zathura|sioyek|pavucontrol|org.telegram.desktop|discord|vesktop|WebCord|Spotify|quickshell)$, opacity 0.85 0.85
-- windowrule = match:title ^(Find)$, opacity 0.75 0.75


---------------------
---- LAYER RULES ----
---------------------
-- Layer rule effect names other than no_anim are not verified in Lua yet.
-- They use the same names as the conf. If one fails, hyprctl configerrors will show it.

-- Rofi
hl.layer_rule({ match = { namespace = "^(rofi)$" }, blur = true, ignore_alpha = 0.1 })

-- GTK layer-shell surfaces (bars, panels, launchers)
hl.layer_rule({ match = { namespace = "^(gtk-layer-shell)$" }, blur = true })

-- Hyprpicker
hl.layer_rule({ match = { namespace = "^(hyprpicker)$" }, no_anim = true })

-- Quickshell (launchers must be fast)
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur_popups = true })
hl.layer_rule({ match = { namespace = "quickshell:.*" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:.*" }, ignore_alpha = 0.7 })
hl.layer_rule({ match = { namespace = "quickshell:bar" }, animation = "slide" })
hl.layer_rule({ match = { namespace = "quickshell:actionCenter" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:cheatsheet" }, animation = "slide bottom" })
hl.layer_rule({ match = { namespace = "quickshell:dock" }, animation = "slide bottom" })
hl.layer_rule({ match = { namespace = "quickshell:screenCorners" }, animation = "popin 120%" })
hl.layer_rule({ match = { namespace = "quickshell:lockWindowPusher" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:notificationPopup" }, animation = "fade" })
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:overlay" }, ignore_alpha = 1 })
hl.layer_rule({ match = { namespace = "quickshell:overview" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:osk" }, animation = "slide bottom" })
hl.layer_rule({ match = { namespace = "quickshell:osk" }, order = -1 })
hl.layer_rule({ match = { namespace = "quickshell:polkit" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:popup" }, xray = false }) -- No weird color for bar tooltips
hl.layer_rule({ match = { namespace = "quickshell:popup" }, ignore_alpha = 1 }) -- Same, needed in practice
hl.layer_rule({ match = { namespace = "quickshell:mediaControls" }, ignore_alpha = 1 })
hl.layer_rule({ match = { namespace = "quickshell:reloadPopup" }, animation = "slide" })
hl.layer_rule({ match = { namespace = "quickshell:regionSelector" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:screenshot" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:session" }, blur = true })
hl.layer_rule({ match = { namespace = "quickshell:session" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:session" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:sidebarRight" }, animation = "slide right" })
hl.layer_rule({ match = { namespace = "quickshell:sidebarLeft" }, animation = "slide left" })
hl.layer_rule({ match = { namespace = "quickshell:verticalBar" }, animation = "slide" })
hl.layer_rule({ match = { namespace = "quickshell:wallpaperSelector" }, animation = "slide top" })
hl.layer_rule({ match = { namespace = "quickshell:wNotificationCenter" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:wOnScreenDisplay" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:wStartMenu" }, no_anim = true })
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, ignore_alpha = 0 })
hl.layer_rule({ match = { namespace = "quickshell:wTaskView" }, no_anim = true })

-- Launchers need to be fast
hl.layer_rule({ match = { namespace = "gtk4-layer-shell" }, no_anim = true })


-----------------------
---- WORKSPACE RULES ----
-----------------------

-- Drop-down terminal: launches the first time the special:drop workspace is created empty.
-- The on_created_empty workspace rule is deprecated in 0.57; the workspace.created
-- event with an is_empty check is the replacement.
hl.on("workspace.created", function(ws)
    if ws and ws.is_empty and ws.name == "special:drop" then
        hl.exec_cmd("terminal --drop")
    end
end)

---------------------------
---- TRANSPARENCY ----
---------------------------
-- Quickshell settings > Transparency runs "switchwall.sh --trans", which writes transparency.lua.
-- These are the opacity rules that the old hyprland.conf toggled.
local okTransparency, transparency = pcall(require, "transparency")
if okTransparency and transparency.enabled then
    hl.window_rule({ name = "opacity-all", match = { class = ".*" }, opacity = "0.89 0.89 override" })
    hl.window_rule({ name = "opacity-apps", match = { class = "^(thunar|geany|org.pwmt.zathura|sioyek|pavucontrol|org.telegram.desktop|discord|vesktop|WebCord|Spotify|quickshell)$" }, opacity = "0.85 0.85" })
    hl.window_rule({ name = "opacity-find", match = { title = "^(Find)$" }, opacity = "0.75 0.75" })
end

-- Floating terminal (SUPER+SHIFT+Return runs `terminal --float`): float and center it.
hl.window_rule({ match = { class = "^(Alacritty-float)$" }, float = true, center = true })

-- Default variables
-- Copy these to ~/.config/hypr/custom/variables.lua to make changes in a dotfiles-update-friendly manner

-- The folder within ~/.config/quickshell containing the config
hl.env("qsConfig", "ii")

-- Apps
-- PULL REQUESTS ADDING MORE WILL NOT BE ACCEPTED, CONFIG FOR YOURSELF
terminal = "alacritty"
fileManager = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'ii-files' 'qs -c $qsConfig ipc call fileManager toggle' 'thunar' 'nautilus' 'dolphin' 'nemo' 'alacritty -e yazi'"
browser = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'firefox' 'google-chrome-stable' 'zen-browser' 'brave' 'chromium' 'microsoft-edge-stable' 'opera' 'librewolf'"
codeEditor = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'windsurf' 'antigravity' 'code' 'codium' 'cursor' 'zed' 'zedit' 'zeditor' 'kate' 'gnome-text-editor' 'emacs' 'command -v nvim && alacritty -e nvim' 'command -v micro && alacritty -e micro'"
officeSoftware = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'wps' 'onlyoffice-desktopeditors' 'libreoffice'"
textEditor = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'qs -c $qsConfig ipc call editor toggle' 'scribe' 'geany' 'kate' 'gnome-text-editor' 'emacs'"
volumeMixer = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'qs -c $qsConfig ipc call mixer toggle' 'pavucontrol-qt' 'pavucontrol'"
settingsApp = "XDG_CURRENT_DESKTOP=gnome ~/.config/hypr/hyprland/scripts/launch_first_available.sh 'qs -c $qsConfig ipc call settings toggle' 'systemsettings' 'gnome-control-center' 'better-control'"
taskManager = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'qs -c $qsConfig ipc call monitor toggle' 'gnome-system-monitor' 'plasma-systemmonitor --page-name Processes' 'command -v btop && alacritty -e btop'"

workspaceGroupSize = 10

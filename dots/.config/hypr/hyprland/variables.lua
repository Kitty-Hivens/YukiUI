-- Default variables
-- Copy these to ~/.config/hypr/custom/variables.lua to make changes in a dotfiles-update-friendly manner

-- The folder within ~/.config/quickshell containing the config
hl.env("qsConfig", "yuki")

-- Apps
-- PULL REQUESTS ADDING MORE WILL NOT BE ACCEPTED, CONFIG FOR YOURSELF
terminal = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'foot' 'kitty' 'alacritty' 'wezterm' 'konsole' 'kgx' 'uxterm' 'xterm'"
fileManager = "~/.config/hypr/hyprland/scripts/launch_filemanager.sh 'dolphin' 'nautilus' 'nemo' 'thunar' 'kitty fish -c yazi'"
browser = "~/.config/hypr/hyprland/scripts/launch_first_available.sh --mime x-scheme-handler/http 'google-chrome-stable' 'zen-browser' 'firefox' 'brave' 'chromium' 'microsoft-edge-stable' 'opera' 'librewolf'"
codeEditor = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'windsurf' 'antigravity' 'code' 'codium' 'cursor' 'zed' 'zedit' 'zeditor' 'kate' 'gnome-text-editor' 'emacs' 'command -v nvim && kitty nvim' 'command -v micro && kitty micro'"
officeSoftware = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'wps' 'onlyoffice-desktopeditors' 'libreoffice'"
textEditor = "~/.config/hypr/hyprland/scripts/launch_first_available.sh --mime text/plain 'kate' 'gnome-text-editor' 'emacs'"
volumeMixer = "~/.config/hypr/hyprland/scripts/launch_settings.sh sound"
settingsApp = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'qs -p ~/.config/quickshell/$qsConfig/appearanceSettings.qml'"
taskManager = "~/.config/hypr/hyprland/scripts/launch_first_available.sh 'gnome-system-monitor' 'plasma-systemmonitor --page-name Processes' 'command -v btop && kitty fish -c btop'"

workspaceGroupSize = 10

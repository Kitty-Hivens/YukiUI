-- This file sources other files in `hyprland` and `custom` folders
-- You wanna add your stuff in files in `custom`

-- Internal stuff --
require("hyprland.lib")
require("hyprland.services")

-- Plugins --
require("hyprland.plugins")

-- Environment variables --
require("hyprland.env")
if is_file_exists(HOME .. "/.config/hypr/custom/env.lua") then
    require("custom.env")
end

-- Default configurations --
require("hyprland.execs")
require("hyprland.general")
require("hyprland.rules")
require("hyprland.colors")
require("hyprland.keybinds")

-- Shell overrides --
--
-- Sourced before `custom`, not after. What the shell writes here is the rule
-- set belonging to the environment that is up -- a default of that environment,
-- not a decree. Sourced last it beat everything a person had written for
-- themselves, and there was no way to disagree with it short of editing a file
-- the header of that same file says not to edit.
--
-- The environment's own rules come first, so a setting changed from the shell
-- still wins over what the environment asks for by default. The file is
-- written by the shell each time an environment comes up, and is absent until
-- the shell has run once.
if is_file_exists(HOME .. "/.config/hypr/hyprland/shellOverrides/environment.lua") then
    require("hyprland.shellOverrides.environment")
end
require("hyprland.shellOverrides.main")

-- Custom configurations --
--
-- Yours, and last, so they win.
if is_file_exists(HOME .. "/.config/hypr/custom/execs.lua") then
    require("custom.execs")
end
if is_file_exists(HOME .. "/.config/hypr/custom/general.lua") then
    require("custom.general")
end
if is_file_exists(HOME .. "/.config/hypr/custom/rules.lua") then
    require("custom.rules")
end
if is_file_exists(HOME .. "/.config/hypr/custom/keybinds.lua") then
    require("custom.keybinds")
end

-- nwg-displays support --
if is_file_exists(HOME .. "/.config/hypr/workspaces.lua") then
    require("workspaces")
end
if is_file_exists(HOME .. "/.config/hypr/monitors.lua") then
    require("monitors")
end

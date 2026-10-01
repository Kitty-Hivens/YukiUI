-- Hyprland plugins YukiUI builds on this machine (package yuki-hyprland-plugins).
--
-- A plugin is loaded only once it has been built, so a machine without the
-- package starts without it instead of with a config error. Loading an already
-- loaded plugin again on a config reload does nothing.

local dir = "/usr/lib/yuki-hyprland-plugins/"

-- minimize: what the shell's minimising needs from inside the compositor.
-- layer-refocus: a panel that appears under a still pointer gets the pointer.
-- press-report: tells the shell where each press lands, so a panel closes on a
-- click outside it and the click still reaches what it landed on.
local plugins = { "minimize", "layer-refocus", "press-report" }

for _, name in ipairs(plugins) do
    local path = dir .. name .. ".so"
    if is_file_exists(path) then
        hl.plugin.load(path)
    end
end

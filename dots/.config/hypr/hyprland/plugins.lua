-- Hyprland plugins YukiUI builds on this machine (package yuki-hyprland-plugins).
--
-- A plugin is loaded only once it has been built, so a machine without the
-- package starts without it instead of with a config error. Loading an already
-- loaded plugin again on a config reload does nothing.

local dir = "/usr/lib/yuki-hyprland-plugins/"

-- minimize: what the shell's minimising and maximising need from inside the
-- compositor.
-- layer-refocus: a panel that appears under a still pointer gets the pointer.
-- press-report: tells the shell where each press lands, so a panel closes on a
-- click outside it and the click still reaches what it landed on.
-- drag-report: tells the shell when a window is moved or resized with the
-- mouse, which snapping a window to an edge needs.
-- capture-report: tells the shell which programs take the screen from the
-- compositor, which the compositor alone does not say.
-- data-control-v1: keeps a clipboard event of the protocol's second version
-- from clients of its first, which Hyprland 0.56 sends and which killed Wine's
-- clipboard. Not needed once Hyprland checks the version itself.
local plugins = { "minimize", "layer-refocus", "press-report", "drag-report", "capture-report", "data-control-v1" }

for _, name in ipairs(plugins) do
    local path = dir .. name .. ".so"
    if is_file_exists(path) then
        hl.plugin.load(path)
    end
end

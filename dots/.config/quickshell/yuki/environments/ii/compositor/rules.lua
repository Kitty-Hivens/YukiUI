-- Compositor rules of the Illogical Impulse environment.

-- Qt programs pick files through the portal, which is the shell's own picker:
-- the KDE platform theme's dialog belongs to another desktop. The theme reads
-- this once, as a program starts. Handed on to the user's services as well, as
-- the session hands on its variables as it starts, since programs started from
-- the shell take their environment from there; not by the test bench, whose
-- compositor runs inside the person's session.
hl.env("PLASMA_INTEGRATION_USE_PORTAL", "1")
if not os.getenv("YUKI_BENCH") then
    hl.exec_cmd("uwsm finalize PLASMA_INTEGRATION_USE_PORTAL")
end

-- Windows tile, so the keys that place them work on the layout: the split
-- ratio, a window taken out of the tiling and put back, Hyprland's own
-- maximise, and focus moved in a direction.
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Window: Float/Tile" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "Window: Maximize" })
for _, arrow in ipairs({ "Left", "Right", "Up", "Down" }) do
    hl.bind("SUPER + " .. arrow, hl.dsp.focus({ direction = arrow:sub(1, 1):lower() }), { description = "Window: Focus " .. arrow })
end

-- Touchpad gestures. Each environment has its own, since a gesture once made
-- cannot be taken back short of a reload: three fingers move the window under
-- them and a pinch makes it fullscreen, four switch workspaces sideways and
-- open the overview up or down.
hl.gesture({
    fingers = 3,
    direction = "swipe",
    action = "move"
})
hl.gesture({
    fingers = 3,
    direction = "pinch",
    action = "fullscreen"
})
hl.gesture({
    fingers = 4,
    direction = "horizontal",
    action = "workspace"
})
hl.gesture({
    fingers = 4,
    direction = "up",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})
hl.gesture({
    fingers = 4,
    direction = "down",
    action = function()
        hl.dispatch(hl.dsp.global("quickshell:overviewWorkspacesToggle"))
    end
})

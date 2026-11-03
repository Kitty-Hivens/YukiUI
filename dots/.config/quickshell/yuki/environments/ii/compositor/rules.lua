-- Compositor rules of the Illogical Impulse environment.

-- Qt programs pick files through the portal, which is the shell's own picker:
-- the KDE platform theme's dialog belongs to another desktop. The theme reads
-- this once, as a program starts. Listed for uwsm to hand on to the user's
-- services, where programs started from the shell take their environment
-- from: as the session starts, and again when the shell switches to here.
hl.env("PLASMA_INTEGRATION_USE_PORTAL", "1")
hl.env("UWSM_FINALIZE_VARNAMES", "PLASMA_INTEGRATION_USE_PORTAL")

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

-- A window that opens goes into the tiling, even one whose application
-- remembers having been closed maximised and asks for it again a moment after
-- it opens, as kitty does. Hyprland's maximise is a fullscreen of its own over
-- the layout, and the window looked like a floating one until it was grabbed.
-- Only that first request is dropped: a maximise asked for later, from a
-- title bar or with Super+D, still is one.
YUKI_JUST_OPENED = {}
hl.on("window.open", function(w)
    local address = w.address
    YUKI_JUST_OPENED[address] = true
    hl.timer(function()
        YUKI_JUST_OPENED[address] = nil
    end, { timeout = 1500, type = "oneshot" })
end)
hl.on("window.fullscreen", function(w)
    if not YUKI_JUST_OPENED[w.address] then
        return
    end
    YUKI_JUST_OPENED[w.address] = nil
    -- 1 is the maximise. A window asking for real fullscreen, a game or a
    -- player, is left to it.
    if w.fullscreen == 1 then
        hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = "address:" .. w.address }))
    end
end)

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

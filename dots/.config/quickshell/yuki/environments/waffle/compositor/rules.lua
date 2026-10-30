-- Compositor rules of the Waffle environment.

-- Qt programs keep the KDE platform theme's own file dialog until this
-- environment has a picker of its own, rather than the portal another
-- environment sends them to. 0 rather than unset: the theme reads it as a
-- number, once, as a program starts. Listed for uwsm to hand on to the user's
-- services, where programs started from the shell take their environment
-- from: as the session starts, and again when the shell switches to here.
hl.env("PLASMA_INTEGRATION_USE_PORTAL", "0")
hl.env("UWSM_FINALIZE_VARNAMES", "PLASMA_INTEGRATION_USE_PORTAL")

-- Focus by click, as on Windows 11, which this environment follows. The
-- pointer still reaches what it is over, scrolling included, but only a click
-- moves the keyboard. With focus following the pointer, the window a person
-- meant was lost on the way to the taskbar: crossing another window took focus
-- to it, so a click on the first window's button brought it up again instead
-- of minimising it.
hl.config({ input = { follow_mouse = 2 } })

-- Windows tile here, so the keys that place them work on the layout: the split
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

-- Compositor rules of the Waffle environment.

-- Focus by click, as on Windows 11, which this environment follows. The
-- pointer still reaches what it is over, scrolling included, but only a click
-- moves the keyboard. With focus following the pointer, the window a person
-- meant was lost on the way to the taskbar: crossing another window took focus
-- to it, so a click on the first window's button brought it up again instead
-- of minimising it.
hl.config({ input = { follow_mouse = 2 } })

-- Windows tile here, so the keys that place them work on the layout: the split
-- ratio, a window taken out of the tiling and put back, and Hyprland's own
-- maximise.
hl.bind("SUPER + Semicolon", hl.dsp.layout("splitratio -0.1"), { repeating = true })
hl.bind("SUPER + Apostrophe", hl.dsp.layout("splitratio +0.1"), { repeating = true })
hl.bind("SUPER + ALT + Space", hl.dsp.window.float({ action = "toggle" }), { description = "Window: Float/Tile" })
hl.bind("SUPER + D", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }),
    { description = "Window: Maximize" })

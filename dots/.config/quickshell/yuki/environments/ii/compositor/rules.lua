-- Compositor rules of the Illogical Impulse environment.

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

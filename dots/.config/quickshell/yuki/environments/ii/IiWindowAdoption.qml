import QtQuick
import Quickshell

import qs.core.services

// The windows another environment left, taken into this one's tiling as it
// comes up in that one's place. They stand as the other left them: floating,
// placed and tagged by a desktop of overlapping windows, which kept a tiled
// window under every one of them, since a floating window is always drawn over
// a tiled one.
//
// Only on a switch, not every time the shell starts: a window floated here on
// purpose stays floating. Every window on a workspace that is shown is let go
// of the other environment's tags, an X11 window told it is not maximised,
// and a floating one tiled unless it would float if it opened now: a dialog,
// a window pinned or fullscreen, or one a rule loaded now floats. Asked once
// the compositor runs under this environment's rules, and only with the
// minimize plugin to answer it: without it, a dialog could not be told apart
// and would be tiled, so nothing is.
Scope {
    id: root

    readonly property string lua: `
        local minimize = hl.plugin.minimize
        local shouldFloat = minimize and minimize.should_float
        for _, w in ipairs(hl.get_windows()) do
            local workspace = w.workspace
            if w.mapped and workspace and workspace.id >= 1 then
                local target = "address:" .. w.address
                for _, tag in ipairs({ "maximized", "snapped", "square", "bare" }) do
                    hl.dispatch(hl.dsp.window.tag({ tag = "-" .. tag, window = target }))
                end
                if w.xwayland and minimize and minimize.set_window_state then
                    minimize.set_window_state(w.address, false, true)
                end
                if shouldFloat and w.floating and not w.pinned and w.fullscreen == 0 and not shouldFloat(w.address) then
                    hl.dispatch(hl.dsp.window.float({ action = "disable", window = target }))
                end
            end
        end
    `

    Connections {
        target: Environments
        enabled: Environments.switchedFrom.length > 0

        function onRulesSettled() {
            Quickshell.execDetached(["hyprctl", "eval", root.lua]);
        }
    }
}

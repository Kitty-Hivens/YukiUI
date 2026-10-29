import QtQuick
import Quickshell

import qs.core.services

// The windows another environment left floating, taken into the tiling of an
// environment that tiles, as it comes up in that one's place: a floating
// window is always drawn over a tiled one, so a tiled window could never come
// up over them.
//
// Only on a switch, not every time the shell starts: a window floated on
// purpose stays floating. A floating window on a regular workspace is tiled
// unless it would float if it opened now: a dialog, a window pinned or
// fullscreen, or one a rule loaded now floats. Asked once the compositor runs
// under the new environment's rules, and only with the minimize plugin to
// answer it: without it, a dialog could not be told apart and would be tiled,
// so nothing is. What the environment before kept on the windows is its own
// to take back as it goes.
Scope {
    id: root

    readonly property string lua: `
        local minimize = hl.plugin.minimize
        local shouldFloat = minimize and minimize.should_float
        if not shouldFloat then
            return
        end
        for _, w in ipairs(hl.get_windows()) do
            local workspace = w.workspace
            if w.mapped and workspace and workspace.id >= 1 and w.floating and not w.pinned and w.fullscreen == 0
                    and not shouldFloat(w.address) then
                hl.dispatch(hl.dsp.window.float({ action = "disable", window = "address:" .. w.address }))
            end
        end
    `

    Connections {
        target: Environments
        enabled: Environments.switched

        function onRulesSettled() {
            Quickshell.execDetached(["hyprctl", "eval", root.lua]);
        }
    }
}

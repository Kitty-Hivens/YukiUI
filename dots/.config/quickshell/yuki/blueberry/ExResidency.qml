import QtQuick
import Quickshell
import Quickshell.Io

import qs.core

// How firmly the shell is held in memory.
//
// Panels kept built by keepReady open at once only while what they are made of
// is still in memory. A game that needs the memory pushed a good part of the
// shell out to swap, and the first thing opened after it was slow for that
// alone, so with keepReady on the shell's own unit is given more memory that is
// reclaimed only when nothing else is left to take. Applications are started in
// scopes of their own, see AppLaunch, so this is the shell's alone.
Scope {
    id: root

    /** What the session starts the shell with, see hypr/hyprland/execs.lua. */
    readonly property string startedWith: "350M"
    readonly property string keptWith: "768M"
    readonly property string wanted: Config.ready ? (Config.options.blueberry.keepReady ? root.keptWith : root.startedWith) : ""

    /**
     * The unit the shell runs in, when it is the one the session started it
     * as. A shell started by hand from a terminal runs in the terminal's unit,
     * whose memory is not the shell's to change.
     */
    property string unit: ""

    FileView {
        id: cgroup
        path: "/proc/self/cgroup"
        printErrors: false
        onLoaded: {
            const line = cgroup.text().split("\n").find(entry => entry.startsWith("0::")) ?? "";
            const name = line.trim().split("/").pop() ?? "";
            root.unit = /^app-.*quickshell.*\.(scope|service)$/.test(name) ? name : "";
        }
    }

    onWantedChanged: root.apply()
    onUnitChanged: root.apply()

    function apply() {
        if (root.unit.length === 0 || root.wanted.length === 0)
            return;
        setter.running = false;
        setter.command = ["systemctl", "--user", "set-property", "--runtime", root.unit, `MemoryLow=${root.wanted}`];
        setter.running = true;
    }

    // Another environment taking this one's place gets the shell as it was started.
    Component.onDestruction: {
        if (root.unit.length > 0 && root.wanted !== root.startedWith)
            Quickshell.execDetached(["systemctl", "--user", "set-property", "--runtime", root.unit, `MemoryLow=${root.startedWith}`]);
    }

    Process {
        id: setter
        onExited: exitCode => {
            if (exitCode !== 0)
                console.warn(`[ExResidency] systemctl could not set MemoryLow on ${root.unit}, status ${exitCode}`);
        }
    }
}

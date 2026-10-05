import QtQuick
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.functions

// Writes down what the touchpad gestures do, for this environment's compositor
// rules to read as they load, and has the compositor reload when that changed:
// a gesture once made cannot be taken back otherwise.
Scope {
    id: root

    // Where the rules read it, by XDG_STATE_HOME as they look for it: the
    // test bench gives its compositor and its shells a state folder of their
    // own and leaves HOME the person's.
    readonly property string path: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/yuki/gestures`
    readonly property var actions: ["search", "showDesktop", "notifications", "quickSettings", "maximize"]

    /** The lines for one count of fingers, as fingers, direction and action. */
    function linesFor(fingers: int, set): var {
        const mode = set?.mode ?? "none";
        if (mode === "workspaces")
            return [[fingers, "horizontal", "workspace"], [fingers, "up", "search"], [fingers, "down", "showDesktop"]];
        if (mode === "move")
            return [[fingers, "swipe", "move"], [fingers, "pinch", "fullscreen"]];
        if (mode !== "custom")
            return [];
        const lines = [];
        if (set.sideways === "workspace")
            lines.push([fingers, "horizontal", "workspace"]);
        for (const direction of ["up", "down"])
            if (root.actions.includes(set[direction]))
                lines.push([fingers, direction, set[direction]]);
        return lines;
    }

    readonly property string text: {
        const gestures = Config.options.experimental.gestures;
        const lines = [...root.linesFor(3, gestures.three), ...root.linesFor(4, gestures.four)];
        return lines.map(line => line.join("\t")).join("\n") + "\n";
    }

    // Once the settings have been read, not with the defaults before them,
    // and once a run of changes has stopped: each write that changes the
    // file reloads the compositor.
    onTextChanged: writeLater.restart()
    Component.onCompleted: writeLater.restart()
    Connections {
        target: Config
        function onReadyChanged() {
            writeLater.restart();
        }
    }

    Timer {
        id: writeLater
        interval: 600
        onTriggered: {
            if (!Config.ready)
                return;
            writer.command = ["bash", FileUtils.trimFileProtocol(Quickshell.shellPath("scripts/hyprland/state_reload.sh")), root.text, root.path];
            writer.running = true;
        }
    }

    Process {
        id: writer
    }
}

pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

Singleton {
    id: root

    function load() {}

    readonly property bool anyFullscreen: Hyprland.workspaces.values.some(ws =>
        ws.active && ws.toplevels.values.some(t => t.wayland?.fullscreen))

    /**
     * Whether a window is fullscreen on one particular screen.
     *
     * A workspace is active on its own monitor, so every monitor has one, and
     * asking whether any active workspace holds a fullscreen window asks about
     * all of them at once. Panels that step aside for a game were stepping aside
     * on every screen the moment a game went fullscreen on one of them, which on
     * a docked machine means the sidebar stops opening on the screen being
     * worked on. A panel is only in the way on the screen it is drawn on.
     */
    function fullscreenOn(monitorName) {
        if (!monitorName)
            return root.anyFullscreen;
        return Hyprland.workspaces.values.some(ws => ws.active
            && ws.monitor?.name === monitorName
            && ws.toplevels.values.some(t => t.wayland?.fullscreen));
    }

    readonly property bool engaged: Config.options.gameMode.active
        || (Config.options.gameMode.autoOnFullscreen && root.anyFullscreen)

    function setManual(on) {
        if (on === root.engaged) return;
        Config.options.gameMode.active = on;
    }

    readonly property bool visualEngaged: root.engaged && Config.options.gameMode.visual

    /**
     * The compositor settings the visual side overwrites.
     *
     * Written through `hyprctl eval`, which is the only way in on a machine whose
     * compositor is configured in lua: `hyprctl keyword` answers "keyword can't
     * work with non-legacy parsers", so the whole visual side of this mode was a
     * batch of rejected commands whose failure nobody read.
     *
     * Putting them back is not `hyprctl reload`, which re-reads the whole
     * compositor config. That rebuilds every keybind, so the shell's global
     * shortcuts are torn down and registered again, and a key still held across
     * that moment is released against a registration that never saw it pressed,
     * which fires the tap-to-open overview without a tap. Leaving a fullscreen
     * window is exactly when that happens, because leaving it is what ends the
     * mode. A reload also drops every other setting made while the session ran,
     * which is not this service's to discard.
     */
    readonly property list<string> visualKeywords: ["animations:enabled", "decoration:shadow:enabled", "decoration:blur:enabled", "general:gaps_in", "general:gaps_out", "general:border_size", "decoration:rounding"]

    /**
     * Shaped the way `hyprctl getoption` reports an option, so the mode's own
     * values and the ones read back off the compositor go through one formatter
     * and compare against each other without either being flattened first.
     *
     * Tearing is not among them. It belongs to the display, which is where it is
     * set and where it is turned off again, and a mode that switched it on for
     * the length of a game overrode that choice without saying so.
     */
    readonly property var visualValues: ({
        "animations:enabled": { "bool": false },
        "decoration:shadow:enabled": { "bool": false },
        "decoration:blur:enabled": { "bool": false },
        "general:gaps_in": { "int": 0 },
        "general:gaps_out": { "int": 0 },
        "general:border_size": { "int": 1 },
        "decoration:rounding": { "int": 0 }
    })

    /**
     * What the settings held before the mode took them over.
     *
     * Kept in the state file as well as in memory. A shell that restarts while
     * the mode is engaged reads the mode's own values back off the compositor and
     * has nothing else to go by, so a way back that does not survive the restart
     * is no way back at all, and the desktop stays flat until its config is
     * reloaded by hand.
     */
    property var visualBefore: null

    onVisualEngagedChanged: {
        if (root.visualEngaged)
            root.engageVisual();
        else
            root.disengageVisual();
    }

    /// One reported option as the lua the config takes.
    function luaLiteral(reported) {
        if (reported["bool"] !== undefined)
            return reported["bool"] ? "true" : "false";
        if (reported["int"] !== undefined)
            return String(reported["int"]);
        if (reported["float"] !== undefined)
            return String(reported["float"]);
        if (reported["css"] !== undefined) {
            // A gap reads back as "top right bottom left" and goes back as a
            // number or a table of those four names. The string it was read as is
            // refused outright.
            const parts = String(reported["css"]).trim().split(/\s+/).map(Number);
            if (parts.length === 4 && parts.every(part => !isNaN(part)))
                return `{ top = ${parts[0]}, right = ${parts[1]}, bottom = ${parts[2]}, left = ${parts[3]} }`;
            if (parts.length === 1 && !isNaN(parts[0]))
                return String(parts[0]);
        }
        const text = String(reported["str"] ?? reported["css"] ?? "");
        return `"${text.replace(/\\/g, "\\\\").replace(/"/g, "\\\"")}"`;
    }

    function luaTable(node) {
        const parts = [];
        for (const key of Object.keys(node)) {
            const value = node[key];
            parts.push(`${key} = ${typeof value === "string" ? value : root.luaTable(value)}`);
        }
        return `{ ${parts.join(", ")} }`;
    }

    /// `decoration:blur:enabled` is `decoration.blur.enabled`, so the option path
    /// is also the shape of the table it goes back in.
    function configCall(values) {
        const tree = ({});
        for (const key of root.visualKeywords) {
            const reported = values[key];
            if (reported === undefined)
                continue;
            const path = key.split(":");
            let node = tree;
            for (let depth = 0; depth < path.length - 1; depth++) {
                if (node[path[depth]] === undefined)
                    node[path[depth]] = ({});
                node = node[path[depth]];
            }
            node[path[path.length - 1]] = root.luaLiteral(reported);
        }
        return `hl.config(${root.luaTable(tree)})`;
    }

    function applyCommand(values) {
        return ["hyprctl", "eval", root.configCall(values)];
    }

    /// What an option amounts to, in a form two readings can be compared by. A
    /// gap of nought reads back as "0 0 0 0" and is written as a plain 0.
    function normalized(reported) {
        if (!reported)
            return "";
        if (reported["bool"] !== undefined)
            return reported["bool"] ? "1" : "0";
        if (reported["int"] !== undefined)
            return String(reported["int"]);
        if (reported["float"] !== undefined)
            return String(reported["float"]);
        if (reported["css"] !== undefined) {
            const parts = String(reported["css"]).trim().split(/\s+/);
            return parts.every(part => part === parts[0]) ? parts[0] : parts.join(" ");
        }
        return String(reported["str"] ?? "");
    }

    // Read before writing, every time it engages: a setting changed on the
    // desktop between one game and the next is otherwise put back to what it was
    // two games ago.
    function engageVisual() {
        captureProc.running = true;
    }

    function disengageVisual() {
        if (!root.visualBefore) {
            console.warn("[GameMode] nothing saved to put back, leaving the compositor settings alone");
            return;
        }
        Quickshell.execDetached(root.applyCommand(root.visualBefore));
        root.visualBefore = null;
        Persistent.states.gameMode.visualBefore = "";
    }

    Process {
        id: captureProc
        command: ["bash", "-c", `for key in ${root.visualKeywords.join(" ")}; do printf '%s\t' "$key"; hyprctl -j getoption "$key" | tr -d '\n'; printf '\n'; done`]
        stdout: StdioCollector {
            id: captureCollector
            onStreamFinished: {
                const found = ({});
                for (const line of captureCollector.text.split("\n")) {
                    const tab = line.indexOf("\t");
                    if (tab < 0)
                        continue;
                    const key = line.slice(0, tab);
                    let reported;
                    try {
                        reported = JSON.parse(line.slice(tab + 1));
                    } catch (error) {
                        continue;
                    }
                    // Whichever type the option turned out to be, kept as that
                    // type. Flattened to a string it could be neither compared
                    // with the mode's own values nor written back as lua.
                    for (const field of ["bool", "int", "float", "css", "str"]) {
                        if (reported[field] !== undefined) {
                            const kept = ({});
                            kept[field] = reported[field];
                            found[key] = kept;
                            break;
                        }
                    }
                }

                // Nothing is overwritten without a way back. Applying on a short
                // reading is how the settings used to be left with no record of
                // what they had been.
                if (!root.visualKeywords.every(key => found[key] !== undefined)) {
                    console.warn(`[GameMode] read back ${Object.keys(found).length} of ${root.visualKeywords.length} settings, leaving the compositor alone`);
                    return;
                }
                // Engaged and left again while the reading was in flight.
                if (!root.visualEngaged)
                    return;

                // What was read is only worth keeping if it is the desktop's own.
                // A shell that restarted while the mode was on reads back the
                // mode's values, and remembering those would restore them as if
                // they were the desktop, so the settings would never come back.
                const alreadyApplied = root.visualKeywords.every(key =>
                    root.normalized(found[key]) === root.normalized(root.visualValues[key]));
                if (!alreadyApplied) {
                    root.visualBefore = found;
                    Persistent.states.gameMode.visualBefore = JSON.stringify(found);
                }
                Quickshell.execDetached(root.applyCommand(root.visualValues));
            }
        }
    }

    Process {
        id: systemModeHolder
        running: root.engaged && Config.options.gameMode.system
        command: ["gamemoderun", "sleep", "infinity"]
        // Ending the mode is what normally ends this, and by then the switch that
        // asked for it already reads as off. Anything else means the governor is
        // not being held and the toggle would go on saying it is.
        onExited: (exitCode, exitStatus) => {
            if (root.engaged && Config.options.gameMode.system)
                console.warn(`[GameMode] gamemoderun ended with status ${exitCode}, the performance governor is not being held`);
        }
    }

    readonly property bool wallpaperPaused: root.engaged && Config.options.gameMode.wallpaper
    onWallpaperPausedChanged: root.setWallpaperPaused(wallpaperPaused)
    function setWallpaperPaused(paused) {
        Quickshell.execDetached([Directories.videoWallpaperPowerScriptPath, paused ? "stop" : "cont"]);
    }

    /// A wallpaper left stopped stays stopped. It is halted rather than asked, and
    /// nothing else in the session starts it again.
    Component.onDestruction: {
        if (root.wallpaperPaused)
            root.setWallpaperPaused(false);
    }

    function restoreSavedVisualBefore() {
        if (!Persistent.ready || root.visualBefore)
            return;
        const saved = Persistent.states.gameMode.visualBefore;
        if (!saved || saved.length === 0)
            return;
        try {
            root.visualBefore = JSON.parse(saved);
        } catch (error) {
            root.visualBefore = null;
        }
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreSavedVisualBefore();
        }
    }

    Component.onCompleted: {
        root.restoreSavedVisualBefore();
        if (root.visualEngaged) root.engageVisual();
        if (root.wallpaperPaused) root.setWallpaperPaused(true);
    }
}

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

    readonly property bool engaged: Config.options.gameMode.active
        || (Config.options.gameMode.autoOnFullscreen && root.anyFullscreen)

    function setManual(on) {
        if (on === root.engaged) return;
        Config.options.gameMode.active = on;
    }

    readonly property bool visualEngaged: root.engaged && Config.options.gameMode.visual

    /**
     * The keywords the visual side overwrites, and what they held beforehand.
     *
     * Putting them back used to be `hyprctl reload`, which re-reads the whole
     * compositor config. That rebuilds every keybind, so the shell's global
     * shortcuts are torn down and registered again; a key still held across
     * that moment is released against a registration that never saw it pressed,
     * and the tap-to-open overview fires without a tap. Leaving a fullscreen
     * window is exactly when that happens, because leaving it is what ends the
     * mode. A reload also drops every other keyword set while the session ran,
     * which is not this service's to discard.
     */
    readonly property list<string> visualKeywords: ["animations:enabled", "decoration:shadow:enabled", "decoration:blur:enabled", "general:gaps_in", "general:gaps_out", "general:border_size", "decoration:rounding"]

    /**
     * Tearing is not among these. It belongs to the display, which is where it is
     * set and where it is turned off again, and a mode that switched it on for
     * the length of a game overrode that choice without saying so.
     */
    readonly property var visualValues: ({
        "animations:enabled": "0",
        "decoration:shadow:enabled": "0",
        "decoration:blur:enabled": "0",
        "general:gaps_in": "0",
        "general:gaps_out": "0",
        "general:border_size": "1",
        "decoration:rounding": "0"
    })

    /** Filled the first time the mode engages, so it holds the desktop's own values. */
    property var visualBefore: null

    onVisualEngagedChanged: {
        if (root.visualEngaged)
            root.engageVisual();
        else
            root.disengageVisual();
    }

    function keywordBatch(values) {
        const parts = root.visualKeywords.map(key => `keyword ${key} ${values[key]}`);
        return ["bash", "-c", `hyprctl --batch "${parts.join("; ")}"`];
    }

    function engageVisual() {
        // Read before writing, or what gets remembered is the mode's own doing.
        if (root.visualBefore)
            Quickshell.execDetached(root.keywordBatch(root.visualValues));
        else
            captureProc.running = true;
    }

    function disengageVisual() {
        if (!root.visualBefore) {
            // Engaged before anything was read -- the shell started inside the
            // mode. The config's own values are the only ones left to go by.
            Quickshell.execDetached(["hyprctl", "reload"]);
            return;
        }
        Quickshell.execDetached(root.keywordBatch(root.visualBefore));
    }

    Process {
        id: captureProc
        command: ["bash", "-c", `for key in ${root.visualKeywords.join(" ")}; do printf '%s\t' "$key"; hyprctl -j getoption "$key" | tr -d '\n'; printf '\n'; done`]
        stdout: StdioCollector {
            id: captureCollector
            onStreamFinished: {
                const found = {};
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
                    // Whichever type the option turned out to be. A quad such as
                    // "4 4 4 4" comes back as one string and goes back as one.
                    for (const field of ["bool", "int", "float", "css", "str"]) {
                        if (reported[field] !== undefined) {
                            found[key] = String(reported[field]);
                            break;
                        }
                    }
                }
                const complete = Object.keys(found).length === root.visualKeywords.length;
                // What was read is only worth keeping if it is the desktop's own.
                // A shell that restarted while the mode was on reads back the mode's
                // own values, and remembering those would restore them as if they
                // were the desktop -- the settings would never come back.
                const alreadyApplied = root.visualKeywords.every(key => found[key] === root.visualValues[key]);
                if (complete && !alreadyApplied)
                    root.visualBefore = found;
                else if (!complete)
                    console.warn(`[GameMode] read back ${Object.keys(found).length} of ${root.visualKeywords.length} settings, leaving the reload as the way out`);
                if (!alreadyApplied)
                    Quickshell.execDetached(root.keywordBatch(root.visualValues));
            }
        }
    }

    Process {
        running: root.engaged && Config.options.gameMode.system
        command: ["gamemoderun", "sleep", "infinity"]
    }

    readonly property bool wallpaperPaused: root.engaged && Config.options.gameMode.wallpaper
    onWallpaperPausedChanged: root.setWallpaperPaused(wallpaperPaused)
    function setWallpaperPaused(paused) {
        Quickshell.execDetached(["bash", "-c",
            `"$HOME/.config/hypr/custom/scripts/video-wallpaper-power.sh" ${paused ? "stop" : "cont"}`])
    }

    Component.onCompleted: {
        if (root.visualEngaged) root.engageVisual();
        if (root.wallpaperPaused) root.setWallpaperPaused(true);
    }
}

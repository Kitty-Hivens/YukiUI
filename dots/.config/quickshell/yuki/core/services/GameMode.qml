pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

Singleton {
    id: root

    function load() {}

    /**
     * Whether a window is fullscreen anywhere.
     *
     * A window that has merely been told it is fullscreen does not count, and is
     * not meant to. The spoof bind leaves the compositor's own state at none, so
     * the window keeps its size and its place in the layout and only its own
     * behaviour changes, which leaves nothing for a panel to be in the way of.
     * The compositor reports fullscreen over the foreign toplevel protocol only
     * for windows it holds fullscreen itself, so that is what this reads.
     */
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
        return root.fullscreenMonitors.includes(monitorName);
    }

    /// The screens holding a fullscreen window right now, by name.
    readonly property var fullscreenMonitors: Hyprland.workspaces.values
        .filter(ws => ws.active && ws.toplevels.values.some(t => t.wayland?.fullscreen))
        .map(ws => ws.monitor?.name ?? "")
        .filter(name => name.length > 0)

    /**
     * Whether a game has held a screen long enough that the shell should give up
     * its windows on it, rather than merely stand aside on it.
     *
     * Leaving a screen to a game is two things, and they cost differently. Standing
     * aside is instant and free: a panel slides off the screen and nothing of it is
     * drawn over the game. Giving up the window is neither, because Quickshell
     * destroys a layer window when it is hidden and builds a new one to bring it
     * back, scene graph and textures and all. The timings say it plainly: a panel's
     * surface is gone two to thirty milliseconds after the screen changes hands and
     * takes a hundred and ten to seven hundred and fifty milliseconds to come back.
     * One session of stepping in and out of a game paid that thirty times over, for
     * trips that lasted seconds.
     *
     * What that was paying for is the compositor's solitary path, and it turns out
     * not to be needed for it. With the panels parked and their drawing stopped, the
     * compositor handed the screen to the game with their surfaces still mapped, in
     * two separate episodes, and it was the unmapping that briefly took solitary away
     * again as the dying layer faded out. So the wait is nought, which means never,
     * and the mechanism is kept for a machine where a mapped layer does get in the way.
     */
    function standDownOn(monitorName) {
        if (!monitorName)
            return false;
        return root.stoodDown[monitorName] === true;
    }

    /// The wait, in milliseconds. Nought means the windows are never given up.
    readonly property int standDownDelay: Math.max(0, Config.options.gameMode.standDownDelay) * 1000
    onStandDownDelayChanged: root.reviewStandDown()

    /// When each screen now holding a game was taken over, by monitor name.
    property var fullscreenSince: ({})

    /// The ones whose wait is over. Read through standDownOn.
    property var stoodDown: ({})

    onFullscreenMonitorsChanged: root.reviewStandDown()

    /**
     * Brings both tables in line with the screens as they are now and points the
     * timer at whichever one comes due first.
     *
     * A screen that is the desktop's again is taken back here and now: coming back
     * is never made to wait, only leaving is. This runs on every reading of the
     * compositor's workspaces, so the tables are written back only when they have
     * really changed, or every panel reading them would be answered afresh several
     * times a second.
     */
    function reviewStandDown() {
        if (root.standDownDelay <= 0) {
            standDownTimer.stop();
            if (Object.keys(root.stoodDown).length > 0)
                root.stoodDown = ({});
            if (Object.keys(root.fullscreenSince).length > 0)
                root.fullscreenSince = ({});
            return;
        }
        const now = Date.now();
        const since = ({});
        const stood = ({});
        for (const name of root.fullscreenMonitors) {
            since[name] = root.fullscreenSince[name] ?? now;
            if (root.stoodDown[name] === true)
                stood[name] = true;
        }
        if (!root.sameNames(since, root.fullscreenSince))
            root.fullscreenSince = since;
        if (!root.sameNames(stood, root.stoodDown))
            root.stoodDown = stood;

        let soonest = -1;
        for (const name of Object.keys(since)) {
            if (stood[name] === true)
                continue;
            const due = since[name] + root.standDownDelay - now;
            if (soonest < 0 || due < soonest)
                soonest = due;
        }
        if (soonest < 0) {
            standDownTimer.stop();
            return;
        }
        standDownTimer.interval = Math.max(soonest, 1);
        standDownTimer.restart();
    }

    function sameNames(a, b) {
        const names = Object.keys(a);
        return names.length === Object.keys(b).length && names.every(name => b[name] !== undefined);
    }

    Timer {
        id: standDownTimer
        onTriggered: {
            const now = Date.now();
            const stood = ({});
            for (const name of Object.keys(root.fullscreenSince)) {
                if (root.stoodDown[name] === true || root.fullscreenSince[name] + root.standDownDelay <= now)
                    stood[name] = true;
            }
            root.stoodDown = stood;
            root.reviewStandDown();
        }
    }

    /// What the mode is being asked for at this instant.
    readonly property bool requested: Config.options.gameMode.active
        || (Config.options.gameMode.autoOnFullscreen && root.anyFullscreen)

    /**
     * The mode as the rest of the shell sees it: on as soon as it is asked for,
     * off only once it has stayed unasked for a moment.
     *
     * A window being closed takes the compositor through a burst of focus and
     * workspace changes, and the fullscreen read above is false in the gaps
     * between them. Answering each gap on its own cost a governor hold torn down
     * and started again, a wallpaper stopped and continued, and a pass over the
     * compositor settings, ten times a second for as long as the burst ran, and
     * it is the pass over the settings that lost the way back to the desktop.
     * Waiting out the gaps costs half a second of a governor nobody is using.
     */
    property bool engaged: false

    onRequestedChanged: {
        if (root.requested) {
            settleTimer.stop();
            root.engaged = true;
        } else if (root.engaged) {
            settleTimer.restart();
        }
    }

    Timer {
        id: settleTimer
        interval: 500
        onTriggered: root.engaged = root.requested
    }

    function setManual(on) {
        if (on === root.engaged) return;
        Config.options.gameMode.active = on;
        // A switch that was just flicked is answered at once. The wait above is
        // there to ride out the compositor's own flicker, and a hand on the
        // toggle is not that.
        settleTimer.stop();
        root.engaged = root.requested;
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
     * The desktop's own values for those settings, as last seen.
     *
     * Kept in the state file as well as in memory, and kept after the mode has
     * put them back rather than dropped. It is the one record of what the desktop
     * looks like without the mode on it: a shell that starts while the mode is
     * engaged can only read the mode's own values off the compositor, and one
     * that never had a reading of its own has nowhere to return to. It is taken
     * fresh whenever the compositor is read and found to be holding something
     * other than the mode's values, so a setting changed on the desktop between
     * one game and the next is the one that comes back.
     */
    property var desktopVisual: null

    /// Whether the compositor is holding the mode's values rather than the desktop's.
    property bool visualApplied: false

    /// One reading or one write at a time, and never both.
    property bool visualBusy: false

    /**
     * Set when a reading or a write did not go through. Nothing is retried on its
     * own afterwards: a failure that repeats would otherwise be asked again the
     * moment it was answered, for as long as the mode stayed as it is.
     */
    property bool visualStalled: false

    onVisualEngagedChanged: {
        root.visualStalled = false;
        root.syncVisual();
    }

    /**
     * Brings the compositor in line with the mode, one step at a time.
     *
     * Reading the settings and writing them are separate processes, and both used
     * to be started straight off the change that called for them. A mode that
     * went on and off again while a reading was in the air had that reading
     * answer for a state that no longer held, and a reading taken while the
     * previous write was still on its way came back with the mode's own values
     * and offered them as the desktop's. That is how the way back was lost, and
     * once lost it stayed lost: every reading after it found the mode's values
     * already in place, kept no record, and left the desktop flat.
     */
    function syncVisual() {
        if (!Persistent.ready || root.visualBusy || root.visualStalled)
            return;
        if (root.visualEngaged === root.visualApplied)
            return;
        if (root.visualEngaged)
            root.engageVisual();
        else
            root.disengageVisual();
    }

    function engageVisual() {
        root.visualBusy = true;
        captureProc.forEngage = true;
        captureProc.running = true;
    }

    function disengageVisual() {
        // Read again rather than trusting the copy taken at startup: the record
        // may have been written after it, by another shell or by hand, and this
        // is the one moment it is needed.
        if (!root.desktopVisual)
            root.loadDesktopVisual();
        if (!root.desktopVisual) {
            console.warn("[GameMode] nothing saved to put back, leaving the compositor settings alone");
            root.setVisualApplied(false);
            return;
        }
        root.visualBusy = true;
        root.writeVisual(root.desktopVisual, false);
    }

    function loadDesktopVisual() {
        const saved = Persistent.states.gameMode.desktopVisual;
        if (!saved || saved.length === 0)
            return;
        try {
            root.desktopVisual = JSON.parse(saved);
        } catch (error) {
            root.desktopVisual = null;
        }
    }

    /// Reads the settings without touching them, so the desktop is on record
    /// before a game ever asks for the mode.
    function snapshotDesktop() {
        if (root.visualBusy)
            return;
        root.visualBusy = true;
        captureProc.forEngage = false;
        captureProc.running = true;
    }

    function writeVisual(values, applied) {
        applyProc.appliedAfter = applied;
        applyProc.command = root.applyCommand(values);
        applyProc.running = true;
    }

    /// Whatever the step just taken was, the mode may have changed while it ran,
    /// so the state is compared with the compositor again rather than assumed.
    function finishVisual() {
        root.visualBusy = false;
        root.syncVisual();
    }

    function setVisualApplied(applied) {
        root.visualApplied = applied;
        Persistent.states.gameMode.visualApplied = applied;
    }

    function rememberDesktop(values) {
        root.desktopVisual = values;
        Persistent.states.gameMode.desktopVisual = JSON.stringify(values);
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

    /// One option per line, as `<key>\t<the json getoption printed>`.
    function parseReported(text) {
        const found = ({});
        for (const line of text.split("\n")) {
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
            // Whichever type the option turned out to be, kept as that type.
            // Flattened to a string it could be neither compared with the mode's
            // own values nor written back as lua.
            for (const field of ["bool", "int", "float", "css", "str"]) {
                if (reported[field] !== undefined) {
                    const kept = ({});
                    kept[field] = reported[field];
                    found[key] = kept;
                    break;
                }
            }
        }
        return found;
    }

    Process {
        id: captureProc
        /// Whether this reading is the one the mode takes on its way in, as
        /// against the one taken to put the desktop on record.
        property bool forEngage: false
        command: ["bash", "-c", `for key in ${root.visualKeywords.join(" ")}; do printf '%s\t' "$key"; hyprctl -j getoption "$key" | tr -d '\n'; printf '\n'; done`]
        stdout: StdioCollector {
            id: captureCollector
            onStreamFinished: {
                const found = root.parseReported(captureCollector.text);

                // Nothing is overwritten on a short reading, and no half of one is
                // kept as the desktop either.
                if (!root.visualKeywords.every(key => found[key] !== undefined)) {
                    console.warn(`[GameMode] read back ${Object.keys(found).length} of ${root.visualKeywords.length} settings, leaving the compositor alone`);
                    root.visualStalled = true;
                    root.finishVisual();
                    return;
                }

                const holdsModeValues = root.visualKeywords.every(key =>
                    root.normalized(found[key]) === root.normalized(root.visualValues[key]));
                // Only a reading that is not the mode's own says anything about
                // the desktop. Keeping the mode's values as the desktop is what
                // would restore them as if they were, leaving nothing to come back to.
                if (!holdsModeValues)
                    root.rememberDesktop(found);

                if (!captureProc.forEngage || !root.visualEngaged) {
                    root.finishVisual();
                    return;
                }

                if (holdsModeValues) {
                    if (!root.desktopVisual)
                        console.warn("[GameMode] the compositor already holds this mode's values and no desktop reading is on record, so there is nothing to put back afterwards");
                    root.setVisualApplied(true);
                    root.finishVisual();
                    return;
                }

                root.writeVisual(root.visualValues, true);
            }
        }
    }

    Process {
        id: applyProc
        /// What the compositor is holding once this write lands.
        property bool appliedAfter: false
        onExited: exitCode => {
            if (exitCode !== 0) {
                console.warn(`[GameMode] hyprctl refused the compositor settings with status ${exitCode}`);
                root.visualStalled = true;
            } else {
                root.setVisualApplied(applyProc.appliedAfter);
            }
            root.finishVisual();
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

    /**
     * Picks the state file back up, and with it the two questions a fresh shell
     * cannot answer by looking at the compositor: what the desktop looked like,
     * and whether what is on the compositor now was put there by this mode. A
     * session that ended while a game was running comes back to a flat desktop
     * and is what puts it right.
     */
    function restoreVisualState() {
        if (!Persistent.ready)
            return;
        root.visualApplied = Persistent.states.gameMode.visualApplied;
        root.loadDesktopVisual();
        root.syncVisual();
        // Idle and on the desktop's own settings: the moment to read them, so the
        // record is this session's rather than one carried over from another.
        if (!root.visualEngaged && !root.visualApplied)
            root.snapshotDesktop();
    }

    Connections {
        target: Persistent
        function onReadyChanged() {
            root.restoreVisualState();
        }
    }

    Component.onCompleted: {
        root.engaged = root.requested;
        root.reviewStandDown();
        root.restoreVisualState();
        if (root.wallpaperPaused) root.setWallpaperPaused(true);
    }
}

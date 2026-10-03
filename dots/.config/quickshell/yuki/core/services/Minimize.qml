pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Minimising, which Hyprland does not have.
 *
 * A minimised window is parked on a special workspace named after the one it
 * came from: `special:min-3` holds what was minimised on workspace 3. Nothing is
 * remembered here. Which windows are minimised, and where each goes back to, is
 * read off the compositor, so it survives the shell restarting and cannot come
 * to disagree with what is on screen.
 *
 * Off unless an environment turns it on. Honouring an application's own request
 * to minimise changes what alt-tab out of a fullscreen game does, and an
 * environment designed without minimising has to keep behaving the way it did.
 */
Singleton {
    id: root

    /**
     * Wanted by the environment that is up. Set it through a `Binding`, which
     * puts the old value back when that environment is torn down.
     */
    property bool enabled: false

    /**
     * Shows windows going into the dock and coming back out of it, or null for
     * none. Handed the windows and the function that moves them, which it has
     * to call exactly once: when minimising, as soon as it has a picture of
     * them to show, and when restoring, once they have arrived. Set through a
     * `Binding` like `enabled`.
     */
    property var animator: null

    readonly property string prefix: "special:min-"

    /**
     * Every minimised window. Bound from the start, which is also what wakes
     * the window list: that singleton is only built when first read, and a
     * first request that arrived before it had read anything found no window
     * to act on.
     */
    readonly property var minimizedWindows: HyprlandData.windowList.filter(win => root.originOf(win) > 0)

    /** The workspace a minimised window goes back to, or -1 for one that is not minimised. */
    function originOf(win): int {
        const name = win?.workspace?.name ?? "";
        return name.startsWith(root.prefix) ? parseInt(name.slice(root.prefix.length)) : -1;
    }

    function isMinimized(address: string): bool {
        return root.originOf(HyprlandData.windowByAddress[address]) > 0;
    }

    /** What belongs to a workspace, shown or minimised, in the compositor's order. */
    function windowsOf(workspaceId: int): var {
        return HyprlandData.windowList.filter(win => win.workspace.id === workspaceId || root.originOf(win) === workspaceId);
    }

    // The address goes into a line of lua, so it is held to the one shape the
    // compositor hands out. Hyprland itself accepts any string and silently
    // does nothing with one that names no window.
    function usable(address: string): bool {
        return /^0x[0-9a-f]+$/.test(address);
    }

    function minimize(address: string) {
        root.minimizeMany([address]);
    }

    /**
     * Several windows in one go, as one chunk of lua. Focus is handed on once,
     * to a window that stays: minimised one by one, the first would pass it to
     * a sibling that the next command then took out of sight with it.
     */
    function minimizeMany(addresses) {
        if (!root.enabled)
            return;
        // Where a floating window stands is read fresh: moving one raises no
        // event, so the window list can still hold where it stood before.
        root.minimizeQueue = [...root.minimizeQueue, addresses];
        if (!geometry.running)
            geometry.running = true;
    }

    property var minimizeQueue: []

    Process {
        id: geometry
        command: ["hyprctl", "clients", "-j"]
        // The queue is emptied when the output ends, and the process only
        // counts as stopped a moment later. A request in between found it
        // running and waited for a next one that might never come.
        onRunningChanged: {
            if (!geometry.running && root.minimizeQueue.length > 0)
                geometry.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                let fresh = {};
                try {
                    for (const client of JSON.parse(text))
                        fresh[client.address] = { at: client.at, size: client.size };
                } catch (error) {
                    fresh = {};
                }
                const queue = root.minimizeQueue;
                root.minimizeQueue = [];
                for (const addresses of queue)
                    root.minimizeNow(addresses, fresh);
            }
        }
    }

    function minimizeNow(addresses, fresh) {
        // Only a window on an ordinary workspace has somewhere to be put back.
        // With where each stands now, which is also where its picture sets off from.
        const windows = addresses.filter(address => root.usable(address))
            .map(address => HyprlandData.windowByAddress[address])
            .filter(win => win && win.workspace.id >= 1)
            .map(win => Object.assign({}, win, fresh[win.address] ?? {}));
        if (windows.length === 0)
            return;
        let lua = "";
        for (const win of windows) {
            // Hyprland fits a floating window into the work area of the
            // workspace it is moved to, so one that reached under the dock came
            // back higher each time. Where it stood is kept, to put it back there.
            if (win.floating)
                root.remember(win.address, win.at);
            lua += `hl.dispatch(hl.dsp.window.move({ workspace = "${root.prefix}${win.workspace.id}", follow = false, window = "address:${win.address}" })) `;
        }
        // A window moved out of sight keeps keyboard focus, so typing would go
        // on reaching it. Focus passes to whichever window of the same workspace
        // had it last, the way closing a window hands it on, and is let go of
        // when there is none. Letting go needs the minimize plugin, and without
        // it focus stays where Hyprland left it.
        const focused = windows.find(win => win.focusHistoryID === 0);
        if (focused) {
            const next = root.lastFocusedOn(focused.workspace.id, windows.map(win => win.address));
            lua += next ? `hl.dispatch(hl.dsp.focus({ window = "address:${next.address}" }))`
                : "if hl.plugin.minimize and hl.plugin.minimize.reset_focus then hl.plugin.minimize.reset_focus() end";
        }
        root.move(windows, lua, "minimize");
    }

    /** The window of a workspace that had focus most recently, other than the ones named. */
    function lastFocusedOn(workspaceId: int, except): var {
        return HyprlandData.windowList
            .filter(win => win.workspace.id === workspaceId && !except.includes(win.address) && win.focusHistoryID >= 0)
            .sort((a, b) => a.focusHistoryID - b.focusHistoryID)[0] ?? null;
    }

    function restore(address: string) {
        root.restoreMany([address]);
    }

    /** Puts several back in one go. The one used last comes up in front with focus. */
    function restoreMany(addresses) {
        if (!root.enabled)
            return;
        const windows = addresses.filter(address => root.usable(address))
            .map(address => HyprlandData.windowByAddress[address])
            .filter(win => root.originOf(win) > 0);
        if (windows.length === 0)
            return;
        const front = windows.reduce((best, win) => win.focusHistoryID >= 0 && (best.focusHistoryID < 0 || win.focusHistoryID < best.focusHistoryID) ? win : best);
        const target = `window = "address:${front.address}"`;
        let lua = "";
        // One chunk rather than several commands: separate processes do not
        // keep their order, and focus has to land after the windows are back.
        for (const win of windows) {
            lua += `hl.dispatch(hl.dsp.window.move({ workspace = ${root.originOf(win)}, follow = false, window = "address:${win.address}" })) `;
            const at = root.placeOf(win.address);
            if (at)
                lua += `hl.dispatch(hl.dsp.window.move({ window = "address:${win.address}", x = ${at[0]}, y = ${at[1]} })) `;
        }
        root.move(windows, lua + `hl.dispatch(hl.dsp.focus({ ${target} })) hl.dispatch(hl.dsp.window.bring_to_top({ ${target} }))`, "restore");
        root.forget(windows.map(win => win.address));
    }

    /**
     * Where each minimised floating window stood, by address. Kept only in
     * memory: after a restart of the shell a window comes back where Hyprland
     * left it, which is all that was lost.
     */
    property var places: ({})

    function remember(address: string, at) {
        const next = Object.assign({}, root.places);
        next[address] = [Math.round(at[0]), Math.round(at[1])];
        root.places = next;
    }

    function forget(addresses) {
        const next = Object.assign({}, root.places);
        for (const address of addresses)
            delete next[address];
        root.places = next;
    }

    /** Where a minimised floating window stood before, as [x, y], or null. */
    function placeOf(address: string): var {
        return root.places[address] ?? null;
    }

    // Through the animator when there is one. The move happens once however
    // often it is asked for, and happens anyway if the animator never asks:
    // a fault in how it looks must not leave windows where they were.
    property var pendingMoves: []

    function move(windows, lua: string, kind: string) {
        if (!root.animator) {
            root.run(lua);
            return;
        }
        // The animator draws the going and the coming, so the compositor must
        // not animate the window as well: it would slide or fade it on top of
        // the picture flying into the dock, one movement twice. Its own
        // animations are switched off for the move and given back afterwards,
        // to whatever the window rules say, once the window has settled.
        const props = value => windows.map(win => `hl.dispatch(hl.dsp.window.set_prop({ window = "address:${win.address}", prop = "no_anim", value = "${value}" })) `).join("");
        lua = props("1") + lua;
        root.unquiet = [...root.unquiet, { lua: props("unset"), at: 0 }];
        const entry = root.unquiet[root.unquiet.length - 1];
        const pending = { done: false, deadline: Date.now() + 1500, go: null };
        pending.go = () => {
            if (pending.done)
                return;
            pending.done = true;
            root.pendingMoves = root.pendingMoves.filter(other => other !== pending);
            root.run(lua);
            entry.at = Date.now() + 700;
        };
        root.pendingMoves = [...root.pendingMoves, pending];
        try {
            root.animator[kind](windows, pending.go);
        } catch (error) {
            console.warn("[Minimize] animator failed, moving without it:", error);
            pending.go();
        }
    }

    /** Animations to give back to windows once they have moved, and when. */
    property var unquiet: []

    Timer {
        interval: 250
        repeat: true
        running: root.pendingMoves.length > 0 || root.unquiet.length > 0
        onTriggered: {
            const now = Date.now();
            for (const pending of root.pendingMoves)
                if (pending.deadline <= now)
                    pending.go();
            const due = root.unquiet.filter(entry => entry.at > 0 && entry.at <= now);
            if (due.length === 0)
                return;
            root.unquiet = root.unquiet.filter(entry => !due.includes(entry));
            root.run(due.map(entry => entry.lua).join(""));
        }
    }

    /** The windows showing the desktop put away, by workspace, to bring back. */
    property var desktopShown: ({})

    /**
     * Shows the desktop of a workspace, or brings back what showing it put
     * away, the way the far corner of the Windows taskbar does. What is on the
     * workspace is minimised and remembered. With nothing left in sight, the
     * next call restores exactly those. A window opened in between counts as
     * something in sight, and puts it all away again.
     */
    function toggleDesktop(workspaceId: int) {
        if (!root.enabled || workspaceId < 1)
            return;
        const inSight = HyprlandData.windowList.filter(win => win.workspace.id === workspaceId).map(win => win.address);
        const kept = (root.desktopShown[workspaceId] ?? []).filter(address => root.isMinimized(address));
        const next = Object.assign({}, root.desktopShown);
        if (inSight.length === 0) {
            delete next[workspaceId];
            root.desktopShown = next;
            if (kept.length > 0)
                root.restoreMany(kept);
            return;
        }
        next[workspaceId] = inSight;
        root.desktopShown = next;
        root.minimizeMany(inSight);
    }

    /**
     * Puts every minimised window back on its workspace, with no animation
     * and no change of focus.
     *
     * For when no environment that minimises is up: switched to one without a
     * dock, or started after a session that ended with windows minimised, they
     * would sit on their special workspaces with nothing to bring them back.
     */
    function releaseAll() {
        const lua = root.minimizedWindows.filter(win => root.usable(win.address))
            .map(win => `hl.dispatch(hl.dsp.window.move({ workspace = ${root.originOf(win)}, follow = false, window = "address:${win.address}" })) `)
            .join("");
        if (lua.length > 0)
            root.run(lua);
        root.places = ({});
        root.desktopShown = ({});
    }

    /** Built with the shell, so that the timer below runs whichever environment is up. */
    function load() {
    }

    // Given a few seconds after an environment has settled: the one that
    // minimises turns this on as it comes up, and a reload passes through
    // a moment with it off.
    Timer {
        interval: 4000
        running: !root.enabled && Environments.activeId.length > 0 && root.minimizedWindows.length > 0
        onTriggered: {
            if (!root.enabled && Environments.activeId.length > 0)
                root.releaseAll();
        }
    }

    function toggle(address: string) {
        if (root.isMinimized(address))
            root.restore(address);
        else
            root.minimize(address);
    }

    function run(lua: string) {
        Quickshell.execDetached(["hyprctl", "eval", lua]);
    }

    // An application asking to be minimised, or put back. Also what arrives when
    // another client minimises a window through foreign-toplevel.
    Connections {
        target: Hyprland
        enabled: root.enabled

        function onRawEvent(event) {
            if (event.name !== "minimized")
                return;
            const [address, state] = event.data.split(",");
            if (state === "1")
                root.minimize(`0x${address}`);
            else
                root.restore(`0x${address}`);
        }
    }

    IpcHandler {
        target: "minimize"

        function active(): void {
            root.minimize(HyprlandData.windowList.find(win => win.focusHistoryID === 0)?.address ?? "");
        }
        function toggle(address: string): void {
            root.toggle(address);
        }
        /** Shows the desktop of the focused screen, or brings its windows back. */
        function desktop(): void {
            root.toggleDesktop(Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1);
        }
    }
}

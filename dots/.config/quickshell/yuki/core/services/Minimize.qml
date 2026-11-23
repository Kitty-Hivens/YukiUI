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
     * them to show, and when restoring, once they have arrived. Handed with
     * them is a function to call with the address of each once nothing of it
     * is in the air any more. Set through a `Binding` like `enabled`.
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

    /**
     * Windows on their way out of sight or back, by address:
     * { kind, wanted, landed, until, landBy }. The compositor has a window
     * where it was until its picture has flown, so what the window list says
     * about one in the air is not what the next click means. Asked again
     * while it flies, a window was sent off a second time, and its picture
     * hung over the window already come back.
     */
    property var moving: ({})

    /** Whether a window is on its way. */
    function busy(address: string): bool {
        return root.moving[address] !== undefined;
    }

    /** "minimize" or "restore": what a window is, or is becoming. */
    function heading(address: string): string {
        const flight = root.moving[address];
        if (flight)
            return flight.wanted ?? flight.kind;
        return root.isMinimized(address) ? "minimize" : "restore";
    }

    /**
     * The windows that set off now. One already on its way is left to arrive,
     * and turned round then if that is what was asked meanwhile.
     */
    function setOff(addresses, kind: string): var {
        const next = Object.assign({}, root.moving);
        const free = [];
        for (const address of addresses) {
            if (next[address]) {
                next[address] = Object.assign({}, next[address], { wanted: next[address].kind === kind ? null : kind });
            } else {
                next[address] = { kind: kind, wanted: null, landed: false, until: Date.now() + 3000, landBy: 0 };
                free.push(address);
            }
        }
        root.moving = next;
        return free;
    }

    /** A window that turned out not to go anywhere. */
    function stay(addresses) {
        const next = Object.assign({}, root.moving);
        for (const address of addresses)
            delete next[address];
        root.moving = next;
    }

    function landed(address: string) {
        if (!root.moving[address])
            return;
        const next = Object.assign({}, root.moving);
        next[address] = Object.assign({}, next[address], { landed: true });
        root.moving = next;
        root.arrive();
    }

    /** Lets go of the windows that have arrived, and sends back those wanted elsewhere. */
    function arrive() {
        const now = Date.now();
        const next = Object.assign({}, root.moving);
        const turned = [];
        for (const address in next) {
            const flight = next[address];
            const done = flight.landed && root.isMinimized(address) === (flight.kind === "minimize");
            if (!done && now < flight.until)
                continue;
            delete next[address];
            if (flight.wanted)
                turned.push({ address: address, kind: flight.wanted });
        }
        if (Object.keys(next).length !== Object.keys(root.moving).length)
            root.moving = next;
        for (const turn of turned)
            Qt.callLater(() => turn.kind === "minimize" ? root.minimize(turn.address) : root.restore(turn.address));
    }

    Connections {
        target: HyprlandData
        function onWindowListChanged() {
            if (Object.keys(root.moving).length > 0)
                root.arrive();
        }
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
        const free = root.setOff(addresses, "minimize");
        if (free.length === 0)
            return;
        root.minimizeQueue = [...root.minimizeQueue, free];
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
                let clients = [];
                try {
                    clients = JSON.parse(text);
                } catch (error) {
                    clients = [];
                }
                const queue = root.minimizeQueue;
                root.minimizeQueue = [];
                for (const addresses of queue)
                    root.minimizeNow(addresses, clients);
            }
        }
    }

    function minimizeNow(addresses, clients) {
        // Only a window on an ordinary workspace has somewhere to be put back.
        // With where each stands now, which is also where its picture sets off
        // from, and from the bottom up, the order their pictures are drawn in.
        // Each window as the compositor has it now, by preference: the shared
        // list is a read behind, and a window asking to be minimised as it
        // opens was not in it yet, so the request was lost.
        const order = clients.map(client => client.address);
        const moving = addresses.filter(address => root.usable(address));
        const windows = moving
            .map(address => clients.find(client => client.address === address) ?? HyprlandData.windowByAddress[address])
            .filter(win => win && win.workspace.id >= 1)
            .map(win => Object.assign({}, win, { coveredBy: root.coveringOf(win, clients, moving) }))
            .sort((a, b) => order.indexOf(a.address) - order.indexOf(b.address));
        root.stay(addresses.filter(address => !windows.some(win => win.address === address)));
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
        // it focus stays where Hyprland left it. The window given focus is
        // raised with it: the one used last is not always the one on top, and
        // focus alone would leave the keys going to a window behind another.
        const focused = windows.find(win => win.focusHistoryID === 0);
        if (focused) {
            const next = root.lastFocusedOn(focused.workspace.id, windows.map(win => win.address));
            const target = next ? `window = "address:${next.address}"` : "";
            lua += next ? `hl.dispatch(hl.dsp.focus({ ${target} })) hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", ${target} }))`
                : "if hl.plugin.minimize and hl.plugin.minimize.reset_focus then hl.plugin.minimize.reset_focus() end";
        }
        root.move(windows, lua, "minimize");
    }

    /**
     * What stands over a window and stays where it is, as {x, y, w, h} in the
     * compositor's coordinates: the windows of its workspace drawn after it,
     * other than the ones going with it. Hyprland draws tiled windows first,
     * floating ones over them and a fullscreen one over both, each kind in the
     * order of its window list, which raising a window changes. Pinned windows
     * are over everything on their screen, and left to whoever draws.
     */
    function coveringOf(win, clients, moving): var {
        const index = clients.findIndex(client => client.address === win.address);
        if (index < 0)
            return [];
        const rank = client => client.fullscreen > 0 ? 2 : client.floating ? 1 : 0;
        const own = rank(clients[index]);
        return clients
            .filter((client, at) => client.workspace.id === win.workspace.id && client.mapped && !client.hidden
                && !client.pinned && !moving.includes(client.address)
                && (rank(client) > own || (rank(client) === own && at > index)))
            .map(client => ({ x: client.at[0], y: client.at[1], w: client.size[0], h: client.size[1] }));
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
        const free = root.setOff(addresses.filter(address => root.usable(address)), "restore");
        const windows = free.map(address => HyprlandData.windowByAddress[address])
            .filter(win => root.originOf(win) > 0);
        root.stay(free.filter(address => !windows.some(win => win.address === address)));
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
        root.move(windows, lua + `hl.dispatch(hl.dsp.focus({ ${target} })) hl.dispatch(hl.dsp.window.alter_zorder({ mode = "top", ${target} }))`, "restore");
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
            for (const win of windows)
                root.landed(win.address);
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
            // An animator that never says so counts as done by then.
            const next = Object.assign({}, root.moving);
            for (const win of windows)
                if (next[win.address])
                    next[win.address] = Object.assign({}, next[win.address], { landBy: Date.now() + 700 });
            root.moving = next;
        };
        root.pendingMoves = [...root.pendingMoves, pending];
        try {
            root.animator[kind](windows, pending.go, address => root.landed(address));
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
        running: root.pendingMoves.length > 0 || root.unquiet.length > 0 || Object.keys(root.moving).length > 0
        onTriggered: {
            const now = Date.now();
            for (const address in root.moving)
                if (!root.moving[address].landed && root.moving[address].landBy > 0 && root.moving[address].landBy <= now)
                    root.landed(address);
            root.arrive();
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
        if (root.heading(address) === "minimize")
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

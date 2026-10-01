import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.core
import qs.core.services

// Maximising as Windows does it: a floating window given the work area of its
// screen, the screen less what the dock keeps, and put back where it was.
//
// Hyprland maximises a window as a kind of fullscreen. Only one window per
// workspace can be in that state, maximising a second puts the first back, and
// a window in it is not raised over floating windows. So this family suppresses
// Hyprland's own maximise with a window rule, and a request to maximise, from
// the window's own title bar through the minimize plugin or from the keys,
// comes here. The application is still told it is maximised, so it draws
// itself that way, while the compositor treats it as an ordinary window.
Scope {
    id: root

    /** Where each window maximised here stood before, by address: { at: [x, y], size: [w, h] }. */
    property var before: ({})

    function isMaximized(address: string): bool {
        return root.before[address] !== undefined;
    }

    function usable(address: string): bool {
        return /^0x[0-9a-f]+$/.test(address);
    }

    // Each call reads the windows and the screens fresh: the shared lists are
    // a read behind, and a floating window moving raises no event at all.
    function request(address: string, wanted: string) {
        if (!root.usable(address))
            return;
        root.queue = [...root.queue, { address: address, wanted: wanted }];
        if (!reader.running)
            reader.running = true;
    }

    function maximize(address: string) {
        root.request(address, "maximize");
    }
    function restore(address: string) {
        root.request(address, "restore");
    }
    function toggle(address: string) {
        root.request(address, "toggle");
    }
    /** Fits every window maximised here to its screen's work area again, after the dock moved say. */
    function refit() {
        for (const address of Object.keys(root.before))
            root.request(address, "refit");
    }

    property var queue: []

    Process {
        id: reader

        command: ["sh", "-c", "hyprctl clients -j; echo; hyprctl monitors -j"]
        onRunningChanged: {
            if (!reader.running && root.queue.length > 0)
                reader.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const queue = root.queue;
                root.queue = [];
                let clients, monitors;
                try {
                    const parts = text.split(/\n(?=\[)/);
                    clients = JSON.parse(parts[0]);
                    monitors = JSON.parse(parts[1]);
                } catch (error) {
                    return;
                }
                let lua = "";
                for (const job of queue)
                    lua += root.answer(job, clients, monitors);
                if (lua.length > 0)
                    Quickshell.execDetached(["hyprctl", "eval", lua]);
            }
        }
    }

    /** The work area of a monitor in global logical coordinates: the screen less what is reserved along its edges. */
    function workArea(monitor): var {
        const scale = monitor.scale || 1;
        const transformed = monitor.transform % 2 === 1;
        const width = (transformed ? monitor.height : monitor.width) / scale;
        const height = (transformed ? monitor.width : monitor.height) / scale;
        const [left, top, right, bottom] = monitor.reserved ?? [0, 0, 0, 0];
        return {
            x: Math.round(monitor.x + left),
            y: Math.round(monitor.y + top),
            w: Math.round(width - left - right),
            h: Math.round(height - top - bottom)
        };
    }

    function answer(job, clients, monitors): string {
        const client = clients.find(candidate => candidate.address === job.address);
        if (!client || !client.floating || client.workspace.id < 1)
            return "";
        const monitor = monitors.find(candidate => candidate.id === client.monitor);
        if (!monitor)
            return "";
        const target = `window = "address:${client.address}"`;
        const known = root.isMaximized(client.address);
        const wanted = job.wanted === "toggle" ? (known ? "restore" : "maximize") : job.wanted;

        if (wanted === "restore") {
            const saved = root.before[client.address];
            const next = Object.assign({}, root.before);
            delete next[client.address];
            root.before = next;
            let lua = `hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, ${target} })) `;
            // Known only for a window maximised here since the shell started.
            // One maximised before is given back a size of its own, centred.
            const area = root.workArea(monitor);
            const size = saved?.size ?? [Math.round(area.w * 0.6), Math.round(area.h * 0.7)];
            const at = saved?.at ?? [Math.round(area.x + (area.w - size[0]) / 2), Math.round(area.y + (area.h - size[1]) / 2)];
            lua += `hl.dispatch(hl.dsp.window.resize({ ${target}, x = ${size[0]}, y = ${size[1]} })) `;
            lua += `hl.dispatch(hl.dsp.window.move({ ${target}, x = ${at[0]}, y = ${at[1]} })) `;
            return lua;
        }

        if (wanted === "refit" && !known)
            return "";
        if (wanted === "maximize" && !known) {
            const next = Object.assign({}, root.before);
            next[client.address] = { at: client.at, size: client.size };
            root.before = next;
        }
        const area = root.workArea(monitor);
        // Told it is maximised, so it draws itself that way, while the
        // compositor keeps treating it as an ordinary floating window.
        return `hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 1, ${target} })) `
            + `hl.dispatch(hl.dsp.window.resize({ ${target}, x = ${area.w}, y = ${area.h} })) `
            + `hl.dispatch(hl.dsp.window.move({ ${target}, x = ${area.x}, y = ${area.y} })) `;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "maximizerequest") {
                const [address, state] = event.data.split(",");
                root.request(`0x${address}`, state === "1" ? "maximize" : "restore");
            } else if (event.name === "closewindow") {
                // Gone, and its address may be handed to another window.
                const address = `0x${event.data}`;
                if (root.isMaximized(address)) {
                    const next = Object.assign({}, root.before);
                    delete next[address];
                    root.before = next;
                }
            } else if (event.name === "monitoradded" || event.name === "monitorremoved" || event.name === "configreloaded") {
                refitLater.restart();
            }
        }
    }

    // The work area changes with the dock: its edge, its style, hiding itself.
    Connections {
        target: Config.options.experimental.dock
        function onEdgeChanged() {
            refitLater.restart();
        }
        function onStyleChanged() {
            refitLater.restart();
        }
        function onAutoHideChanged() {
            refitLater.restart();
        }
    }
    // Once the compositor has the new reserved area.
    Timer {
        id: refitLater
        interval: 600
        onTriggered: root.refit()
    }

    GlobalShortcut {
        name: "maximizeToggle"
        description: "Maximises the focused window or puts it back"
        onPressed: root.toggle(HyprlandData.windowList.find(client => client.focusHistoryID === 0)?.address ?? "")
    }

    IpcHandler {
        target: "maximize"

        function toggle(address: string): void {
            root.toggle(address);
        }
        function active(): void {
            root.toggle(HyprlandData.windowList.find(client => client.focusHistoryID === 0)?.address ?? "");
        }
        function list(): string {
            return JSON.stringify(Object.keys(root.before));
        }
    }
}

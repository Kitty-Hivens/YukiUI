import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.core
import qs.core.services

// Where a window is put as Windows puts it: maximised, or snapped to half of
// its screen or a quarter of it, and put back where it stood.
//
// Every placement is a floating window given a part of the work area, the
// screen less what the dock reserves. Hyprland maximises a window as a kind of
// fullscreen that only one window per workspace can have and that is not raised
// over floating windows, so this family suppresses that with a window rule, and
// a window's own request to maximise reaches here through the minimize plugin.
// A maximised application is still told it is maximised, so it draws itself
// that way, while the compositor treats it as an ordinary window.
Scope {
    id: root

    /** The zones a window can be placed in. */
    readonly property var zones: ["maximized", "left", "right", "topleft", "topright", "bottomleft", "bottomright"]

    /**
     * Each window placed here, by address: { zone, before }, `before` being
     * where it stood and how large it was before it was placed, { at, size }.
     */
    property var placed: ({})

    function zoneOf(address: string): string {
        return root.placed[address]?.zone ?? "";
    }
    function isMaximized(address: string): bool {
        return root.zoneOf(address) === "maximized";
    }
    /** The size a placed window had before, to be given back as it is pulled away, or null. */
    function sizeBefore(address: string): var {
        return root.placed[address]?.before?.size ?? null;
    }

    function usable(address: string): bool {
        return /^0x[0-9a-f]+$/.test(address);
    }

    function setPlaced(address: string, entry) {
        const next = Object.assign({}, root.placed);
        if (entry)
            next[address] = entry;
        else
            delete next[address];
        root.placed = next;
        root.tellCompositor(address, entry);
    }

    // The compositor remembers where a window stood as it closes, and a placed
    // window is to be remembered as it stood before it was placed.
    function tellCompositor(address: string, entry) {
        const key = `YUKI_PLACED["${address}"]`;
        const before = entry?.before;
        Quickshell.execDetached(["hyprctl", "eval", before
            ? `YUKI_PLACED = YUKI_PLACED or {} ${key} = { x = ${before.at[0]}, y = ${before.at[1]}, w = ${before.size[0]}, h = ${before.size[1]} }`
            : `if YUKI_PLACED then ${key} = nil end`]);
    }
    // What the compositor was told by a shell before this one no longer holds.
    Component.onCompleted: Quickshell.execDetached(["hyprctl", "eval", "YUKI_PLACED = {}"])

    // Every call reads the windows and the screens fresh: the shared lists are
    // a read behind, and a floating window moving raises no event at all.
    function request(address: string, wanted: string) {
        if (!root.usable(address))
            return;
        root.queue = [...root.queue, { address: address, wanted: wanted }];
        if (!reader.running)
            reader.running = true;
    }

    function place(address: string, zone: string) {
        if (root.zones.includes(zone))
            root.request(address, zone);
    }
    function maximize(address: string) {
        root.request(address, "maximized");
    }
    function restore(address: string) {
        root.request(address, "restore");
    }
    function toggleMaximized(address: string) {
        root.request(address, "toggle");
    }
    /**
     * Lets go of a placement without moving the window: it is being pulled
     * away and has been given its size back, or was resized by hand.
     */
    function release(address: string) {
        if (!root.placed[address])
            return;
        const wasMaximized = root.isMaximized(address);
        root.setPlaced(address, null);
        if (wasMaximized)
            Quickshell.execDetached(["hyprctl", "eval", `hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, window = "address:${address}" }))`]);
    }
    /** Fits every placed window to its screen's work area again, after the dock moved say. */
    function refit() {
        for (const address of Object.keys(root.placed))
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

    /** The part of a work area a zone stands for. */
    function zoneRect(area, zone: string): var {
        const halfW = Math.round(area.w / 2);
        const halfH = Math.round(area.h / 2);
        switch (zone) {
        case "left":
            return { x: area.x, y: area.y, w: halfW, h: area.h };
        case "right":
            return { x: area.x + halfW, y: area.y, w: area.w - halfW, h: area.h };
        case "topleft":
            return { x: area.x, y: area.y, w: halfW, h: halfH };
        case "topright":
            return { x: area.x + halfW, y: area.y, w: area.w - halfW, h: halfH };
        case "bottomleft":
            return { x: area.x, y: area.y + halfH, w: halfW, h: area.h - halfH };
        case "bottomright":
            return { x: area.x + halfW, y: area.y + halfH, w: area.w - halfW, h: area.h - halfH };
        }
        return area;
    }

    function answer(job, clients, monitors): string {
        const client = clients.find(candidate => candidate.address === job.address);
        if (!client || !client.floating || client.workspace.id < 1)
            return "";
        const monitor = monitors.find(candidate => candidate.id === client.monitor);
        if (!monitor)
            return "";
        const target = `window = "address:${client.address}"`;
        const entry = root.placed[client.address];
        let wanted = job.wanted;
        if (wanted === "toggle")
            wanted = entry?.zone === "maximized" ? "restore" : "maximized";

        if (wanted === "restore") {
            if (!entry && client.fullscreenClient !== 1)
                return "";
            root.setPlaced(client.address, null);
            const area = root.workArea(monitor);
            // Known only for a window placed here since the shell started. One
            // placed before is given a size of its own, centred.
            const size = entry?.before?.size ?? [Math.round(area.w * 0.6), Math.round(area.h * 0.7)];
            const at = entry?.before?.at ?? [Math.round(area.x + (area.w - size[0]) / 2), Math.round(area.y + (area.h - size[1]) / 2)];
            return `hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, ${target} })) `
                + `hl.dispatch(hl.dsp.window.resize({ ${target}, x = ${size[0]}, y = ${size[1]} })) `
                + `hl.dispatch(hl.dsp.window.move({ ${target}, x = ${at[0]}, y = ${at[1]} })) `;
        }

        const zone = wanted === "refit" ? entry?.zone : wanted;
        if (!zone)
            return "";
        // Where it stood before the first placement, kept across later ones:
        // snapped and then maximised, it still goes back to where it stood.
        root.setPlaced(client.address, { zone: zone, before: entry?.before ?? { at: client.at, size: client.size } });
        const rect = root.zoneRect(root.workArea(monitor), zone);
        // A maximised window is told so, and draws itself that way. A snapped
        // one is not: Windows draws it as an ordinary window.
        return `hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = ${zone === "maximized" ? 1 : 0}, ${target} })) `
            + `hl.dispatch(hl.dsp.window.resize({ ${target}, x = ${rect.w}, y = ${rect.h} })) `
            + `hl.dispatch(hl.dsp.window.move({ ${target}, x = ${rect.x}, y = ${rect.y} })) `;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "maximizerequest") {
                const [address, state] = event.data.split(",");
                root.request(`0x${address}`, state === "1" ? "maximized" : "restore");
            } else if (event.name === "closewindow") {
                // Gone, and its address may be handed to another window. The
                // compositor has let go of it already.
                const next = Object.assign({}, root.placed);
                delete next[`0x${event.data}`];
                root.placed = next;
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
        onPressed: root.toggleMaximized(HyprlandData.windowList.find(client => client.focusHistoryID === 0)?.address ?? "")
    }

    IpcHandler {
        target: "placement"

        function toggleMaximized(address: string): void {
            root.toggleMaximized(address);
        }
        function place(address: string, zone: string): void {
            root.place(address, zone);
        }
        function restore(address: string): void {
            root.restore(address);
        }
        function list(): string {
            return JSON.stringify(root.placed);
        }
    }
}

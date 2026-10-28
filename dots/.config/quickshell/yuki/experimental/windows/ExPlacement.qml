import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.core
import qs.core.services
import qs.experimental.looks

// Where a window is put as Windows puts it: maximised, or snapped to half of
// its screen or a quarter of it, and put back where it stood.
//
// Every placement is a floating window given a part of the work area, the
// screen less what the dock reserves. Hyprland maximises a window as a kind of
// fullscreen that only one window per workspace can have and that is not raised
// over floating windows, so this family suppresses that with a window rule, and
// a window's own request to maximise reaches here through the minimize plugin.
// A maximised application is still told it is maximised, so it draws itself
// that way, while the compositor treats it as an ordinary window, tagged.
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

    /**
     * Whether the compositor shows a window as maximised here, by the tag it
     * was given, for one this shell has not placed itself.
     */
    function markedMaximized(client): bool {
        return (client.tags ?? []).includes("maximized");
    }

    /** Changes what is known of a window here. What the compositor is told of it goes in `placedLua`. */
    function setPlaced(address: string, entry) {
        const next = Object.assign({}, root.placed);
        if (entry)
            next[address] = entry;
        else
            delete next[address];
        root.placed = next;
    }

    /**
     * Lua telling the compositor where a placed window is placed and where it
     * stood before, which it remembers as the window closes and a shell
     * started anew reads back, or that it is placed no more. Sent in the same
     * chunk as the placement: in a process of its own it could arrive before
     * or after it.
     */
    function placedLua(address: string, entry): string {
        const key = `YUKI_PLACED["${address}"]`;
        const before = entry?.before;
        return before
            ? `YUKI_PLACED = YUKI_PLACED or {} ${key} = { zone = "${entry.zone}", x = ${before.at[0]}, y = ${before.at[1]}, w = ${before.size[0]}, h = ${before.size[1]} } `
            : `if YUKI_PLACED then ${key} = nil end `;
    }

    /**
     * The room left round a placed window, and between two standing side by
     * side. With the dock standing off the edge the windows stand off it too,
     * by as much, and keep their round corners. Against an attached dock they
     * meet the edges and each other, as on Windows.
     */
    readonly property real gap: Config.options.experimental.dock.style !== "attached" ? ExLooks.dock.floatingGap : 0

    /**
     * Lua marking a window by its placement: "maximized", "snapped" for the
     * halves and quarters, or neither, which is how a shell started anew
     * knows it, and the tags the compositor rules draw it by. Against the
     * edges, with no gap, "square" takes its round corners off, and a
     * maximised one is "bare" as well, with no border or shadow. For an X11
     * window, whether it is maximised, which
     * Hyprland never tells one, so it draws itself to match and its own
     * maximise button means what it shows. It is sent before the window is
     * resized, which is what carries it to the window.
     *
     * A Wayland window is left as Hyprland has it, told it is maximised and
     * tiled whatever its size: only then does a GTK window leave out the
     * margin it draws for its own shadow, which the compositor lined up with
     * neither its border nor its corners. Its maximise button, showing
     * "restore", is read as a toggle instead.
     */
    function marksFor(address: string, zone: string, x11: bool): string {
        const target = `window = "address:${address}"`;
        const maximized = zone === "maximized";
        const snapped = zone.length > 0 && !maximized;
        const flush = zone.length > 0 && root.gap === 0;
        return `hl.dispatch(hl.dsp.window.tag({ tag = "${maximized ? "+" : "-"}maximized", ${target} })) `
            + `hl.dispatch(hl.dsp.window.tag({ tag = "${snapped ? "+" : "-"}snapped", ${target} })) `
            + `hl.dispatch(hl.dsp.window.tag({ tag = "${flush ? "+" : "-"}square", ${target} })) `
            + `hl.dispatch(hl.dsp.window.tag({ tag = "${flush && maximized ? "+" : "-"}bare", ${target} })) `
            + (x11 ? `if hl.plugin.minimize and hl.plugin.minimize.set_window_state then hl.plugin.minimize.set_window_state("${address}", ${maximized}, true) end ` : "");
    }

    // A shell started anew learns what the one before it placed from the
    // compositor, which keeps each placement and where the window stood
    // before it. A window the compositor knows nothing of is judged by what
    // it shows, as the minimised windows are: one told it is maximised, or
    // covering the work area, is maximised, and one standing exactly on a half
    // or a quarter is snapped there, and given a size of its own when put back.
    //
    // Nothing is moved as it is learnt. The dock goes with the shell and comes
    // back a moment after it, so the work area read now is the screen without
    // it: fitted to that, a maximised window went on under the dock, and a
    // snapped one was let go of. The windows are fitted once the room the
    // layers reserve changes, the dock's coming back included.
    Component.onCompleted: adopter.running = true

    /** Placements the compositor kept, by address: { zone, before }, read as the shell starts. */
    property var kept: ({})
    /** The windows have been learnt, and a change in reserved room is acted on. */
    property bool adopted: false
    /** The room reserved along each monitor's edges, by name, as last acted on. */
    property var reservedSeen: ({})

    Process {
        id: adopter

        readonly property string path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/yuki-placed`

        command: ["sh", "-c", "rm -f \"$2\"; hyprctl eval \"$1\" >/dev/null 2>&1; cat \"$2\" 2>/dev/null; rm -f \"$2\"", "yuki-placed",
            `local f = io.open(${JSON.stringify(adopter.path)}, "w") if f then for a, e in pairs(YUKI_PLACED or {}) do if e.zone then f:write(a, "\\t", e.zone, "\\t", e.x, "\\t", e.y, "\\t", e.w, "\\t", e.h, "\\n") end end f:close() end`,
            adopter.path]
        stdout: StdioCollector {
            id: keptOutput

            onStreamFinished: {
                const kept = {};
                for (const line of keptOutput.text.split("\n")) {
                    const [address, zone, x, y, w, h] = line.split("\t");
                    if (!root.usable(address ?? "") || !root.zones.includes(zone) || h === undefined)
                        continue;
                    kept[address] = { zone: zone, before: { at: [Number(x), Number(y)], size: [Number(w), Number(h)] } };
                }
                root.kept = kept;
                root.request("*", "adopt");
            }
        }
    }

    // Every call reads the windows and the screens fresh: the shared lists are
    // a read behind, and a floating window moving raises no event at all.
    function request(address: string, wanted: string, before) {
        if (address !== "*" && !root.usable(address))
            return;
        if (address !== "*" && wanted !== "opened" && wanted !== "refit")
            root.decide(address);
        root.queue = [...root.queue, { address: address, wanted: wanted, before: before ?? null }];
        if (!reader.running)
            reader.running = true;
    }

    /**
     * Places a window. `before`, { at, size }, is where it goes back to when
     * put back, for a window that has moved since it stood there: one dragged
     * to an edge stands at the edge when it is placed. Without it, where the
     * window stands now.
     */
    function place(address: string, zone: string, before) {
        if (root.zones.includes(zone))
            root.request(address, zone, before);
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
        root.setPlaced(address, null);
        Quickshell.execDetached(["hyprctl", "eval", root.marksFor(address, "", HyprlandData.windowByAddress[address]?.xwayland ?? false) + root.placedLua(address, null)]);
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
                for (const job of queue) {
                    if (job.address === "*" && job.wanted === "layers") {
                        lua += root.fitToReserved(clients, monitors);
                    } else if (job.address === "*") {
                        lua += "YUKI_PLACED = {} ";
                        for (const client of clients)
                            lua += root.answer({ address: client.address, wanted: job.wanted }, clients, monitors);
                        root.reservedSeen = root.reservedOf(monitors);
                        root.adopted = true;
                    } else {
                        lua += root.answer(job, clients, monitors);
                    }
                }
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

    /** What the zones are cut from: the work area less the gap along its edges. */
    function placementArea(monitor): var {
        const area = root.workArea(monitor);
        return { x: area.x + root.gap, y: area.y + root.gap, w: area.w - 2 * root.gap, h: area.h - 2 * root.gap };
    }

    function reservedOf(monitors): var {
        const reserved = {};
        for (const monitor of monitors)
            reserved[monitor.name] = String(monitor.reserved ?? []);
        return reserved;
    }

    /** Fits the placed windows of every monitor whose reserved room has changed since it was last looked at. */
    function fitToReserved(clients, monitors): string {
        if (!root.adopted)
            return "";
        const now = root.reservedOf(monitors);
        const changed = monitors.filter(monitor => now[monitor.name] !== root.reservedSeen[monitor.name]).map(monitor => monitor.id);
        root.reservedSeen = now;
        let lua = "";
        for (const client of clients)
            if (root.placed[client.address] && changed.includes(client.monitor))
                lua += root.answer({ address: client.address, wanted: "refit" }, clients, monitors);
        return lua;
    }

    /** The part of a placement area a zone stands for, the gap left between neighbours. */
    function zoneRect(area, zone: string): var {
        const gap = root.gap;
        const halfW = Math.round((area.w - gap) / 2);
        const halfH = Math.round((area.h - gap) / 2);
        const farX = area.x + halfW + gap;
        const farY = area.y + halfH + gap;
        switch (zone) {
        case "left":
            return { x: area.x, y: area.y, w: halfW, h: area.h };
        case "right":
            return { x: farX, y: area.y, w: area.x + area.w - farX, h: area.h };
        case "topleft":
            return { x: area.x, y: area.y, w: halfW, h: halfH };
        case "topright":
            return { x: farX, y: area.y, w: area.x + area.w - farX, h: halfH };
        case "bottomleft":
            return { x: area.x, y: farY, w: halfW, h: area.y + area.h - farY };
        case "bottomright":
            return { x: farX, y: farY, w: area.x + area.w - farX, h: area.y + area.h - farY };
        }
        return area;
    }

    /**
     * Whether a window covers the work area, give or take a few pixels for an
     * application that leaves room for borders it does not draw.
     */
    function covers(client, area): bool {
        return client.size[0] >= area.w - 8 && client.size[1] >= area.h - 8;
    }

    /** Where a window placed before anything knew where it stood goes back to: a size of its own, centred. */
    function centred(area): var {
        const size = [Math.round(area.w * 0.6), Math.round(area.h * 0.7)];
        return { at: [Math.round(area.x + (area.w - size[0]) / 2), Math.round(area.y + (area.h - size[1]) / 2)], size: size };
    }

    /** The zone a window stands exactly on, or empty. */
    function zoneUnder(client, area): string {
        for (const zone of root.zones.filter(zone => zone !== "maximized")) {
            const rect = root.zoneRect(area, zone);
            if (Math.abs(client.at[0] - rect.x) <= 1 && Math.abs(client.at[1] - rect.y) <= 1
                    && Math.abs(client.size[0] - rect.w) <= 1 && Math.abs(client.size[1] - rect.h) <= 1)
                return zone;
        }
        return "";
    }

    function answer(job, clients, monitors): string {
        const client = clients.find(candidate => candidate.address === job.address);
        if (!client || !client.floating || client.workspace.id < 1 || client.fullscreen !== 0)
            return "";
        const monitor = monitors.find(candidate => candidate.id === client.monitor);
        if (!monitor)
            return "";
        // Whether a window is as large as the screen allows is judged by the
        // work area, where it stands and is put by the placement area.
        const area = root.workArea(monitor);
        const room = root.placementArea(monitor);
        const target = `window = "address:${client.address}"`;
        const entry = root.placed[client.address];
        let wanted = job.wanted;
        // Where it stood before the first placement, kept across later ones:
        // snapped and then maximised, it still goes back to where it stood.
        let before = job.before ?? entry?.before ?? { at: client.at, size: client.size };

        // An application's own request to be maximised or put back. A Wayland
        // window always believes it is maximised, so whichever it asks for
        // is the press of its maximise button, and toggles. An X11 window is
        // told the truth and is taken at its word.
        if (wanted === "asked:1" || wanted === "asked:0")
            wanted = client.xwayland ? (wanted === "asked:1" ? "maximized" : "restore") : "toggle";

        if (wanted === "toggle")
            wanted = entry?.zone === "maximized" || (!entry && root.markedMaximized(client)) ? "restore" : "maximized";

        if (wanted === "adopt") {
            // A Wayland window an older shell told it was not maximised is
            // told so again, as Hyprland tells every one.
            let asHyprland = client.xwayland ? "" : `if hl.plugin.minimize and hl.plugin.minimize.set_window_state then hl.plugin.minimize.set_window_state("${client.address}", true, true) end `;
            // One an older shell marked as maximised with Hyprland's fullscreen
            // state has its states in step again, or its own request for
            // fullscreen stays with the application alone. Only that mark:
            // a window told it is fullscreen on purpose, by the spoof key,
            // keeps it.
            if (client.fullscreenClient === 1 && client.fullscreen === 0)
                asHyprland += `hl.dispatch(hl.dsp.window.fullscreen_state({ internal = 0, client = 0, ${target} })) `;
            const kept = root.kept[client.address];
            if (kept) {
                wanted = kept.zone;
                before = kept.before;
            } else {
                wanted = client.fullscreenClient === 1 || root.markedMaximized(client) || root.covers(client, area) ? "maximized" : root.zoneUnder(client, room);
                before = root.centred(area);
            }
            if (!wanted)
                return asHyprland + root.marksFor(client.address, "", client.xwayland);
            return asHyprland + root.answer({ address: client.address, wanted: wanted, before: before, stay: true }, clients, monitors);
        }

        // An application that opens as large as the work area is taken to want
        // to be maximised, and is, as GNOME does: Steam, say, sizes itself to
        // the screen without saying it is maximised.
        if (wanted === "opened") {
            if (entry || root.decided[client.address] || !root.covers(client, area))
                return "";
            wanted = "maximized";
            before = root.centred(area);
        }

        if (wanted === "restore") {
            if (!entry && !root.markedMaximized(client))
                return "";
            root.setPlaced(client.address, null);
            // Known only for a window placed here since the shell started. One
            // placed before is given a size of its own, centred.
            const back = entry?.before ?? root.centred(area);
            return root.marksFor(client.address, "", client.xwayland) + root.placedLua(client.address, null)
                + `hl.dispatch(hl.dsp.window.resize({ ${target}, x = ${back.size[0]}, y = ${back.size[1]} })) `
                + `hl.dispatch(hl.dsp.window.move({ ${target}, x = ${back.at[0]}, y = ${back.at[1]} })) `;
        }

        const zone = wanted === "refit" ? entry?.zone : wanted;
        if (!zone || !root.zones.includes(zone))
            return "";
        const placement = { zone: zone, before: before };
        root.setPlaced(client.address, placement);
        const rect = root.zoneRect(room, zone);
        // Learnt rather than placed, it stays where it stands, and one fitted
        // again that already fits is not touched.
        const fits = client.at[0] === rect.x && client.at[1] === rect.y && client.size[0] === rect.w && client.size[1] === rect.h;
        if (job.stay || (wanted === "refit" && fits))
            return root.marksFor(client.address, zone, client.xwayland) + root.placedLua(client.address, placement);
        // Hyprland's own fullscreen state is left alone. Set to anything,
        // its two halves stop following each other, and the window's own
        // request for fullscreen, F11 in a browser, then reached only the
        // application, which hid its tool bars inside a maximised frame.
        return root.marksFor(client.address, zone, client.xwayland) + root.placedLua(client.address, placement)
            + `hl.dispatch(hl.dsp.window.resize({ ${target}, x = ${rect.w}, y = ${rect.h} })) `
            + `hl.dispatch(hl.dsp.window.move({ ${target}, x = ${rect.x}, y = ${rect.y} })) `;
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (event.name === "maximizerequest") {
                const [address, state] = event.data.split(",");
                root.request(`0x${address}`, `asked:${state}`);
            } else if (event.name === "openwindow") {
                root.watchOpened(`0x${event.data.split(",")[0]}`);
            } else if (event.name === "closewindow") {
                // Gone, and its address may be handed to another window. The
                // compositor has let go of it already.
                const next = Object.assign({}, root.placed);
                delete next[`0x${event.data}`];
                root.placed = next;
                delete root.decided[`0x${event.data}`];
            } else if (event.name === "monitoradded" || event.name === "monitorremoved" || event.name === "configreloaded") {
                refitLater.restart();
            } else if (event.name === "openlayer" || event.name === "closelayer") {
                // The room the layers reserve may have changed: the dock came
                // back, or went.
                layersLater.restart();
            }
        }
    }

    // A window just opened is looked at twice: an X11 application in
    // particular often sizes itself a moment after it has appeared.
    property var opened: []

    // Windows placed or put back since they opened, by address, whose checks
    // are left out. A check reads where a window stands from a list read
    // before what was just decided for it took effect, sometimes in the same
    // batch: a window maximised and put back in its first second and a half
    // was maximised again by its own late check.
    property var decided: ({})

    function decide(address: string) {
        root.decided[address] = true;
        root.opened = root.opened.filter(check => check.address !== address);
    }

    function watchOpened(address: string) {
        if (!root.usable(address))
            return;
        const now = Date.now();
        root.opened = [...root.opened, { address: address, at: now + 400 }, { address: address, at: now + 1500 }];
        openedTimer.start();
    }

    Timer {
        id: openedTimer
        interval: 100
        repeat: true
        onTriggered: {
            const now = Date.now();
            const due = root.opened.filter(check => check.at <= now);
            root.opened = root.opened.filter(check => check.at > now);
            for (const check of due)
                root.request(check.address, "opened");
            if (root.opened.length === 0)
                openedTimer.stop();
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
    Timer {
        id: layersLater
        interval: 250
        onTriggered: root.request("*", "layers")
    }

    GlobalShortcut {
        name: "maximizeToggle"
        description: "Maximises the focused window or puts it back"
        onPressed: root.toggleMaximized(HyprlandData.windowList.find(client => client.focusHistoryID === 0)?.address ?? "")
    }

    /**
     * Where Super and an arrow takes a window from each placement, as Windows
     * does: up and down climb from the dock through where it stood to
     * maximised, a snapped half going through its quarters on the way, and
     * the opposite side puts a snapped window back where it stood. Null where
     * the key does nothing. Pressed towards another screen it stays put for
     * now.
     */
    readonly property var steps: ({
        "": { up: "maximized", down: "minimize", left: "left", right: "right" },
        maximized: { up: null, down: "restore", left: "left", right: "right" },
        left: { up: "topleft", down: "bottomleft", left: null, right: "restore" },
        right: { up: "topright", down: "bottomright", left: "restore", right: null },
        topleft: { up: "maximized", down: "left", left: null, right: "topright" },
        topright: { up: "maximized", down: "right", left: "topleft", right: null },
        bottomleft: { up: "left", down: "minimize", left: null, right: "bottomright" },
        bottomright: { up: "right", down: "minimize", left: "bottomleft", right: null }
    })

    function step(direction: string) {
        const client = HyprlandData.windowList.find(candidate => candidate.focusHistoryID === 0);
        if (!client || !client.floating || client.fullscreen !== 0 || client.workspace.id < 1)
            return;
        // One maximised before the shell started is told so but not known here.
        const zone = root.zoneOf(client.address) || (root.markedMaximized(client) ? "maximized" : "");
        const next = root.steps[zone]?.[direction] ?? null;
        if (next === "minimize")
            Minimize.minimize(client.address);
        else if (next === "restore")
            root.restore(client.address);
        else if (next)
            root.place(client.address, next);
    }

    GlobalShortcut {
        name: "snapLeft"
        description: "Snaps the focused window to the left, or steps it back"
        onPressed: root.step("left")
    }
    GlobalShortcut {
        name: "snapRight"
        description: "Snaps the focused window to the right, or steps it back"
        onPressed: root.step("right")
    }
    GlobalShortcut {
        name: "snapUp"
        description: "Maximises the focused window, or takes a snapped one to its upper quarter"
        onPressed: root.step("up")
    }
    GlobalShortcut {
        name: "snapDown"
        description: "Puts the focused window back where it stood, or minimises it"
        onPressed: root.step("down")
    }
    GlobalShortcut {
        name: "showDesktop"
        description: "Shows the desktop of the focused screen, or brings its windows back"
        onPressed: Minimize.toggleDesktop(Hyprland.focusedMonitor?.activeWorkspace?.id ?? -1)
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
        /** The same as Super and an arrow: left, right, up or down. */
        function step(direction: string): void {
            root.step(direction);
        }
        function list(): string {
            return JSON.stringify(root.placed);
        }
    }
}

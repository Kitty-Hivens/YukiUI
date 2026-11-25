import QtQuick

import qs.core
import qs.core.services

/**
 * What is worth knowing to get about this desktop, in groups: the keys, and
 * what the mouse and the touchpad do.
 *
 * A row names the key binds it is about by their descriptions, and its keys are
 * read from the compositor. Bound to another key, it shows that key, and bound
 * to none it is left out, so nothing here tells of a key that does not answer.
 * Binds meant for panels only another environment draws are not named.
 */
QtObject {
    id: root

    /**
     * The groups with something to show, each { glyph, hue, title, rows }, a
     * row { text, note, caps }, a cap { text }, { glyphs } or { mouse }.
     */
    readonly property var groups: {
        const shown = [];
        for (const group of root.known) {
            const rows = [];
            for (const row of group.rows) {
                const caps = row.caps ?? root.capsOf(row.binds, row.upTo ?? "");
                if (caps.length > 0)
                    rows.push({ text: row.text, note: row.note ?? "", caps: caps });
            }
            if (rows.length > 0)
                shown.push(Object.assign({}, group, { rows: rows }));
        }
        return shown;
    }

    readonly property var arrows: ({ Left: "arrow_back", Up: "arrow_upward", Down: "arrow_downward", Right: "arrow_forward" })
    readonly property var mouseButtons: ({ "mouse:272": "left", "mouse:273": "right" })
    readonly property var names: ({
        SUPER_L: "Super", SUPER_R: "Super", Return: "Enter", Slash: "/", Backslash: "\\", Period: ".", Comma: ",", Minus: "-", Equal: "=",
        Print: "PrtSc", Escape: "Esc", Delete: "Del", Space: Translation.tr("Space"), Page_Up: "PgUp", Page_Down: "PgDn"
    })

    function modifiers(mask: int): var {
        const held = [];
        if (mask & 64)
            held.push("Super");
        if (mask & 4)
            held.push("Ctrl");
        if (mask & 8)
            held.push("Alt");
        if (mask & 1)
            held.push("Shift");
        return held;
    }

    function capOf(key: string): var {
        if (root.arrows[key])
            return { glyphs: [root.arrows[key]] };
        if (root.mouseButtons[key])
            return { mouse: root.mouseButtons[key] };
        return { text: root.names[key] ?? (key.length === 1 ? key.toUpperCase() : key) };
    }

    /**
     * The keys of a row: what is held, then the key of each bind it names,
     * arrows together on one cap. `upTo` ends a run begun by the first key,
     * 1 to 0. Nothing when none of the binds is there.
     */
    function capsOf(descriptions: var, upTo: string): var {
        const found = descriptions.map(description => HyprlandKeybinds.keybinds.find(bind => bind.description === description && bind.key.length > 0)).filter(bind => bind !== undefined);
        if (found.length === 0)
            return [];
        // Super let go of on its own is bound as the key with itself held.
        const first = found[0];
        if (first.key === "SUPER_L" || first.key === "SUPER_R")
            return [{ text: "Super" }];
        const caps = root.modifiers(first.modmask).map(name => ({ text: name }));
        const keys = found.filter(bind => bind.modmask === first.modmask);
        if (upTo.length > 0) {
            caps.push({ text: `${root.capOf(first.key).text} … ${upTo}` });
        } else if (keys.every(bind => root.arrows[bind.key] !== undefined)) {
            caps.push({ glyphs: keys.map(bind => root.arrows[bind.key]) });
        } else {
            for (const bind of keys)
                caps.push(root.capOf(bind.key));
        }
        return caps;
    }

    readonly property bool snaps: Config.options.blueberry.snap.enabled

    readonly property var known: [
        {
            glyph: "web_asset",
            hue: 250,
            title: Translation.tr("Your windows"),
            rows: [
                { text: Translation.tr("Move a window"), note: root.snaps ? Translation.tr("Pull it by any part. At a side of the screen it takes half, at a corner a quarter, at the top all of it") : Translation.tr("Pull it by any part"), binds: ["Window: Move"] },
                { text: Translation.tr("Resize a window"), note: Translation.tr("By any part, and by an edge without Super"), binds: ["Window: Resize"] },
                { text: Translation.tr("Maximize"), binds: ["Window: Snap Up"] },
                { text: Translation.tr("Put back, then minimize"), binds: ["Window: Snap Down"] },
                { text: Translation.tr("Half of the screen"), binds: ["Window: Snap Left", "Window: Snap Right"] },
                { text: Translation.tr("Take the whole screen"), binds: ["Window: Fullscreen"] },
                { text: Translation.tr("Close a window"), binds: ["Window: Close"] }
            ]
        },
        {
            glyph: "explore",
            hue: 145,
            title: Translation.tr("Getting around"),
            rows: [
                { text: Translation.tr("Search and applications"), binds: ["Shell: Toggle search"] },
                { text: Translation.tr("Switch windows"), binds: ["Shell: Switch windows"] },
                { text: Translation.tr("Show the desktop"), binds: ["Window: Show desktop"] },
                { text: Translation.tr("Go to a workspace"), binds: ["Workspace: Focus 1"], upTo: "0" },
                { text: Translation.tr("The workspace beside"), binds: ["Workspace: Focus left", "Workspace: Focus right"] },
                { text: Translation.tr("Send the window to a workspace"), binds: ["Window: Send to workspace 1"], upTo: "0" },
                { text: Translation.tr("Game bar"), binds: ["Shell: Toggle widget overlay"] },
                { text: Translation.tr("This list"), binds: ["Shell: Toggle cheatsheet"] }
            ]
        },
        {
            glyph: "screenshot_region",
            hue: 20,
            title: Translation.tr("Screen and clipboard"),
            rows: [
                { text: Translation.tr("Snip the screen"), binds: ["Utilities: Snipping tool"] },
                { text: Translation.tr("The whole screen, to a file"), binds: ["Utilities: Screenshot >> clipboard & file"] },
                { text: Translation.tr("Record a part of the screen"), binds: ["Utilities: Record region (no sound)"] },
                { text: Translation.tr("Read text off the screen"), binds: ["Utilities: Character recognition >> clipboard"] },
                { text: Translation.tr("Pick a color"), binds: ["Utilities: Pick color #RRGGBB >> clipboard"] },
                { text: Translation.tr("Clipboard history"), binds: ["Utilities: Clipboard history >> clipboard"] },
                { text: Translation.tr("Magnify, nearer and farther"), binds: ["Screen: Zoom in", "Screen: Zoom out"] }
            ]
        },
        {
            glyph: "dock_to_bottom",
            hue: 195,
            title: Translation.tr("Dock"),
            rows: [
                { text: Translation.tr("Open or minimize an application"), caps: [{ mouse: "left" }] },
                { text: Translation.tr("The application's menu"), caps: [{ mouse: "right" }] },
                { text: Translation.tr("Clock: notifications and the calendar"), caps: [{ mouse: "left" }] },
                { text: Translation.tr("Icons: quick settings"), caps: [{ mouse: "left" }] }
            ]
        },
        {
            glyph: "power_settings_new",
            hue: 60,
            title: Translation.tr("Session"),
            rows: [
                { text: Translation.tr("Lock the screen"), binds: ["Session: Lock"] },
                { text: Translation.tr("Put to sleep"), binds: ["Session: Sleep"] },
                { text: Translation.tr("Log out, restart, shut down"), binds: ["Shell: Toggle session menu"] }
            ]
        },
        {
            glyph: "apps",
            hue: 300,
            title: Translation.tr("Apps"),
            rows: [
                { text: Translation.tr("Settings"), binds: ["App: Settings app"] },
                { text: Translation.tr("Files"), binds: ["App: File manager"] },
                { text: Translation.tr("Browser"), binds: ["App: Browser"] },
                { text: Translation.tr("Terminal"), binds: ["App: Terminal"] }
            ]
        },
        {
            glyph: "music_note",
            hue: 350,
            title: Translation.tr("Sound and media"),
            rows: [
                { text: Translation.tr("Play, pause"), binds: ["Media: Play/pause media"] },
                { text: Translation.tr("Previous and next track"), binds: ["Media: Previous track", "Media: Next track"] },
                { text: Translation.tr("Mute the sound"), binds: ["Media: Toggle mute"] },
                { text: Translation.tr("Mute the microphone"), binds: ["Media: Toggle mic"] }
            ]
        },
        {
            glyph: "healing",
            hue: 100,
            title: Translation.tr("When something hangs"),
            rows: [
                { text: Translation.tr("Task manager"), binds: ["App: Task manager"] },
                { text: Translation.tr("Kill a window"), note: Translation.tr("Then click it"), binds: ["Window: Forcefully zap a window"] },
                { text: Translation.tr("Restart the shell"), note: Translation.tr("The dock, the search, the notifications"), binds: ["Shell: Restart widgets"] }
            ]
        },
        {
            glyph: "trackpad_input",
            hue: -1,
            title: Translation.tr("Touchpad"),
            rows: HyprInput.touchpadDevice.length === 0 ? [] : [
                ...root.gestureRows(3, Config.options.blueberry.gestures.three),
                ...root.gestureRows(4, Config.options.blueberry.gestures.four)
            ]
        }
    ]

    readonly property var gestureNames: ({
        search: Translation.tr("Search and applications"),
        showDesktop: Translation.tr("Show the desktop"),
        notifications: Translation.tr("Notifications and the calendar"),
        quickSettings: Translation.tr("Quick settings"),
        maximize: Translation.tr("Maximize")
    })

    /** What so many fingers do on the touchpad, as the settings have it. */
    function gestureRows(fingers: int, set: var): var {
        const count = { text: fingers === 3 ? Translation.tr("3 fingers") : Translation.tr("4 fingers") };
        const sideways = { glyphs: ["arrow_back", "arrow_forward"] };
        const up = { glyphs: ["arrow_upward"] };
        const down = { glyphs: ["arrow_downward"] };
        if (set.mode === "move")
            return [
                { text: Translation.tr("Move the window under the pointer"), caps: [count, { glyphs: ["open_with"] }] },
                { text: Translation.tr("Take the whole screen"), caps: [count, { glyphs: ["pinch"] }] }
            ];
        const actions = set.mode === "workspaces" ? { sideways: "workspace", up: "search", down: "showDesktop" }
            : set.mode === "custom" ? { sideways: set.sideways, up: set.up, down: set.down } : {};
        const rows = [];
        if (actions.sideways === "workspace")
            rows.push({ text: Translation.tr("The workspace beside"), caps: [count, sideways] });
        if (root.gestureNames[actions.up])
            rows.push({ text: root.gestureNames[actions.up], caps: [count, up] });
        if (root.gestureNames[actions.down])
            rows.push({ text: root.gestureNames[actions.down], caps: [count, down] });
        return rows;
    }
}

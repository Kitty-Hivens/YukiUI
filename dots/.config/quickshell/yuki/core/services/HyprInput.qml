pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core
import qs.core.functions

/**
 * Keyboard and pointer settings, read from the compositor and written back into
 * the one file that is meant to hold a person's own.
 *
 * Two steps, because the compositor keeps them apart: a change is applied at
 * once through the lua dispatcher, and separately written into
 * `custom/general.lua` so it survives the next reload. Applied and not written,
 * it lasts until the config is reloaded; written and not applied, it would need
 * a reload to be felt.
 *
 * That file is chosen over the shell's own override slot because it is sourced
 * after it -- what is written to the override slot is beaten by whatever the
 * person has already put here, which on a machine that sets a layout there is
 * every time. It is hand-written and carries reasoning in comments, so a change
 * rewrites one value on one line and leaves every other byte where it was, and
 * refuses rather than guesses when the file is not written a line at a time.
 */
Singleton {
    id: root

    readonly property string path: FileUtils.trimFileProtocol(`${Directories.config}/hypr/custom/general.lua`)

    /** Layout codes in the order the compositor cycles them. */
    property list<string> layouts: []
    property string variants: ""
    /** The whole xkb option string, of which this only ever owns two entries. */
    property string options: ""
    property int repeatRate: 25
    property int repeatDelay: 600
    property bool numlock: false

    property bool touchpadNaturalScroll: false
    property bool touchpadDisableWhileTyping: true
    property bool touchpadClickfinger: false
    property real touchpadScrollFactor: 1.0

    /** The keyboard the compositor treats as the one being typed on. */
    property string mainKeyboard: ""
    /** Named rather than counted: a machine reports every device that can send a key as a keyboard. */
    property int keyboardCount: 0
    property string touchpadDevice: ""

    /** False once a write has found the file in a shape it will not edit. */
    property bool writable: true
    /** Whether the compositor has been asked yet. Before that, none of the above is a reading. */
    property bool ready: false
    property bool busy: false

    readonly property var switchShortcuts: ["", "grp:alt_shift_toggle", "grp:ctrl_shift_toggle", "grp:win_space_toggle", "grp:caps_toggle", "grp:alt_space_toggle", "grp:shifts_toggle"]
    readonly property var capsBehaviours: ["", "caps:none", "caps:escape", "caps:ctrl_modifier", "caps:backspace", "caps:super"]

    /** Every layout xkb knows, as { code, name }, in the order it names them. */
    property var availableLayouts: []

    function layoutName(code) {
        return root.availableLayouts.find(layout => layout.code === code)?.name ?? code;
    }

    /** The entry of an xkb option list that starts with a prefix, without the prefix. */
    function optionEntry(prefix) {
        const found = root.options.split(",").map(entry => entry.trim()).find(entry => entry.startsWith(prefix));
        return found ?? "";
    }

    /**
     * The option list with one prefix's entry replaced, and everything else left
     * in place: this owns the group switch and the caps key, and a person may
     * well have put other things in the same string.
     */
    function optionsWith(prefix, entry) {
        const kept = root.options.split(",").map(part => part.trim()).filter(part => part.length > 0 && !part.startsWith(prefix));
        if (entry.length > 0)
            kept.push(entry);
        return kept.join(",");
    }

    // -- Reading -------------------------------------------------------------

    readonly property var watched: [
        "input:kb_layout", "input:kb_variant", "input:kb_options",
        "input:repeat_rate", "input:repeat_delay", "input:numlock_by_default",
        "input:touchpad:natural_scroll", "input:touchpad:disable_while_typing",
        "input:touchpad:clickfinger_behavior", "input:touchpad:scroll_factor"
    ]

    function refresh() {
        readOptions.running = false;
        readOptions.running = true;
        readDevices.running = false;
        readDevices.running = true;
    }

    /** What hyprctl prints for an option that was never set. */
    function optionString(entry) {
        const value = entry.str ?? "";
        return value === "[[EMPTY]]" ? "" : value;
    }

    function takeOptions(text) {
        const seen = ({});
        text.split("\n").forEach(line => {
            if (line.trim().length === 0)
                return;
            try {
                const entry = JSON.parse(line);
                seen[entry.option] = entry;
            } catch (error) {
                // A line that is not an option is not an error worth stopping for.
            }
        });
        const layoutString = root.optionString(seen["input:kb_layout"] ?? ({}));
        root.layouts = layoutString.length > 0 ? layoutString.split(",").map(code => code.trim()) : [];
        root.variants = root.optionString(seen["input:kb_variant"] ?? ({}));
        root.options = root.optionString(seen["input:kb_options"] ?? ({}));
        root.repeatRate = seen["input:repeat_rate"]?.int ?? root.repeatRate;
        root.repeatDelay = seen["input:repeat_delay"]?.int ?? root.repeatDelay;
        root.numlock = (seen["input:numlock_by_default"]?.int ?? 0) === 1;
        root.touchpadNaturalScroll = (seen["input:touchpad:natural_scroll"]?.int ?? 0) === 1;
        root.touchpadDisableWhileTyping = (seen["input:touchpad:disable_while_typing"]?.int ?? 1) === 1;
        root.touchpadClickfinger = (seen["input:touchpad:clickfinger_behavior"]?.int ?? 0) === 1;
        root.touchpadScrollFactor = seen["input:touchpad:scroll_factor"]?.float ?? root.touchpadScrollFactor;
        root.ready = true;
    }

    function takeDevices(text) {
        const parsed = JSON.parse(text);
        const keyboards = parsed.keyboards ?? [];
        root.keyboardCount = keyboards.length;
        root.mainKeyboard = keyboards.find(keyboard => keyboard.main === true)?.name ?? "";
        // A touchpad is reported among the mice and says so only in its name;
        // there is no field that separates the two.
        root.touchpadDevice = (parsed.mice ?? []).map(mouse => mouse.name).find(name => name.includes("touchpad")) ?? "";
    }

    Process {
        id: readOptions
        running: true
        command: ["bash", "-c", root.watched.map(option => `hyprctl getoption -j ${option}`).join("; ")]
        stdout: StdioCollector {
            id: optionCollector
            onStreamFinished: root.takeOptions(optionCollector.text)
        }
    }

    // Read once from the rules xkb itself is driven by, so the list is the one
    // the compositor will accept rather than one written down here.
    Process {
        id: readLayouts
        running: true
        command: ["cat", "/usr/share/X11/xkb/rules/base.lst"]
        stdout: StdioCollector {
            id: layoutCollector
            onStreamFinished: {
                const found = [];
                let inside = false;
                layoutCollector.text.split("\n").forEach(line => {
                    if (line.startsWith("! ")) {
                        inside = line.trim() === "! layout";
                        return;
                    }
                    if (!inside)
                        return;
                    const entry = /^\s+(\S+)\s\s+(.+?)\s*$/.exec(line);
                    if (entry)
                        found.push({ code: entry[1], name: entry[2] });
                });
                root.availableLayouts = found;
            }
        }
    }

    Process {
        id: readDevices
        running: true
        command: ["hyprctl", "devices", "-j"]
        stdout: StdioCollector {
            id: deviceCollector
            onStreamFinished: {
                try {
                    root.takeDevices(deviceCollector.text);
                } catch (error) {
                    root.mainKeyboard = "";
                }
            }
        }
    }

    // -- Writing -------------------------------------------------------------

    /** A lua value as it should be written: a string is quoted, nothing else is. */
    function luaValue(value) {
        if (typeof value === "boolean")
            return value ? "true" : "false";
        if (typeof value === "number")
            return String(value);
        return `"${String(value).replace(/"/g, '\\"')}"`;
    }

    /** A line with its trailing comment taken off, so braces inside one are not counted. */
    function bare(line) {
        return line.replace(/--.*$/, "");
    }

    /**
     * The lines a named block occupies, found by following a path of names down
     * from a `hl.config({` call.
     *
     * Returns null for a file that is not written a line at a time -- a whole
     * table on one line is valid lua and this will not touch it, because a
     * rewrite it cannot see the shape of is how a config file gets corrupted.
     */
    function findBlock(lines, path) {
        const stack = [];
        for (let i = 0; i < lines.length; i++) {
            const body = root.bare(lines[i]);
            if (/^\s*hl\.config\s*\(\s*\{\s*$/.test(body)) {
                stack.push({ name: "", start: i });
                continue;
            }
            const opened = /^\s*(\w+)\s*=\s*\{\s*$/.exec(body);
            if (opened) {
                stack.push({ name: opened[1], start: i });
                continue;
            }
            if (/^\s*\}[,)\s]*$/.test(body)) {
                const closed = stack.pop();
                if (closed === undefined)
                    continue;
                const names = stack.map(frame => frame.name).filter(name => name.length > 0).concat([closed.name]);
                if (names.length === path.length && names.every((name, index) => name === path[index]))
                    return ({ start: closed.start, end: i });
            }
        }
        return null;
    }

    /**
     * Whether the file names this table somewhere this cannot read -- a whole
     * table on one line, most likely.
     *
     * Without asking, a table it could not find would simply be written again at
     * the end, and lua would take the later one: the setting would work, and the
     * file would carry two tables saying different things, the first of which
     * silently stopped mattering. Refusing is the smaller surprise.
     */
    function messyMention(lines, name) {
        const opener = new RegExp(`\\b${name}\\s*=\\s*\\{`);
        return lines.some(line => {
            const body = root.bare(line);
            if (/^\s*(\w+)\s*=\s*\{\s*$/.test(body))
                return false;
            return opener.test(body);
        });
    }

    /** The indentation of the lines inside a block. */
    function innerIndent(lines, block) {
        for (let i = block.start + 1; i < block.end; i++) {
            const indent = /^(\s+)\S/.exec(lines[i]);
            if (indent)
                return indent[1];
        }
        return (/^(\s*)/.exec(lines[block.start])[1]) + "    ";
    }

    /**
     * Writes one value at one place in the table.
     *
     * Returns the lines to write, the lines it was given when they already say
     * that, and null when the file is not in a shape it will edit -- three
     * answers rather than two, because "nothing to do" and "will not touch this"
     * ask for very different things from the caller.
     */
    function applyValue(lines, path, key, value) {
        const next = lines.slice();
        let block = root.findBlock(next, path);
        if (block === null) {
            if (root.messyMention(next, path[path.length - 1]))
                return null;
            const created = root.createBlock(next, path);
            if (created === null)
                return null;
            block = root.findBlock(created, path);
            if (block === null)
                return null;
            next.length = 0;
            created.forEach(line => next.push(line));
        }
        const written = `${key} = ${root.luaValue(value)},`;
        for (let i = block.start + 1; i < block.end; i++) {
            const found = /^(\s*)(\w+)\s*=\s*(.*)$/.exec(root.bare(next[i]));
            if (!found || found[2] !== key)
                continue;
            const line = found[1] + written;
            if (line === next[i])
                return lines;
            next[i] = line;
            return next;
        }
        next.splice(block.end, 0, root.innerIndent(next, block) + written);
        return next;
    }

    /**
     * Adds an empty table at the end of the file for a path the file does not
     * have. Only one level below a `hl.config` call is created at a time, which
     * is as deep as anything here goes.
     */
    function createBlock(lines, path) {
        if (path.length === 1) {
            const written = ["", "hl.config({", `    ${path[0]} = {`, "    },", "})"];
            let index = lines.length;
            while (index > 0 && lines[index - 1].trim().length === 0)
                index--;
            const next = lines.slice();
            next.splice(index, 0, ...written);
            return next;
        }
        const parent = root.findBlock(lines, path.slice(0, path.length - 1));
        if (parent === null)
            return null;
        const next = lines.slice();
        const indent = root.innerIndent(next, parent);
        next.splice(parent.end, 0, `${indent}${path[path.length - 1]} = {`, `${indent}},`);
        return next;
    }

    // -- Applying ------------------------------------------------------------

    /**
     * Sets options: at once in the compositor, and in the file so they are still
     * set after a reload.
     *
     * Several at a time rather than one call each, because two settings that
     * belong together -- a layout list and the variants beside it -- must not be
     * able to land one without the other, and because a write has to settle
     * before the next one can read the file it is about to change.
     */
    function setMany(entries) {
        if (root.busy)
            return;
        root.apply(entries);
        root.persist(entries);
    }

    function set(path, key, value) {
        root.setMany([({ path: path, key: key, value: value })]);
    }

    function renderTable(node) {
        const parts = Object.keys(node).map(key => {
            const value = node[key];
            const written = (value !== null && typeof value === "object") ? root.renderTable(value) : root.luaValue(value);
            return `${key} = ${written}`;
        });
        return `{ ${parts.join(", ")} }`;
    }

    function apply(entries) {
        const tree = ({});
        entries.forEach(entry => {
            let node = tree;
            entry.path.forEach(name => {
                node[name] = node[name] ?? ({});
                node = node[name];
            });
            node[entry.key] = entry.value;
        });
        applyProcess.command = ["hyprctl", "eval", `hl.config(${root.renderTable(tree)})`];
        applyProcess.running = false;
        applyProcess.running = true;
    }

    function persist(entries) {
        const text = configFile.text();
        let lines = text.length > 0 ? text.split("\n") : [];
        let changed = false;
        for (const entry of entries) {
            const next = root.applyValue(lines, entry.path, entry.key, entry.value);
            // Said out loud rather than left to be discovered: a page that cannot
            // write is a page that forgets everything it was told at the next
            // reload, and that is worth a line on the page.
            if (next === null) {
                root.writable = false;
                return;
            }
            if (next !== lines)
                changed = true;
            lines = next;
        }
        root.writable = true;
        if (!changed)
            return;
        root.busy = true;
        configFile.setText(lines.join("\n"));
        settleTimer.restart();
    }

    /** The variants beside the layouts, one per layout whether it has one or not. */
    function variantList() {
        const listed = root.variants.length > 0 ? root.variants.split(",").map(variant => variant.trim()) : [];
        const padded = listed.slice(0, root.layouts.length);
        while (padded.length < root.layouts.length)
            padded.push("");
        return padded;
    }

    /**
     * Writes a layout list and the variants that go with it in one change: xkb
     * pairs them by position, so a list of three layouts beside two variants is
     * not a smaller mistake than a wrong layout.
     */
    function writeLayouts(codes, variants) {
        if (root.busy)
            return;
        const paired = variants.slice(0, codes.length);
        while (paired.length < codes.length)
            paired.push("");
        const written = paired.some(variant => variant.length > 0) ? paired.join(",") : "";
        const entries = [({ path: ["input"], key: "kb_layout", value: codes.join(",") })];
        // Left out entirely when there are none either way: a line saying there
        // are no variants is a line the file did not have and does not need.
        if (written.length > 0 || root.variants.length > 0)
            entries.push({ path: ["input"], key: "kb_variant", value: written });
        // Said here before the compositor is asked, and corrected by its answer
        // if the answer disagrees. Waiting for the round trip meant a list that
        // did not move until a process had started, run and been read.
        root.layouts = codes;
        root.variants = written;
        root.setMany(entries);
    }

    function addLayout(code) {
        if (code.length === 0 || root.layouts.indexOf(code) !== -1)
            return;
        root.writeLayouts(root.layouts.concat([code]), root.variantList().concat([""]));
    }

    function removeLayout(index) {
        if (root.layouts.length <= 1 || index < 0 || index >= root.layouts.length)
            return;
        const codes = root.layouts.slice();
        const variants = root.variantList();
        codes.splice(index, 1);
        variants.splice(index, 1);
        root.writeLayouts(codes, variants);
    }

    /** Order is not decoration: the first layout is the one a session starts on. */
    function moveLayout(index, delta) {
        const target = index + delta;
        if (index < 0 || index >= root.layouts.length || target < 0 || target >= root.layouts.length)
            return;
        const codes = root.layouts.slice();
        const variants = root.variantList();
        [codes[index], codes[target]] = [codes[target], codes[index]];
        [variants[index], variants[target]] = [variants[target], variants[index]];
        root.writeLayouts(codes, variants);
    }

    Process {
        id: applyProcess
        command: ["true"]
    }

    Timer {
        id: settleTimer
        interval: 200
        onTriggered: root.busy = false
    }

    FileView {
        id: configFile
        path: root.path
        blockLoading: true
        watchChanges: true
        onFileChanged: reloadTimer.restart()
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: configFile.reload()
    }

    // The compositor is the source of truth for what is in force, and a reload
    // is when the files it was told about win again.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded" || event.name === "activelayout")
                root.refresh();
        }
    }
}

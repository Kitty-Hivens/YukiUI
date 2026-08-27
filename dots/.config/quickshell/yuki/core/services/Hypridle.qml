pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.core
import qs.core.functions

/**
 * The three things hypridle does when the machine is left alone, read from and
 * written back into its own config.
 *
 * The file is edited rather than regenerated. It is written by hand and carries
 * why things are the way they are -- on this machine a comment explains why
 * there is deliberately no screen-off listener -- so a change here touches the
 * lines of one listener and leaves every other byte where it was.
 *
 * Switching a listener off comments its block out rather than deleting it: the
 * timing and whatever was written around it survive, and switching it back on
 * restores exactly what was there. A listener the file never had is written
 * fresh, in the dialect the file already speaks.
 */
Singleton {
    id: root

    readonly property string path: FileUtils.trimFileProtocol(`${Directories.config}/hypr/hypridle.conf`)

    readonly property var kinds: ["lock", "screenOff", "suspend"]

    /** What a listener starts at when the file has none and one is asked for. */
    readonly property var defaults: ({
        lock: 300,
        screenOff: 600,
        suspend: 900
    })

    /**
     * Each listener as { state, seconds }, where state is "on" for a live block,
     * "off" for one that is commented out, and "absent" when the file has never
     * had one.
     */
    property var timings: ({
        lock: ({ state: "absent", seconds: 300 }),
        screenOff: ({ state: "absent", seconds: 600 }),
        suspend: ({ state: "absent", seconds: 900 })
    })

    /** Whether the daemon that acts on any of this is up. */
    property bool running: true

    /** Set while a write is settling, so a view can hold its controls still. */
    property bool busy: false

    function state(kind) {
        return root.timings[kind]?.state ?? "absent";
    }
    function seconds(kind) {
        return root.timings[kind]?.seconds ?? root.defaults[kind];
    }

    /**
     * Listeners that are switched on and will never be reached, because the
     * machine suspends first and stops counting.
     */
    readonly property var unreachable: {
        if (root.state("suspend") !== "on")
            return [];
        const limit = root.seconds("suspend");
        return ["lock", "screenOff"].filter(kind => root.state(kind) === "on" && root.seconds(kind) > limit);
    }

    /**
     * Which listener a block is, taken from what it runs rather than from its
     * order in the file: the same three things are spelled a dozen ways between
     * one machine and the next, and position means nothing.
     */
    function kindOf(command) {
        const text = command.toLowerCase();
        if (text.includes("suspend") || text.includes("hibernate"))
            return "suspend";
        // Both spellings of switching a screen off: the dispatcher takes "off",
        // and the lua form this config is written in takes "disable".
        if (text.includes("dpms") && (text.includes("off") || text.includes("disable")))
            return "screenOff";
        if (text.includes("lock"))
            return "lock";
        return "";
    }

    /**
     * Every line as { commented, body }, where body is what the line would say
     * with its comment marker and any trailing comment taken off.
     *
     * A commented-out listener still reads as a listener this way, which is what
     * lets one be switched back on instead of written again from scratch.
     */
    function tokenize(lines) {
        return lines.map(line => {
            const commented = /^\s*#\s?(.*)$/.exec(line);
            return ({
                commented: commented !== null,
                body: (commented ? commented[1] : line).replace(/#.*$/, "")
            });
        });
    }

    /**
     * The listener blocks, live and commented out, as the lines they occupy.
     *
     * Lines whose comment marker disagrees with the block's own are skipped: a
     * live block often carries a commented-out command it used to run, and that
     * command is not what the block does.
     */
    function scan(lines) {
        const tokens = root.tokenize(lines);
        const blocks = [];
        let open = null;
        for (let i = 0; i < tokens.length; i++) {
            const token = tokens[i];
            if (/^\s*listener\s*\{/.test(token.body)) {
                open = ({ start: i, end: -1, timeoutLine: -1, seconds: -1, command: "", commented: token.commented });
                continue;
            }
            if (open === null || token.commented !== open.commented)
                continue;
            if (/^\s*\}/.test(token.body)) {
                open.end = i;
                open.kind = root.kindOf(open.command);
                if (open.kind.length > 0 && open.seconds > 0)
                    blocks.push(open);
                open = null;
                continue;
            }
            const timeout = /^\s*timeout\s*=\s*(\d+)/.exec(token.body);
            if (timeout) {
                open.timeoutLine = i;
                open.seconds = parseInt(timeout[1]);
            } else if (/^\s*on-timeout\s*=/.test(token.body)) {
                open.command += " " + token.body;
            }
        }
        return blocks;
    }

    /** The live block for a kind if there is one, otherwise the disabled one. */
    function blockFor(blocks, kind) {
        return blocks.find(block => block.kind === kind && !block.commented)
            ?? blocks.find(block => block.kind === kind)
            ?? null;
    }

    function reread(text) {
        const lines = text.split("\n");
        const blocks = root.scan(lines);
        const next = ({});
        root.kinds.forEach(kind => {
            const block = root.blockFor(blocks, kind);
            next[kind] = block === null ? ({
                state: "absent",
                seconds: root.defaults[kind]
            }) : ({
                state: block.commented ? "off" : "on",
                seconds: block.seconds
            });
        });
        root.timings = next;
    }

    /** The $variables the file defines for itself. */
    function definitions(lines) {
        const found = ({});
        lines.forEach(line => {
            const parsed = /^\s*\$(\w+)\s*=\s*(.+?)\s*$/.exec(line);
            if (parsed)
                found["$" + parsed[1]] = parsed[2];
        });
        return found;
    }

    /**
     * What a listener written from scratch should run, said the way the file
     * already says things: its own variable where it defines one, and the lua
     * dispatch form where the rest of the file is written in it.
     */
    function commandFor(kind, lines) {
        const vars = root.definitions(lines);
        if (kind === "suspend")
            return ({
                timeout: vars["$suspend_cmd"] !== undefined ? "$suspend_cmd" : "systemctl suspend || loginctl suspend",
                resume: ""
            });
        if (kind === "lock")
            return ({
                timeout: vars["$lock_cmd"] !== undefined ? "$lock_cmd" : "loginctl lock-session",
                resume: ""
            });
        const lua = lines.some(line => line.includes("hl.dsp."));
        return lua ? ({
            timeout: "hyprctl dispatch 'hl.dsp.dpms({ action = \"disable\" })'",
            resume: "hyprctl dispatch 'hl.dsp.dpms({ action = \"enable\" })'"
        }) : ({
            timeout: "hyprctl dispatch dpms off",
            // Written with it, never without: a screen switched off by a listener
            // that has no on-resume stays off.
            resume: "hyprctl dispatch dpms on"
        });
    }

    function blockLines(kind, seconds, lines) {
        const command = root.commandFor(kind, lines);
        const block = ["listener {", `    timeout = ${seconds} # ${Math.round(seconds / 60)} mins`, `    on-timeout = ${command.timeout}`];
        if (command.resume.length > 0)
            block.push(`    on-resume = ${command.resume}`);
        block.push("}");
        return block;
    }

    /** Where a new listener goes: in timing order, so the file still reads down. */
    function insertAt(lines, blocks, seconds) {
        const later = blocks.filter(block => block.seconds > seconds).sort((a, b) => a.start - b.start);
        if (later.length > 0)
            return ({ index: later[0].start, atEnd: false });
        let index = lines.length;
        while (index > 0 && lines[index - 1].trim().length === 0)
            index--;
        return ({ index: index, atEnd: true });
    }

    /**
     * Rewrites one number, keeping the rest of the line: a trailing comment on a
     * timeout line usually says the same figure in minutes, and leaving a stale
     * one behind is worse than not writing at all.
     */
    function applySeconds(lines, kind, seconds) {
        const block = root.blockFor(root.scan(lines), kind);
        if (block === null)
            return null;
        const line = lines[block.timeoutLine];
        // The number first, and only then the comment that trails it: a line
        // whose number could not be found is left entirely alone rather than
        // ending up with a minute count that contradicts it.
        const renumbered = line.replace(/^(\s*(?:#\s*)?timeout\s*=\s*)\d+/, `$1${seconds}`);
        if (renumbered === line)
            return null;
        const rewritten = renumbered.replace(/(#\s*)\d+(\s*mins?\b)/i, `$1${Math.round(seconds / 60)}$2`);
        const next = lines.slice();
        next[block.timeoutLine] = rewritten;
        return next;
    }

    function setSeconds(kind, seconds) {
        root.edit(lines => root.applySeconds(lines, kind, seconds));
    }

    /**
     * Switches a listener on or off.
     *
     * Off comments the block out rather than removing it, so the timing and any
     * reasoning written beside it come back untouched when it is switched on
     * again. A kind the file has never had is written fresh.
     */
    function applyEnabled(lines, kind, on) {
        const blocks = root.scan(lines);
        const block = root.blockFor(blocks, kind);
        const next = lines.slice();
        if (block !== null) {
            if (block.commented !== on)
                return null;
            for (let i = block.start; i <= block.end; i++) {
                // The marker goes at the start of the line and the indentation
                // stays behind it, which is both how a block is usually commented
                // out and what makes taking the marker off again exact.
                if (on)
                    next[i] = next[i].replace(/^([ \t]*)#[ ]?/, "$1");
                else if (next[i].trim().length > 0)
                    next[i] = "# " + next[i];
            }
            return next;
        }
        if (!on)
            return null;
        const seconds = root.seconds(kind);
        const written = root.blockLines(kind, seconds, lines);
        const where = root.insertAt(lines, blocks, seconds);
        next.splice(where.index, 0, ...(where.atEnd ? [""].concat(written) : written.concat([""])));
        return next;
    }

    function setEnabled(kind, on) {
        root.edit(lines => root.applyEnabled(lines, kind, on));
    }

    /**
     * Runs one change over the file as it stands. The change either returns the
     * lines it wants written or nothing at all, which is how a change that turns
     * out to be no change writes nothing and restarts nothing.
     */
    function edit(change) {
        if (root.busy)
            return;
        const text = configFile.text();
        if (text.length === 0)
            return;
        const next = change(text.split("\n"));
        if (next === null)
            return;
        root.busy = true;
        configFile.setText(next.join("\n"));
        restartProcess.running = true;
    }

    /** Asks whether hypridle is up, which is the difference between all of this working and not. */
    function refresh() {
        probeProcess.running = false;
        probeProcess.running = true;
    }

    function restart() {
        if (root.busy)
            return;
        root.busy = true;
        restartProcess.running = true;
    }

    // hypridle reads its config once, at startup, so a new number means a new
    // process. Detached from the shell, the way the compositor starts it, or it
    // would go down with the next shell reload.
    Process {
        id: restartProcess
        command: ["bash", "-c", "pkill -x hypridle; sleep 0.3; setsid -f hypridle >/dev/null 2>&1"]
        onExited: {
            root.busy = false;
            root.refresh();
        }
    }

    Process {
        id: probeProcess
        command: ["pgrep", "-x", "hypridle"]
        stdout: StdioCollector {
            onStreamFinished: root.running = text.trim().length > 0
        }
    }

    FileView {
        id: configFile
        path: root.path
        // Read before anything is drawn. Loaded in the background, the page opens
        // for a moment showing three listeners switched off, which is a lie about
        // a machine that is about to lock itself.
        blockLoading: true
        watchChanges: true
        onFileChanged: reloadTimer.restart()
        onLoaded: root.reread(text())
    }

    Timer {
        id: reloadTimer
        interval: 100
        onTriggered: configFile.reload()
    }

    Component.onCompleted: {
        // Read once here as well: a blocking load has already happened by the
        // time this object exists, and its loaded signal is not there to catch.
        root.reread(configFile.text());
        root.refresh();
    }
}

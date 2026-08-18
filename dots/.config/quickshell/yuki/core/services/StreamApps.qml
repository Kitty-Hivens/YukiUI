pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.common
import qs.modules.common.functions

/**
 * Which application an audio stream belongs to.
 *
 * PipeWire describes a stream by the process that opened it, and for anything
 * built on Electron or Chromium that process is a helper calling itself
 * "Chromium". The mixer then lists the runtime instead of the program, which is
 * true and useless. The application is the first ancestor that is not a helper,
 * and its desktop entry carries the name and icon a person recognises.
 *
 * Resolution costs a process, so it only runs while something is displaying the
 * result, and each pid is resolved once.
 */
Singleton {
    id: root

    property int subscribers: 0
    readonly property bool watching: root.subscribers > 0

    // pid -> desktop entry id, or a bare token when nothing matches an entry
    property var tokens: ({})

    // Command names that say nothing about the program: the argument after them
    // is what carries the identity.
    readonly property var runtimes: ["electron", "chromium", "chrome", "chromium-browser", "node", "python", "java", "wine", "wine64", "sh", "bash"]

    readonly property var pids: {
        if (!root.watching)
            return [];
        const seen = [];
        for (const node of Audio.outputAppNodes.concat(Audio.inputAppNodes)) {
            const pid = node?.properties?.["application.process.id"] ?? "";
            if (pid.length > 0 && seen.indexOf(pid) === -1)
                seen.push(pid);
        }
        return seen;
    }

    onPidsChanged: resolveTimer.restart()
    onWatchingChanged: {
        if (root.watching)
            resolveTimer.restart();
    }

    Timer {
        id: resolveTimer
        interval: 200
        onTriggered: root.resolve()
    }

    function resolve() {
        // A pid that stopped playing is not coming back as the same program.
        // Kept around, its name and icon would be handed to whatever process
        // the kernel next hands the number to.
        const known = ({});
        let dropped = false;
        for (const pid of Object.keys(root.tokens)) {
            if (root.pids.indexOf(pid) === -1)
                dropped = true;
            else
                known[pid] = root.tokens[pid];
        }
        if (dropped)
            root.tokens = known;

        const unknown = root.pids.filter(pid => root.tokens[pid] === undefined);
        if (unknown.length === 0)
            return;
        resolveProc.command = ["sh", FileUtils.trimFileProtocol(`${Quickshell.shellPath("scripts/audio/stream_apps.sh")}`)].concat(unknown);
        resolveProc.running = true;
    }

    /**
     * A version suffix is part of the runtime, not of the program: Arch ships
     * Electron as electron42, and every release would otherwise be a new name.
     */
    function tokenFrom(first, second) {
        const command = first.split("/").pop().replace(/[0-9.]+$/, "");
        if (root.runtimes.indexOf(command) === -1)
            return command;
        if (!second || second.length === 0 || second.startsWith("-"))
            return command;

        // What a runtime is handed is a path into the program's own directory:
        // /usr/lib/pear-desktop/app.asar names the program in the folder, while
        // /usr/lib/firefox/firefox names it in the file.
        const parts = second.split("/").filter(part => part.length > 0);
        if (parts.length === 0)
            return command;
        const last = parts[parts.length - 1];
        if (parts.length >= 2 && /\.(asar|js|jar|py|pyc)$/.test(last))
            return parts[parts.length - 2];
        return last.replace(/\.[A-Za-z0-9]+$/, "");
    }

    /**
     * Every entry that describes this program, best first.
     *
     * More than one can: a locally written entry overriding the packaged one is
     * exactly how a program ends up named the way its user wants. The local one
     * is preferred for the name, but it is also the one likely to point at an
     * icon that was never installed, so the icon is picked separately.
     */
    function entriesFor(node) {
        const pid = node?.properties?.["application.process.id"] ?? "";
        const token = (root.tokens[pid] ?? "").toLowerCase();
        if (token.length === 0)
            return [];

        const byId = [];
        const byCommand = [];
        for (const entry of AppSearch.list) {
            const id = (entry.id ?? "").toLowerCase();
            if (id === token || id.endsWith(`.${token}`)) {
                byId.push(entry);
                continue;
            }
            const command = (entry.execString ?? entry.command ?? "").toString().toLowerCase().trim().split(/\s+/)[0] ?? "";
            if (command.length > 0 && command.split("/").pop() === token)
                byCommand.push(entry);
        }
        return byId.concat(byCommand);
    }

    function nameFor(node) {
        return root.entriesFor(node)[0]?.name ?? "";
    }

    function iconFor(node) {
        // An entry naming an icon nobody shipped is worse than the next entry
        // for the same program, which usually names one that exists.
        for (const entry of root.entriesFor(node)) {
            if (AppSearch.iconExists(entry.icon))
                return entry.icon;
        }
        return "";
    }

    Process {
        id: resolveProc
        stdout: StdioCollector {
            id: resolveCollector
            onStreamFinished: {
                const resolved = ({});
                for (const line of resolveCollector.text.trim().split("\n")) {
                    if (line.trim().length === 0)
                        continue;
                    const fields = line.split("\t");
                    if (fields.length < 2)
                        continue;
                    resolved[fields[0]] = root.tokenFrom(fields[1], fields[2] ?? "");
                }
                // A pid that resolved to nothing still counts as answered, so it
                // is not asked about again on every list change. Only the pids
                // still playing are carried over: see resolve().
                const merged = ({});
                for (const pid of root.pids)
                    merged[pid] = resolved[pid] ?? root.tokens[pid] ?? "";
                root.tokens = merged;
            }
        }
    }
}

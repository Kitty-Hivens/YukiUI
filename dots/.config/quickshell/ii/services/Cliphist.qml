pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root
    // property string cliphistBinary: FileUtils.trimFileProtocol(`${Directories.home}/.cargo/bin/stash`)
    property string cliphistBinary: "cliphist"
    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2
    property list<string> entries: []

    /**
     * The search index, built when something searches and not before.
     *
     * As a binding on the list it was rebuilt on every copy, whether or not
     * anyone had the clipboard search open -- several milliseconds of work per
     * copy for an answer usually nobody asked for. Dropped when the list
     * changes, and paid for by the first query after that.
     */
    property var preparedCache: null
    onEntriesChanged: root.preparedCache = null

    function preparedEntries() {
        if (!root.preparedCache) {
            root.preparedCache = root.entries.map(a => ({
                name: Fuzzy.prepare(`${a.replace(/^\s*\S+\s+/, "")}`),
                entry: a
            }));
        }
        return root.preparedCache;
    }

    function fuzzyQuery(search: string): var {
        if (search.trim() === "") {
            return entries;
        }
        if (root.sloppySearch) {
            const results = entries.slice(0, 100).map(str => ({
                entry: str,
                score: Levendist.computeTextMatchScore(str.toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
            return results
                .map(item => item.entry)
        }

        return Fuzzy.go(search, root.preparedEntries(), {
            all: true,
            key: "name"
        }).map(r => {
            return r.obj.entry
        });
    }

    function entryIsImage(entry) {
        return !!(/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(entry))
    }

    /**
     * The number cliphist files an entry under, which is all it needs to act on
     * one.
     *
     * Everything below asks by number and never by content. A listing carries
     * the first hundred characters of what was copied, and passing that on a
     * command line published it: a process command line is readable by every
     * account on the machine, and a hundred characters is a whole password.
     */
    function entryId(entry) {
        return (`${entry}`.match(/^\s*(\d+)/)?.[1]) ?? "";
    }

    function refresh() {
        readProc.running = true
    }

    function copy(entry) {
        const id = root.entryId(entry);
        if (id.length === 0)
            return;
        Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${id} | wl-copy`]);
    }

    function paste(entry) {
        const id = root.entryId(entry);
        if (id.length === 0)
            return;
        // Pressing the keys is what pastes. Reading the clipboard back out, as
        // this used to, only prints it to a stream nobody is holding.
        Quickshell.execDetached(["bash", "-c", `${root.cliphistBinary} decode ${id} | wl-copy; ${root.pressPasteCommand}`]);
    }

    function superpaste(count, isImage = false) {
        // Find entries
        const ids = entries.filter(entry => {
            if (!isImage) return true;
            return entryIsImage(entry);
        }).slice(0, count).map(entry => root.entryId(entry)).filter(id => id.length > 0);
        if (ids.length === 0)
            return;
        const pasteCommands = [...ids].reverse().map(id => `${root.cliphistBinary} decode ${id} | wl-copy && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`)
        // Act
        Quickshell.execDetached(["bash", "-c", pasteCommands.join(` && sleep ${root.pasteDelay} && `)]);
    }

    /**
     * Deletions wait their turn.
     *
     * Asked for while one was running, the command was rebuilt and emptied
     * before the waiting run ever got to use it, so the entry it named quietly
     * survived and came straight back in the refreshed list.
     */
    property var deleteQueue: []

    function deleteEntry(entry) {
        const id = root.entryId(entry);
        if (id.length === 0)
            return;
        root.deleteQueue = root.deleteQueue.concat([id]);
        root.runNextDelete();
    }

    function runNextDelete() {
        if (deleteProc.running || root.deleteQueue.length === 0)
            return;
        // The number alone is enough on standard input. Given as an argument it
        // is accepted, reports success and deletes nothing.
        deleteProc.command = ["bash", "-c", `echo '${root.deleteQueue[0]}' | ${root.cliphistBinary} delete`];
        deleteProc.running = true;
    }

    Process {
        id: deleteProc
        onExited: (exitCode, exitStatus) => {
            root.deleteQueue = root.deleteQueue.slice(1);
            if (root.deleteQueue.length > 0) {
                root.runNextDelete();
                return;
            }
            root.refresh();
        }
    }

    Process {
        id: wipeProc
        command: [root.cliphistBinary, "wipe"]
        onExited: (exitCode, exitStatus) => {
            root.refresh();
        }
    }

    function wipe() {
        wipeProc.running = true;
    }

    Connections {
        target: Quickshell
        function onClipboardTextChanged() {
            delayedUpdateTimer.restart()
        }
    }

    Timer {
        id: delayedUpdateTimer
        interval: Config.options.hacks.arbitraryRaceConditionDelay
        repeat: false
        onTriggered: {
            root.refresh()
        }
    }

    Process {
        id: readProc
        property list<string> buffer: []

        command: [root.cliphistBinary, "list"]

        // Emptied as this run begins, not when a refresh is asked for. Cleared
        // on request, it was cleared under a read already in progress: that read
        // then reported a list missing everything collected before the clear,
        // and the run queued behind it appended to the remains, listing entries
        // twice.
        onStarted: readProc.buffer = []

        stdout: SplitParser {
            onRead: (line) => {
                readProc.buffer.push(line)
            }
        }

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.entries = readProc.buffer
            } else {
                console.error("[Cliphist] Failed to refresh with code", exitCode, "and status", exitStatus)
            }
        }
    }

    IpcHandler {
        target: "cliphistService"

        function update(): void {
            root.refresh()
        }
    }
}

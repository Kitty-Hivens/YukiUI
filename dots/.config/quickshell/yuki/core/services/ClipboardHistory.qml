pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

import qs.core
import qs.core.functions

/**
 * The clipboard history, one for every environment: what was copied lately,
 * newest first, each entry with every form it was copied in. scripts/clipboard/
 * history.py keeps it, and leaves out anything a password manager marks as secret.
 * How it looks and how it is opened are each environment's own.
 *
 * Entries are { id, time, kind, preview, image, pinned, paths, forms }, kind being
 * "text", "image" or "files".
 */
Singleton {
    id: root

    /** Called by the shell as it comes up, so copies are kept from then on. Another process reading this keeps nothing. */
    function load() {
        watcher.running = true;
    }

    readonly property string script: FileUtils.trimFileProtocol(`${Directories.scriptPath}/clipboard/history.py`)
    readonly property string indexFile: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/yuki/clipboard/index.json`

    property var entries: []

    property real pasteDelay: 0.05
    property string pressPasteCommand: "ydotool key -d 1 29:1 47:1 47:0 29:0"
    property bool sloppySearch: Config.options?.search.sloppy ?? false
    property real scoreThreshold: 0.2

    /** An entry has gone back on the clipboard, or could not. */
    signal offered(string id, bool done)

    /** Puts an entry back on the clipboard, in every form it was copied in. */
    function copy(id: string) {
        offer.id = id;
        offer.command = ["python3", root.script, "offer", id];
        offer.running = true;
    }
    Process {
        id: offer
        property string id: ""
        onExited: exitCode => root.offered(offer.id, exitCode === 0)
    }

    /** Pins, deletes or clears, and reads the history again once done. */
    function run(...words) {
        action.createObject(root, { command: ["python3", root.script, ...words] }).running = true;
    }
    Component {
        id: action
        Process {
            id: job
            onExited: {
                index.reload();
                job.destroy();
            }
        }
    }

    function deleteEntry(id: string) {
        root.run("delete", id);
    }

    /** Everything not pinned. */
    function wipe() {
        root.run("clear");
    }

    /** Pastes the newest few, the oldest of them first. */
    function superpaste(count: int, imagesOnly: bool) {
        const ids = root.entries.filter(entry => !imagesOnly || entry.kind === "image").slice(0, count).map(entry => entry.id);
        if (ids.length === 0)
            return;
        const steps = [...ids].reverse().map(id => `python3 "$1" offer ${id} && sleep ${root.pasteDelay} && ${root.pressPasteCommand}`);
        Quickshell.execDetached(["bash", "-c", steps.join(` && sleep ${root.pasteDelay} && `), "superpaste", root.script]);
    }

    /**
     * The search index, built when something searches and not before: rebuilt as
     * the list changes, it cost several milliseconds per copy for an answer
     * usually nobody asked for.
     */
    property var preparedCache: null
    onEntriesChanged: root.preparedCache = null

    function preparedEntries() {
        if (!root.preparedCache)
            root.preparedCache = root.entries.map(entry => ({ name: Fuzzy.prepare(entry.preview ?? ""), entry: entry }));
        return root.preparedCache;
    }

    function fuzzyQuery(search: string): var {
        if (search.trim() === "")
            return root.entries;
        if (root.sloppySearch) {
            return root.entries.slice(0, 100).map(entry => ({
                entry: entry,
                score: Levendist.computeTextMatchScore((entry.preview ?? "").toLowerCase(), search.toLowerCase())
            })).filter(item => item.score > root.scoreThreshold)
                .sort((a, b) => b.score - a.score)
                .map(item => item.entry);
        }
        return Fuzzy.go(search, root.preparedEntries(), { all: true, key: "name" }).map(result => result.obj.entry);
    }

    // What is copied is kept as it is copied. Each copy kept says so with a line,
    // and the history is read again: a file that was not there as the shell
    // started is not watched for changes.
    //
    // Ended by the kernel as the shell ends. wl-paste reads nothing from the shell
    // and never noticed it gone, so every start of the shell left one more behind.
    Process {
        id: watcher
        command: ["setpriv", "--pdeathsig", "TERM", "--", "wl-paste", "--watch", "sh", "-c", 'python3 "$1" store; echo kept', "clipboard-history", root.script]
        stdout: SplitParser {
            onRead: index.reload()
        }
    }

    FileView {
        id: index
        path: root.indexFile
        watchChanges: true
        printErrors: false
        onFileChanged: index.reload()
        onLoaded: {
            try {
                root.entries = JSON.parse(index.text());
            } catch (error) {
                root.entries = [];
            }
        }
        onLoadFailed: root.entries = []
    }
}

pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.core
import qs.core.functions

/**
 * The clipboard history behind Win+V: what was copied lately, newest first,
 * and putting an entry back and pasting it where the person was. Drawn by the
 * dock, as DockClipboard.
 *
 * Every form an entry was copied in is kept, and goes back on with it, so
 * files copied in the file manager paste as files again. scripts/clipboard/
 * history.py keeps them, as they are copied, and leaves out anything a
 * password manager marks as secret.
 */
Singleton {
    id: root

    /** Called by the environment as it comes up, so copies are kept from then on, opened or not. */
    function load() {}

    readonly property string script: FileUtils.trimFileProtocol(`${Directories.scriptPath}/clipboard/history.py`)
    readonly property string indexFile: `${Quickshell.env("XDG_STATE_HOME") || `${Quickshell.env("HOME")}/.local/state`}/yuki/clipboard/index.json`

    property var entries: []
    /** The history is up on a dock, as the dock says. */
    property bool open: false

    /** The window to paste into, and what it is, as they were when the history was asked for. */
    property string target: ""
    property string targetClass: ""

    /** Asks the dock of the focused screen to show the history, or to put it away. */
    signal toggleRequested
    signal closeRequested

    /** Terminals take a paste on Ctrl+Shift+V, Ctrl+V being a key of their own. */
    readonly property var terminals: ["kitty", "foot", "footclient", "Alacritty", "org.wezfurlong.wezterm", "com.mitchellh.ghostty",
        "org.gnome.Ptyxis", "org.gnome.Console", "org.kde.konsole", "xterm"]

    function toggle() {
        if (root.open) {
            root.closeRequested();
            return;
        }
        if (GlobalStates.screenLocked)
            return;
        // The window in use, before anything takes the keyboard from it.
        active.running = true;
    }
    Process {
        id: active
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            id: activeOut
            onStreamFinished: {
                let window = {};
                try {
                    window = JSON.parse(activeOut.text);
                } catch (error) {}
                root.target = window?.address ?? "";
                root.targetClass = window?.class ?? "";
                root.toggleRequested();
            }
        }
    }

    /** Puts an entry back on the clipboard, and pastes it where the person was. */
    function choose(id: string) {
        root.closeRequested();
        offer.command = ["python3", root.script, "offer", id];
        offer.running = true;
    }
    Process {
        id: offer
        onExited: exitCode => {
            if (exitCode === 0 && root.target.length > 0)
                pasteLater.restart();
        }
    }
    // Once the window has the keyboard back from the dock.
    Timer {
        id: pasteLater
        interval: 250
        onTriggered: {
            const mods = root.terminals.includes(root.targetClass) ? "CTRL SHIFT" : "CTRL";
            Hyprland.dispatch(`hl.dsp.send_shortcut({ mods = "${mods}", key = "V", window = "address:${root.target}" })`);
        }
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

    // What is copied is kept as it is copied, while this desktop is up. Each
    // copy kept says so with a line, and the history is read again: a file
    // that was not there as the shell started is not watched for changes.
    Process {
        running: true
        command: ["wl-paste", "--watch", "sh", "-c", 'python3 "$1" store; echo kept', "clipboard-history", root.script]
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

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.closeRequested();
        }
    }

    GlobalShortcut {
        name: "overviewClipboardToggle"
        description: "Opens or closes the clipboard history"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "clipboardHistory"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            if (!root.open)
                root.toggle();
        }
        function close(): void {
            root.closeRequested();
        }
        function isOpen(): bool {
            return root.open;
        }
        function entries(): string {
            return JSON.stringify(root.entries.map(entry => ({ id: entry.id, kind: entry.kind, preview: entry.preview, pinned: entry.pinned,
                forms: entry.forms.map(form => form.type) })));
        }
        function choose(index: int): void {
            const entry = root.entries[index];
            if (entry)
                root.choose(entry.id);
        }
    }
}

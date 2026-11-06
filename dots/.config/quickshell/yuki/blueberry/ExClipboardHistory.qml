pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.core.services

/**
 * The clipboard history as Win+V offers it here: opening it, and putting an entry
 * back and pasting it where the person was. Drawn by the dock, as DockClipboard.
 * What it holds is the shared ClipboardHistory.
 */
Singleton {
    id: root

    /** Called by the environment as it comes up, so copies are kept from then on, opened or not. */
    function load() {
        ClipboardHistory.load();
    }

    readonly property var entries: ClipboardHistory.entries
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
        root.choosing = id;
        ClipboardHistory.copy(id);
    }
    /** The entry going back on the clipboard to be pasted, or empty. */
    property string choosing: ""
    Connections {
        target: ClipboardHistory
        function onOffered(id: string, done: bool) {
            if (id !== root.choosing)
                return;
            root.choosing = "";
            if (done && root.target.length > 0)
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

    /** Pins, deletes or clears. */
    function run(...words) {
        ClipboardHistory.run(...words);
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

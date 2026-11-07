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
 * back on the clipboard, to be pasted wherever the person goes next. Drawn by the
 * dock, as DockClipboard. What it holds is the shared ClipboardHistory.
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
    /** The entry picked in it, by id, as the dock says. */
    property string picked: ""

    /** Asks the dock of the focused screen to show the history, or to put it away. */
    signal toggleRequested
    signal closeRequested

    function toggle() {
        if (root.open) {
            root.closeRequested();
            return;
        }
        if (!GlobalStates.screenLocked)
            root.toggleRequested();
    }

    /** Puts an entry back on the clipboard, and puts the history away. */
    function choose(id: string) {
        root.closeRequested();
        ClipboardHistory.copy(id);
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
        function picked(): string {
            return root.picked;
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

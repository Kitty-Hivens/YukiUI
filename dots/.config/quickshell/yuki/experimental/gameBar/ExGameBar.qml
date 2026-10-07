pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs
import qs.core
import qs.core.functions
import qs.core.services
import qs.experimental

// The game bar, as Windows 11 has it on Win+G: the screen dims, a bar at the
// top opens the widgets, and the widgets stand over the game where they were
// left: a picture or a video of the screen, how loud each program is, and how
// hard the machine is working. Win+G, Escape or a click beside the widgets
// puts it away.
//
// Nothing stays over the game once the bar is put away. A widget left on
// screen keeps a surface over a fullscreen game, and the compositor then
// draws every frame itself instead of handing the game's frames to the screen
// as they are, which is what variable refresh rides on.
Scope {
    id: root

    property bool open: false
    /** The screen the bar is on: the focused one as it opened. */
    property string screenName: ""
    /** Every widget there is, in the bar's order. */
    readonly property var widgets: ["capture", "audio", "performance"]
    /** The command last run for a capture, for the tests. */
    property var lastCommand: []

    function show() {
        // Nothing of this desktop belongs over the lock screen.
        if (GlobalStates.screenLocked)
            return;
        root.screenName = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        root.open = true;
    }
    function close() {
        root.open = false;
    }
    function toggle() {
        if (root.open)
            root.close();
        else
            root.show();
    }

    function isShown(key: string): bool {
        return Persistent.states.gameBar.open.includes(key);
    }
    function setShown(key: string, shown: bool) {
        const others = Persistent.states.gameBar.open.filter(other => other !== key);
        Persistent.states.gameBar.open = shown ? [...others, key] : others;
    }

    // What a widget does once the bar is out of the way, so the bar is not in
    // the picture: its surface is gone from the screen a frame or two after
    // it is let go.
    property var afterClose: null
    function closeThen(action) {
        root.afterClose = action;
        root.open = false;
        afterCloseTimer.restart();
    }
    Timer {
        id: afterCloseTimer
        interval: 150
        onTriggered: {
            const action = root.afterClose;
            root.afterClose = null;
            if (action)
                action();
        }
    }

    function run(command) {
        root.lastCommand = command;
        Quickshell.execDetached(command);
    }

    /**
     * The whole screen the bar is on, kept in the folder the snipping tool
     * saves in, and put on the clipboard as the picture and as the file.
     */
    function screenshot() {
        const output = root.screenName;
        const folder = Config.options.screenSnip.savePath;
        root.closeThen(() => root.run(["bash", "-c", 'shot=$(mktemp --suffix=.png) && grim -o "$1" "$shot" && exec bash "$2" "$shot" "$3"',
            "game-bar-screenshot", output, Directories.clipboardPictureScriptPath, folder]));
    }
    function snip() {
        root.closeThen(() => ExStates.snipAsked("image"));
    }
    /** Records the screen the bar is on, which is the focused one, until stopped. */
    function startRecording() {
        const command = ["bash", FileUtils.trimFileProtocol(Directories.recordScriptPath), "--fullscreen"];
        if (Persistent.states.gameBar.recordSound)
            command.push("--sound");
        root.closeThen(() => {
            root.run(command);
            CaptureWatch.recheck();
        });
    }
    function openRecordings() {
        root.closeThen(() => Qt.openUrlExternally(`file://${Config.options.screenRecord.savePath}`));
    }

    Connections {
        target: GlobalStates
        function onScreenLockedChanged() {
            if (GlobalStates.screenLocked)
                root.close();
        }
    }

    /** The bar's window while it is open, or null. */
    readonly property var window: windows.instances[0] ?? null

    Variants {
        id: windows

        model: root.open ? Quickshell.screens.filter(screen => screen.name === root.screenName).slice(0, 1) : []

        ExGameBarWindow {
            bar: root
        }
    }

    GlobalShortcut {
        name: "overlayToggle"
        description: "Opens or closes the game bar"
        onPressed: root.toggle()
    }

    IpcHandler {
        target: "gameBar"

        function toggle(): void {
            root.toggle();
        }
        function open(): void {
            root.show();
        }
        function close(): void {
            root.close();
        }
        function isOpen(): bool {
            return root.open;
        }
        function shown(): string {
            return JSON.stringify(root.widgets.filter(key => root.isShown(key)));
        }
        function setShown(key: string, shown: bool): void {
            root.setShown(key, shown);
        }
        function lastCommand(): string {
            return JSON.stringify(root.lastCommand);
        }
    }
}

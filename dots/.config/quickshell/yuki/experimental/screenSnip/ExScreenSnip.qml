pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import qs.core
import qs.core.functions
import qs.core.utils

// The snipping tool, as Windows 11 has it: the screens freeze and dim, a
// toolbar at the top picks a picture or a video, and a rectangle, a window or
// a whole screen is taken by drawing or clicking on it. What is taken goes to
// the clipboard, and to the folder the settings name, or to the markup editor,
// or through text recognition to the clipboard. A video records until the
// same key is pressed again.
//
// Searching the web with a picture is left out: it hands the picture to an
// upload service before anything is searched.
Scope {
    id: root

    property bool open: false
    /** "image" or "video". */
    property string media: "image"
    /** "rect", "window" or "screen". */
    property string area: "rect"
    /** A picture goes to the markup editor rather than the clipboard. */
    property bool markup: false
    /** A picture goes through text recognition, and its text to the clipboard. */
    property bool textOnly: false
    /** A video with the sound that is playing. */
    property bool sound: false
    /** The screen the toolbar and the keyboard are on: the focused one as it opened. */
    property string screenName: ""
    /** The command last run for a snip, for the tests. */
    property var lastCommand: []

    function action(): int {
        if (root.media === "video")
            return root.sound ? ScreenshotAction.Action.RecordWithSound : ScreenshotAction.Action.Record;
        if (root.textOnly)
            return ScreenshotAction.Action.CharRecognition;
        if (root.markup)
            return ScreenshotAction.Action.Edit;
        return ScreenshotAction.Action.Copy;
    }

    function openFor(media: string) {
        root.media = media;
        root.textOnly = false;
        root.markup = false;
        root.sound = false;
        // The first screen when the compositor has not named one yet, so
        // there is always one with the toolbar and the keyboard.
        root.screenName = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0]?.name ?? "";
        // Opened again while up, it starts over: the frozen picture is a new one.
        root.open = false;
        root.open = true;
    }

    function close() {
        root.open = false;
    }

    function run(command) {
        root.lastCommand = command;
        root.open = false;
        Quickshell.execDetached(command);
    }

    function pickColour() {
        root.open = false;
        // Once the frozen screens have gone, so the colour is of what is there.
        Quickshell.execDetached(["bash", "-c", "sleep 0.2; hyprpicker -a"]);
    }

    // A video already recording is stopped by the key that started it, and
    // nothing opens.
    function record(withSound: bool) {
        recordingCheck.withSound = withSound;
        recordingCheck.running = true;
    }
    Process {
        id: recordingCheck

        property bool withSound: false

        command: ["sh", "-c", "p=\"${XDG_RUNTIME_DIR:-/tmp}/yuki-recorder.pid\"; [ -s \"$p\" ] && kill -0 \"$(cat \"$p\")\" 2>/dev/null"]
        onExited: exitCode => {
            if (exitCode === 0) {
                Quickshell.execDetached(["bash", FileUtils.trimFileProtocol(Directories.recordScriptPath)]);
                return;
            }
            root.openFor("video");
            root.sound = recordingCheck.withSound;
        }
    }

    Variants {
        model: root.open ? Quickshell.screens : []

        ExSnipPanel {
            snip: root
        }
    }

    IpcHandler {
        target: "region"

        function screenshot(): void {
            root.openFor("image");
        }
        function ocr(): void {
            root.openFor("image");
            root.textOnly = true;
        }
        function record(): void {
            root.record(false);
        }
        function recordWithSound(): void {
            root.record(true);
        }
        function open(): void {
            root.openFor("image");
        }
        function close(): void {
            root.close();
        }
        function isOpen(): bool {
            return root.open;
        }
        function lastCommand(): string {
            return JSON.stringify(root.lastCommand);
        }
    }

    GlobalShortcut {
        name: "snipOpen"
        description: "Opens the snipping tool"
        onPressed: root.openFor("image")
    }
    GlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.openFor("image")
    }
    GlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: {
            root.openFor("image");
            root.textOnly = true;
        }
    }
    GlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region, or stops the recording"
        onPressed: root.record(false)
    }
    GlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound, or stops the recording"
        onPressed: root.record(true)
    }
}

pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.core
import QtQuick
import Quickshell

/**
 * Bridge between the yuki xdg-desktop-portal FileChooser backend and the shell.
 *
 * scripts/portal/filechooser.py answers the D-Bus interface, then opens this dialog
 * over IPC and blocks on a fifo until submit()/cancel() writes the answer back --
 * the same shape as ScreenShare and scripts/screenShare/picker.sh. The dialog lives
 * in the shell so it wears the family's widgets and the live palette rather than a
 * copy of them.
 */
Singleton {
    id: root

    // State for the single in-flight pick.
    property string fifoPath: ""
    property bool active: false
    property var request: ({})
    // Set while something external (not a cancel) tears the panel down.
    property bool suppressCancel: false
    // The last folder browsed, remembered across opens within this shell session so
    // a picker with no requested folder reopens where you left off.
    property string lastFolder: ""

    // request is the JSON the backend built (mode, title, filters, currentFolder...).
    function open(requestJson, fifo) {
        if (root.active)
            root.cancel(); // resolve any previous in-flight request before taking this one
        root.fifoPath = fifo;
        let parsed = ({});
        try {
            parsed = JSON.parse(requestJson);
        } catch (error) {
            parsed = ({});
        }
        root.request = parsed;
        root.active = true;
        sessionTimeout.restart();
        GlobalStates.filePickerOpen = true;
    }

    // uris: array of file:// strings. The backend reads this JSON off the fifo.
    function submit(uris) {
        if (!root.active)
            return;
        root.writeFifo(JSON.stringify({ "response": 0, "uris": uris }));
        root.finish();
    }

    function cancel() {
        if (!root.active) {
            GlobalStates.filePickerOpen = false;
            return;
        }
        root.writeFifo(""); // empty payload -> the backend reads nothing -> cancelled
        root.finish();
    }

    function finish() {
        sessionTimeout.stop();
        root.active = false;
        root.suppressCancel = false;
        root.request = ({});
        GlobalStates.filePickerOpen = false;
    }

    function writeFifo(payload) {
        // A fresh process per call so back-to-back writes can't clobber one another;
        // timeout guards against the fifo reader having already vanished.
        Quickshell.execDetached(["timeout", "5", "sh", "-c", "printf '%s' \"$1\" > \"$2\"", "filePicker", payload, root.fifoPath]);
    }

    Timer {
        id: sessionTimeout
        interval: 240000 // give up well before the backend's 300s cat timeout
        onTriggered: root.cancel()
    }

    // Focus-grab dismissal or any external close without a pick counts as a cancel.
    Connections {
        target: GlobalStates
        function onFilePickerOpenChanged() {
            if (!GlobalStates.filePickerOpen && root.active && !root.suppressCancel)
                root.cancel();
        }
    }
}

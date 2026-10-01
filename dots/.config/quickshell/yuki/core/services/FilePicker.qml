pragma Singleton
pragma ComponentBehavior: Bound
import qs
import qs.core
import QtQuick
import Quickshell
import Quickshell.Io

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
        GlobalStates.filePickerOpen = true;
    }

    /**
     * Whether the request answered through this fifo is still open. The
     * backend asks every few seconds and gives up on a request the shell no
     * longer holds, a shell that died or restarted included, which is what a
     * flat time limit used to stand in for: it cancelled a dialog still in use
     * after four minutes.
     */
    function pending(fifo: string): bool {
        return root.active && root.fifoPath === fifo;
    }

    /** The application gave up on the request, or went away. */
    function closeRequest(fifo: string) {
        if (root.pending(fifo))
            root.cancel();
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
        root.active = false;
        root.suppressCancel = false;
        root.request = ({});
        GlobalStates.filePickerOpen = false;
    }

    /**
     * Writes the answer into the fifo. Handed over on standard input, not as an
     * argument: one argument is capped at 128 KiB, which a large selection of
     * long names passes, and the write then failed while the dialog closed as if
     * it had gone through. A fresh process per answer, so two cannot interleave,
     * and a time limit in case the reader is gone.
     */
    function writeFifo(payload) {
        writer.createObject(root, { payload: payload, command: ["timeout", "5", "sh", "-c", "cat > \"$1\"", "filePicker", root.fifoPath] });
    }

    Component {
        id: writer

        Process {
            id: process

            property string payload: ""

            running: true
            stdinEnabled: true
            onStarted: {
                process.write(process.payload);
                process.stdinEnabled = false;
            }
            onExited: process.destroy()
        }
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

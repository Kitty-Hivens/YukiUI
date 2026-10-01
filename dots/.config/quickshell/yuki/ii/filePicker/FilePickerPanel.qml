import qs
import qs.core.services
import qs.common
import QtQuick
import Quickshell
import Quickshell.Io

// The file chooser is a real toplevel window, not a layer-shell overlay: a file
// dialog belongs in the window stack like every other one (movable, normally
// focused, survives over fullscreen), the way the GNOME dialog it stands in for
// does. It still lives in the shell process, so it keeps the family widgets and
// the live palette. A stable title lets the compositor float and centre it.
Scope {
    id: root

    Loader {
        id: pickerLoader
        active: GlobalStates.filePickerOpen

        sourceComponent: FloatingWindow {
            id: win
            title: "File picker"
            color: "transparent"
            implicitWidth: Appearance.sizes.filePickerWidth
            implicitHeight: Appearance.sizes.filePickerHeight
            minimumSize: Qt.size(560, 400)

            visible: GlobalStates.filePickerOpen
            onVisibleChanged: {
                // Closing the window (compositor close button) counts as a cancel.
                if (!visible)
                    FilePicker.cancel();
            }

            FilePickerContent {
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "filePicker"

        function open(request: string, fifo: string): void {
            FilePicker.open(request, fifo);
        }

        function close(): void {
            FilePicker.cancel();
        }
        function pending(fifo: string): bool {
            return FilePicker.pending(fifo);
        }
        function closeRequest(fifo: string): void {
            FilePicker.closeRequest(fifo);
        }
    }
}

import QtQuick
import Quickshell
import Quickshell.Io

import qs
import qs.core.services
import qs.blueberry.looks

// An application asking for a file to open or a place to save one. The exchange
// with the portal is the shared service's. The dialog is an ordinary window
// rather than an overlay: it sits in the window stack like the dialog it stands
// in for, can be moved, and does not cover the application that asked. Its
// title is what the compositor rules know it by.
Scope {
    id: root

    Loader {
        active: GlobalStates.filePickerOpen

        sourceComponent: FloatingWindow {
            title: "File picker"
            color: ExLooks.colors.surface
            implicitWidth: 900
            implicitHeight: 600
            minimumSize: Qt.size(600, 420)

            visible: GlobalStates.filePickerOpen
            // Closed from outside, by the compositor, without a choice.
            onVisibleChanged: {
                if (!visible)
                    FilePicker.cancel();
            }

            ExFilePickerContent {
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

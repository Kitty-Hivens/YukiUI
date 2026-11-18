import QtQuick
import Quickshell
import Quickshell.Hyprland
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
            // The screen in logical pixels, of the monitor the asking
            // application is on, which is where the focus is.
            readonly property real screenWidth: (Hyprland.focusedMonitor?.width ?? 1920) / (Hyprland.focusedMonitor?.scale || 1)
            readonly property real screenHeight: (Hyprland.focusedMonitor?.height ?? 1080) / (Hyprland.focusedMonitor?.scale || 1)

            title: "File picker"
            color: ExLooks.colors.surface
            // A share of the screen within bounds, as the welcome and the
            // settings: a size fixed for 1080p was small on a larger screen
            // and ran past the edges of a small one.
            implicitWidth: Math.round(Math.min(Math.max(screenWidth * 0.58, 760), 1600, screenWidth * 0.94))
            implicitHeight: Math.round(Math.min(Math.max(screenHeight * 0.6, 480), 1000, screenHeight * 0.9))
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

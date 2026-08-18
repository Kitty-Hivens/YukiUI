import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.core.functions
import qs.waffle
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    Loader {
        id: sessionLoader
        active: WStates.sessionOpen
        onActiveChanged: {
            if (sessionLoader.active) SessionWarnings.refresh();
        }

        Connections {
            target: GlobalStates
            function onScreenLockedChanged() {
                if (GlobalStates.screenLocked) {
                    WStates.sessionOpen = false;
                }
            }
        }

        sourceComponent: PanelWindow { // Session menu
            id: sessionRoot
            visible: sessionLoader.active
            property string subtitle
            
            function hide() {
                WStates.sessionOpen = false;
            }

            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:session"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
            // This is a big surface so we needa carefully choose the transparency,
            // or we'll get a large scary rgb blob
            color: "#000000"

            anchors {
                top: true
                left: true
                right: true
                bottom: true
            }

            Item {
                anchors.fill: parent
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        sessionRoot.hide();
                    }
                }

                SessionScreenContent {
                    anchors.fill: parent
                }
            }
        }
    }

    IpcHandler {
        target: "session"

        function toggle(): void {
            WStates.sessionOpen = !WStates.sessionOpen;
        }

        function close(): void {
            WStates.sessionOpen = false
        }

        function open(): void {
            WStates.sessionOpen = true
        }
    }

    GlobalShortcut {
        name: "sessionToggle"
        description: "Toggles session screen on press"

        onPressed: {
            WStates.sessionOpen = !WStates.sessionOpen;
        }
    }

    GlobalShortcut {
        name: "sessionOpen"
        description: "Opens session screen on press"

        onPressed: {
            WStates.sessionOpen = true
        }
    }

    GlobalShortcut {
        name: "sessionClose"
        description: "Closes session screen on press"

        onPressed: {
            WStates.sessionOpen = false
        }
    }

}

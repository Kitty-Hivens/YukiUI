import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.core.services
import qs.core
import qs.common.widgets
import qs.waffle
import qs.waffle.bar

Scope {
    id: root

    Connections {
        target: WStates

        function onSidebarLeftOpenChanged() {
            if (WStates.sidebarLeftOpen)
                WPanels.keepOnly("sidebarLeftOpen");
            if (WStates.sidebarLeftOpen)
                panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: WStates.sidebarLeftOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:actionCenter"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                bottom: Config.options.waffles.bar.bottom
                top: !Config.options.waffles.bar.bottom
                right: true
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight
            // Input only where the panel is drawn, so a click past it reaches what is
            // behind and the focus grab can close the panel.
            mask: Region {
                item: content.visibleArea
            }

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow].concat(WBarWindows.windows)
                onCleared: content.close()
            }

            Connections {
                target: WStates
                function onSidebarLeftOpenChanged() {
                    if (!WStates.sidebarLeftOpen)
                        content.close();
                }
            }

            ActionCenterContent {
                id: content
                anchors.fill: parent

                onClosed: {
                    WStates.sidebarLeftOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    function toggleOpen() {
        WStates.sidebarLeftOpen = !WStates.sidebarLeftOpen;
    }

    IpcHandler {
        target: "sidebarLeft"

        function toggle(): void {
            root.toggleOpen();
        }
    }

    GlobalShortcut {
        name: "sidebarLeftToggle"
        description: "Toggles left sidebar on press"

        onPressed: root.toggleOpen()
    }

    IpcHandler {
        target: "mediaControls"

        function toggle(): void {
            WStates.sidebarLeftOpen = !WStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            WStates.sidebarLeftOpen = !WStates.sidebarLeftOpen;
        }
    }
}

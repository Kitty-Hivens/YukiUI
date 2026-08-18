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
        target: GlobalStates

        function onSidebarLeftOpenChanged() {
            if (GlobalStates.sidebarLeftOpen)
                WPanels.keepOnly("sidebarLeftOpen");
            if (GlobalStates.sidebarLeftOpen)
                panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.sidebarLeftOpen
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
                target: GlobalStates
                function onSidebarLeftOpenChanged() {
                    if (!GlobalStates.sidebarLeftOpen)
                        content.close();
                }
            }

            ActionCenterContent {
                id: content
                anchors.fill: parent

                onClosed: {
                    GlobalStates.sidebarLeftOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    function toggleOpen() {
        GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
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
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }

    GlobalShortcut {
        name: "mediaControlsToggle"
        description: "Toggles media controls on press"

        onPressed: {
            GlobalStates.sidebarLeftOpen = !GlobalStates.sidebarLeftOpen;
        }
    }
}

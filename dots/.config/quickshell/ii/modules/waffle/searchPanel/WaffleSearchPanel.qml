import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onSearchPanelOpenChanged() {
            if (!GlobalStates.searchPanelOpen)
                return;
            // The two panels sit in the same place and answer the same query, so
            // one opening closes the other.
            GlobalStates.searchOpen = false;
            LauncherSearch.query = "";
            panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.searchPanelOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wSearchPanel"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            anchors {
                bottom: Config.options.waffles.bar.bottom
                top: !Config.options.waffles.bar.bottom
                left: Config.options.waffles.bar.leftAlignApps
            }

            implicitWidth: content.implicitWidth
            implicitHeight: content.implicitHeight
            mask: Region {
                item: content.visibleArea
            }

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                windows: [panelWindow]
                onCleared: content.close()
            }

            Connections {
                target: GlobalStates
                function onSearchPanelOpenChanged() {
                    if (!GlobalStates.searchPanelOpen)
                        content.close();
                }
            }

            SearchPanelContent {
                id: content
                anchors.fill: parent
                focus: true

                onClosed: {
                    GlobalStates.searchPanelOpen = false;
                    panelLoader.active = false;
                    LauncherSearch.query = "";
                }
            }
        }
    }

    IpcHandler {
        target: "searchPanel"

        function toggle(): void {
            GlobalStates.searchPanelOpen = !GlobalStates.searchPanelOpen;
        }
        function open(): void {
            GlobalStates.searchPanelOpen = true;
        }
        function close(): void {
            GlobalStates.searchPanelOpen = false;
        }
    }

    GlobalShortcut {
        name: "searchPanelToggle"
        description: "Toggles the search panel on press"

        onPressed: {
            GlobalStates.searchPanelOpen = !GlobalStates.searchPanelOpen;
        }
    }
}

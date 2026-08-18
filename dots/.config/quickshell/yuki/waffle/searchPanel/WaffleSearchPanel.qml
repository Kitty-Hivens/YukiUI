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

        function onSearchPanelOpenChanged() {
            if (!WStates.searchPanelOpen)
                return;
            // The two panels sit in the same place and answer the same query, and
            // the rest of the panels hanging off the bar put each other away too.
            WPanels.keepOnly("searchPanelOpen");
            LauncherSearch.query = "";
            panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: WStates.searchPanelOpen
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
                windows: [panelWindow].concat(WBarWindows.windows)
                onCleared: content.close()
            }

            Connections {
                target: WStates
                function onSearchPanelOpenChanged() {
                    if (!WStates.searchPanelOpen)
                        content.close();
                }
            }

            SearchPanelContent {
                id: content
                anchors.fill: parent
                focus: true

                onClosed: {
                    WStates.searchPanelOpen = false;
                    panelLoader.active = false;
                    LauncherSearch.query = "";
                }
            }
        }
    }

    IpcHandler {
        target: "searchPanel"

        function toggle(): void {
            WStates.searchPanelOpen = !WStates.searchPanelOpen;
        }
        function open(): void {
            WStates.searchPanelOpen = true;
        }
        function close(): void {
            WStates.searchPanelOpen = false;
        }
    }

    GlobalShortcut {
        name: "searchPanelToggle"
        description: "Toggles the search panel on press"

        onPressed: {
            WStates.searchPanelOpen = !WStates.searchPanelOpen;
        }
    }
}

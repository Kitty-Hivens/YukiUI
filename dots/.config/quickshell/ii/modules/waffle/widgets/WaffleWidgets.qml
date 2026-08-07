import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.waffle
import qs.modules.waffle.bar
import qs.modules.waffle.widgets

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onWidgetsOpenChanged() {
            if (GlobalStates.widgetsOpen)
                WPanels.keepOnly("widgetsOpen");
            if (GlobalStates.widgetsOpen)
                panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: GlobalStates.widgetsOpen
        sourceComponent: PanelWindow {
            id: panelWindow
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:wWidgets"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
            color: "transparent"

            // The board comes in from the left, where the button that opens it is.
            anchors {
                bottom: true
                top: true
                left: true
            }

            implicitWidth: content.maxWidth
            implicitHeight: content.implicitHeight
            mask: Region {
                item: content.visibleArea
            }

            HyprlandFocusGrab {
                id: focusGrab
                active: true
                // The picker stands in its own window; pressing it is not pressing
                // past the board.
                windows: [panelWindow].concat(WBarWindows.windows).concat(BoardState.pickerWindow ? [BoardState.pickerWindow] : [])
                onCleared: content.close()
            }

            Connections {
                target: GlobalStates
                function onWidgetsOpenChanged() {
                    if (!GlobalStates.widgetsOpen)
                        content.close();
                }
            }

            WidgetsContent {
                id: content
                anchors.fill: parent

                onClosed: {
                    // Arranging is a state of a board that is open.
                    BoardState.editing = false;
                    GlobalStates.widgetsOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    IpcHandler {
        target: "widgets"

        function toggle(): void {
            GlobalStates.widgetsOpen = !GlobalStates.widgetsOpen;
        }
        function open(): void {
            GlobalStates.widgetsOpen = true;
        }
        function close(): void {
            GlobalStates.widgetsOpen = false;
        }
        function refreshFeed(): void {
            NewsFeed.refresh();
        }
        function widen(): void {
            BoardState.wide = !BoardState.wide;
        }
        function arrange(): void {
            BoardState.editing = !BoardState.editing;
        }
    }

    GlobalShortcut {
        name: "widgetsToggle"
        description: "Toggles the widgets board on press"

        onPressed: {
            GlobalStates.widgetsOpen = !GlobalStates.widgetsOpen;
        }
    }
}

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
import qs.waffle.widgets

Scope {
    id: root

    Connections {
        target: GlobalStates

        function onWidgetsOpenChanged() {
            if (WStates.widgetsOpen)
                WPanels.keepOnly("widgetsOpen");
            if (WStates.widgetsOpen)
                panelLoader.active = true;
        }
    }

    Loader {
        id: panelLoader
        active: WStates.widgetsOpen
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

            // As wide as the screen, not as wide as the board: the picker stands
            // beside the board in a window of its own, and a card carried towards it
            // is dragged in this one.
            implicitWidth: panelWindow.screen?.width ?? content.maxWidth
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
                    if (!WStates.widgetsOpen)
                        content.close();
                }
            }

            WidgetsContent {
                id: content
                anchors.fill: parent

                // Arranging is a state of a board that is open, and it ends when the
                // board starts leaving rather than when it has gone: the picker
                // leaves on the same signal and would otherwise be left on screen
                // alone for the length of its own animation.
                onClosing: BoardState.editing = false
                onClosed: {
                    WStates.widgetsOpen = false;
                    panelLoader.active = false;
                }
            }
        }
    }

    IpcHandler {
        target: "widgets"

        function toggle(): void {
            WStates.widgetsOpen = !WStates.widgetsOpen;
        }
        function open(): void {
            WStates.widgetsOpen = true;
        }
        function close(): void {
            WStates.widgetsOpen = false;
        }
        function refreshFeed(): void {
            NewsFeed.refresh();
        }
        function widen(): void {
            BoardState.toggleWide();
        }
        function arrange(): void {
            BoardState.editing = !BoardState.editing;
        }
    }

    GlobalShortcut {
        name: "widgetsToggle"
        description: "Toggles the widgets board on press"

        onPressed: {
            WStates.widgetsOpen = !WStates.widgetsOpen;
        }
    }
}

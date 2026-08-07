pragma ComponentBehavior: Bound
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import Qt.labs.synchronizer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: overviewScope
    property bool dontAutoCancelSearch: false

    Variants {
        id: overviewVariants
        model: Quickshell.screens

        Loader {
            id: panelLoader
            required property var modelData
            active: false
            Connections {
                target: GlobalStates
                function onOverviewOpenChanged() {
                    if (GlobalStates.overviewOpen)
                        panelLoader.active = true;
                }
            }
            sourceComponent: PanelWindow {
                id: root
                property string searchingText: ""
                readonly property HyprlandMonitor monitor: Hyprland.monitorFor(root.screen)
                property bool monitorIsFocused: (Hyprland.focusedMonitor?.id == monitor?.id)
                screen: panelLoader.modelData

                WlrLayershell.namespace: "quickshell:wTaskView"
                WlrLayershell.layer: WlrLayer.Overlay
                // Exclusive, like the session screen and like the other family's
                // overview: OnDemand only hands the keyboard over on a click, so
                // Escape did nothing until the panel had been clicked first.
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
                color: "transparent"

                anchors {
                    top: true
                    bottom: true
                    left: true
                    right: true
                }

                // Nothing is clickable here once it is on its way out; otherwise the
                // press that closed it is followed by one the closing window still eats.
                Region {
                    id: noInput
                }
                mask: taskViewContent.closing ? noInput : null

                TaskViewContent {
                    id: taskViewContent
                    anchors.fill: parent

                    Component.onCompleted: {
                        taskViewContent.forceActiveFocus();
                    }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            GlobalStates.overviewOpen = false;
                        }
                    }

                    Connections {
                        target: GlobalStates
                        function onOverviewOpenChanged() {
                            if (!GlobalStates.overviewOpen)
                                taskViewContent.close();
                        }
                    }
                    onClosed: panelLoader.active = false
                }
            }
        }
    }

    // The task view and the start menu are two separate panels here, unlike in the
    // family this was adapted from, where one panel served as both. Sharing the
    // "search" target left whichever handler registered second doing nothing.
    IpcHandler {
        target: "overview"

        function toggle(): void {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function workspacesToggle(): void {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
        function close(): void {
            GlobalStates.overviewOpen = false;
        }
        function open(): void {
            GlobalStates.overviewOpen = true;
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
        }
    }
}

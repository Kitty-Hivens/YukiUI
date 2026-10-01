import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

import qs
import qs.core
import qs.core.services
import qs.experimental
import qs.experimental.looks

// The launcher: a panel of its own over the dock, on the screen in focus. A
// window rather than a popup of the dock, because it has to take the keyboard
// to be typed into, and a popup that takes no grab never gets it.
Scope {
    id: root

    property var targetScreen: null

    /** Holds the keyboard. Let go a moment after closing when the focus has to be made safe first. */
    property bool holdingKeys: false

    Connections {
        target: ExStates

        function onLauncherOpenChanged() {
            if (!ExStates.launcherOpen) {
                if (FocusReturn.beforeLettingGo())
                    letGo.restart();
                else
                    root.holdingKeys = false;
                return;
            }
            letGo.stop();
            handOver.stop();
            root.holdingKeys = true;
            const focused = Hyprland.focusedMonitor?.name ?? "";
            root.targetScreen = Quickshell.screens.find(screen => screen.name === focused) ?? Quickshell.screens[0];
            loader.active = true;
        }
    }

    // Time for the compositor to have let go of the focus before the launcher
    // lets go of the keyboard, and for that to land before focus is handed on.
    Timer {
        id: letGo
        interval: 80
        onTriggered: {
            root.holdingKeys = false;
            handOver.restart();
        }
    }
    Timer {
        id: handOver
        interval: 60
        onTriggered: FocusReturn.handOver()
    }

    Loader {
        id: loader
        active: false

        sourceComponent: PanelWindow {
            id: panel

            readonly property string edge: Config.options.experimental.dock.edge
            readonly property bool vertical: edge === "left" || edge === "right"
            readonly property bool centered: Config.options.experimental.dock.alignment !== "start"
            readonly property real shadowRoom: 32
            // What the dock takes up at its edge, which the panel stands clear of.
            readonly property real dockRoom: ExLooks.dock.thickness + (Config.options.experimental.dock.style !== "attached" ? ExLooks.dock.floatingGap : 0)

            screen: root.targetScreen
            color: "transparent"
            // Over the dock as well: a click on it, the launcher's own button
            // included, closes the launcher like any other click beside it.
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:launcher"
            WlrLayershell.layer: WlrLayer.Top
            WlrLayershell.keyboardFocus: root.holdingKeys ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            // The whole screen. Holding the keyboard exclusively, the launcher
            // gets no word from the compositor of a click beside it, which is
            // dropped instead, the dock's included, so it takes those clicks
            // itself and closes. On the way out only the panel takes the pointer.
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: ExStates.launcherOpen ? wholeWindow : panelOnly

            Region {
                id: wholeWindow
                item: beside
            }
            Region {
                id: panelOnly
                item: surface
            }

            MouseArea {
                id: beside
                anchors.fill: parent
                onPressed: ExStates.launcherOpen = false
            }

            // Taken once the panel holds the keyboard, not before. A layer
            // turning exclusive again ends whatever grab is up, its own
            // included, so reopened on its way out the launcher had its new
            // grab cleared at once and closed itself.
            HyprlandFocusGrab {
                windows: [panel]
                active: ExStates.launcherOpen && beside.Window.active
                onCleared: ExStates.launcherOpen = false
            }

            ExFlyoutSurface {
                id: surface

                open: ExStates.launcherOpen
                edge: panel.edge
                // Against the dock, along it where the dock gathers its icons.
                restX: panel.vertical ? (panel.edge === "left" ? panel.dockRoom + panel.shadowRoom : panel.width - width - panel.dockRoom - panel.shadowRoom)
                    : (panel.centered ? (panel.width - width) / 2 : panel.shadowRoom)
                restY: panel.vertical ? (panel.height - height) / 2
                    : (panel.edge === "top" ? panel.dockRoom + panel.shadowRoom : panel.height - height - panel.dockRoom - panel.shadowRoom)
                width: content.implicitWidth
                height: content.implicitHeight
                elevation: 2
                // Unloaded once the way out has been shown, not before.
                onProgressChanged: {
                    if (progress === 0 && !ExStates.launcherOpen)
                        loader.active = false;
                }

                LauncherContent {
                    id: content
                    anchors.fill: parent
                    Component.onCompleted: content.reset()

                    // Opened again while still on its way out, it is the same
                    // panel and still holds the last search.
                    Connections {
                        target: ExStates
                        function onLauncherOpenChanged() {
                            if (ExStates.launcherOpen)
                                content.reset();
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "search"

        function toggle(): void {
            ExStates.launcherOpen = !ExStates.launcherOpen;
        }
        function open(): void {
            ExStates.launcherOpen = true;
        }
        function close(): void {
            ExStates.launcherOpen = false;
        }
        function toggleReleaseInterrupt(): void {
            GlobalStates.superReleaseMightTrigger = false;
        }
    }

    GlobalShortcut {
        name: "searchToggle"
        description: "Toggles the launcher on press"
        onPressed: ExStates.launcherOpen = !ExStates.launcherOpen
    }
    GlobalShortcut {
        name: "searchToggleRelease"
        description: "Toggles the launcher when Super is released alone"
        onPressed: GlobalStates.superReleaseMightTrigger = true
        onReleased: {
            if (!GlobalStates.superReleaseMightTrigger) {
                GlobalStates.superReleaseMightTrigger = true;
                return;
            }
            ExStates.launcherOpen = !ExStates.launcherOpen;
        }
    }
    GlobalShortcut {
        name: "searchToggleReleaseInterrupt"
        description: "Keeps a Super release that came with another key from toggling the launcher"
        onPressed: GlobalStates.superReleaseMightTrigger = false
    }
}
